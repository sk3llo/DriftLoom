// SPDX-License-Identifier: GPL-3.0-or-later
import Combine
import Foundation

public struct FeedVideo: Identifiable, Equatable, Sendable {
    public let item: BrowseItem
    public let published: Date
    public var id: String { item.id }
    public init(item: BrowseItem, published: Date) { self.item = item; self.published = published }
}

public protocol FeedLoading: Sendable {
    func videos(channelID: String) async throws -> [FeedVideo]
}

public actor YouTubeFeedClient: FeedLoading {
    private let session: URLSession
    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCache = nil; config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
    }
    public func videos(channelID: String) async throws -> [FeedVideo] {
        do { return try await rssVideos(channelID: channelID) } catch {
            // YouTube's RSS feeds sometimes fail for every channel (404); the Videos tab still lists recent uploads.
            guard !SoundCloudID.isSoundCloud(channelID), channelID.hasPrefix("UC") else { throw error }
            let uploads = try await channelPageVideos(channelID: channelID)
            guard !uploads.isEmpty else { throw error }
            return uploads
        }
    }

    /// Recent uploads from the channel's Videos tab, read in English so their relative times can be dated.
    func channelPageVideos(channelID: String, now: Date = Date()) async throws -> [FeedVideo] {
        guard channelID.range(of: "^UC[A-Za-z0-9_-]{22}$", options: .regularExpression) != nil else { throw BrowseError.invalidInput }
        var url = URLComponents(string: "https://www.youtube.com/channel/\(channelID)/videos")!
        url.queryItems = [URLQueryItem(name: "hl", value: "en"), URLQueryItem(name: "gl", value: "US")]
        var request = URLRequest(url: url.url!)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/18.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.url?.host == "www.youtube.com", data.count <= 8_000_000,
              let html = String(data: data, encoding: .utf8) else { throw BrowseError.unavailable(L("This channel's feed could not be loaded.")) }
        return try Self.uploads(fromChannelPage: html, channelID: channelID, now: now)
    }

    static func uploads(fromChannelPage html: String, channelID: String, now: Date) throws -> [FeedVideo] {
        let page = BrowseParser.channelUploads(try BrowseParser.initialData(in: html))
        var seen = Set<String>()
        return page.uploads.compactMap { upload -> FeedVideo? in
            guard let date = RelativeTime.date(upload.age, now: now), seen.insert(upload.item.contentID).inserted else { return nil }
            let item = upload.item
            return FeedVideo(item: BrowseItem(contentID: item.contentID, kind: .video, title: item.title, subtitle: page.channel,
                                              thumbnail: item.thumbnail, duration: item.duration, channelID: channelID), published: date)
        }
    }

    private func rssVideos(channelID: String) async throws -> [FeedVideo] {
        if SoundCloudID.userNumber(channelID) != nil { return try await SoundCloudClient.shared.feed(channelID) }
        guard channelID.range(of: "^UC[A-Za-z0-9_-]{22}$", options: .regularExpression) != nil else { throw BrowseError.invalidInput }
        var url = URLComponents(string: "https://www.youtube.com/feeds/videos.xml")!
        url.queryItems = [URLQueryItem(name: "channel_id", value: channelID)]
        let (data, response) = try await session.data(from: url.url!)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.url?.host == "www.youtube.com", data.count <= 1_000_000 else {
            throw BrowseError.unavailable(L("This channel's feed could not be loaded."))
        }
        return try FeedXMLParser.parse(data, channelID: channelID)
    }
}

/// Relative times as YouTube's English pages write them: "13 min ago", "1h ago", "2 days ago", "Streamed 3w ago".
enum RelativeTime {
    private static let pattern = try! NSRegularExpression(pattern: #"(\d+)\s*(seconds?|secs?|s|minutes?|mins?|m|hours?|hrs?|h|days?|d|weeks?|wks?|w|months?|mos?|years?|yrs?|y)\b\s*ago"#, options: .caseInsensitive)
    static func date(_ text: String, now: Date = Date()) -> Date? {
        let text = text.replacingOccurrences(of: "\u{00A0}", with: " ")
        guard let match = pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let numberRange = Range(match.range(at: 1), in: text), let unitRange = Range(match.range(at: 2), in: text),
              let count = Double(text[numberRange]) else { return nil }
        let unit = text[unitRange].lowercased()
        let seconds: Double
        switch unit {
        case let u where u.hasPrefix("mo"): seconds = 30 * 86400
        case let u where u.hasPrefix("mi") || u == "m": seconds = 60
        case let u where u.hasPrefix("s"): seconds = 1
        case let u where u.hasPrefix("h"): seconds = 3600
        case let u where u.hasPrefix("d"): seconds = 86400
        case let u where u.hasPrefix("w"): seconds = 7 * 86400
        default: seconds = 365 * 86400
        }
        return now.addingTimeInterval(-count * seconds)
    }
}

final class FeedXMLParser: NSObject, XMLParserDelegate {
    private let channelID: String
    private var inEntry = false
    private var field = "", fields: [String: String] = [:]
    private var thumbnail: URL?
    private var results: [FeedVideo] = []
    init(channelID: String) { self.channelID = channelID }
    static func parse(_ data: Data, channelID: String) throws -> [FeedVideo] {
        let delegate = FeedXMLParser(channelID: channelID)
        let parser = XMLParser(data: data); parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else { throw BrowseError.unsupportedResponse }
        var seen = Set<String>()
        return delegate.results.filter { seen.insert($0.id).inserted }
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        if elementName == "entry" { inEntry = true; fields = [:]; thumbnail = nil }
        guard inEntry else { return }
        field = elementName
        if elementName == "media:thumbnail", let value = attributes["url"], let url = URL(string: value), url.scheme == "https" { thumbnail = url }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inEntry, ["yt:videoId", "title", "published", "name"].contains(field) { fields[field, default: ""] += string }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        defer { field = "" }
        guard elementName == "entry" else { return }
        inEntry = false
        guard let id = fields["yt:videoId"], (try? VideoRequest(input: id).videoID) == id,
              let title = fields["title"], !title.isEmpty,
              let rawDate = fields["published"], let date = ISO8601DateFormatter().date(from: rawDate) else { return }
        results.append(FeedVideo(item: BrowseItem(contentID: id, kind: .video, title: title,
                                                 subtitle: fields["name"] ?? "", thumbnail: thumbnail, channelID: channelID), published: date))
    }
}

@MainActor
public final class SubscriptionFeedStore: ObservableObject {
    @Published public private(set) var items: [FeedVideo] = []
    @Published public private(set) var loading = false
    @Published public private(set) var failedChannels = 0
    @Published public private(set) var completedChannels = 0
    private let client: any FeedLoading
    private var generation = UUID()
    private var requestedChannels: [String] = []
    public init(client: any FeedLoading = YouTubeFeedClient()) { self.client = client }
    public func load(channelIDs: [String]) async {
        let token = UUID(); generation = token
        loading = true; failedChannels = 0; completedChannels = 0
        var seen = Set<String>(), collected: [FeedVideo] = []
        let ids = channelIDs.filter { seen.insert($0).inserted }
        if ids != requestedChannels { items = []; requestedChannels = ids }
        // Bound simultaneous network requests, including for large imported subscription lists.
        for offset in stride(from: 0, to: ids.count, by: 3) {
            guard !Task.isCancelled, generation == token else { break }
            let batch = Array(ids[offset..<min(offset + 3, ids.count)])
            let results = await withTaskGroup(of: [FeedVideo]?.self, returning: [[FeedVideo]?].self) { group in
                for id in batch { group.addTask { [client] in try? await client.videos(channelID: id) } }
                var result: [[FeedVideo]?] = []
                for await value in group { result.append(value) }
                return result
            }
            guard !Task.isCancelled, generation == token else { break }
            completedChannels += results.count
            failedChannels += results.filter { $0 == nil }.count
            collected.append(contentsOf: results.compactMap { $0 }.flatMap { $0 })
        }
        guard generation == token else { return }
        if !Task.isCancelled {
            var videos = Set<String>()
            let sorted = collected.sorted { $0.published == $1.published ? $0.id < $1.id : $0.published > $1.published }
            items = Array(sorted.filter { videos.insert($0.id).inserted }.prefix(1000))
        }
        loading = false
    }
}
