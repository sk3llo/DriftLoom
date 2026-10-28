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
    private let dates: FeedDates
    public init(dates: FeedDates = .shared) {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCache = nil; config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
        self.dates = dates
    }
    public func videos(channelID: String) async throws -> [FeedVideo] {
        if SoundCloudID.isSoundCloud(channelID) { return try await rssVideos(channelID: channelID) }
        do {
            let videos = try await rssVideos(channelID: channelID)
            await dates.record(exact: videos)
            return videos
        } catch {
            guard channelID.hasPrefix("UC") else { throw error }
            // YouTube's channel RSS feeds sometimes fail for every channel (404). The uploads playlist's feed
            // still has exact times; failing that, the Videos tab lists recent uploads with their ages.
            if let videos = try? await rssVideos(channelID: channelID, uploadsPlaylist: true), !videos.isEmpty {
                await dates.record(exact: videos)
                return videos
            }
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
        let estimates = try Self.uploads(fromChannelPage: html, channelID: channelID, now: now)
        var resolved: [(video: FeedVideo, exact: Bool)] = []
        for estimate in estimates {
            let known = await dates.resolve(estimate.video.item.contentID, estimate: estimate.video.published, precision: estimate.precision)
            resolved.append((FeedVideo(item: estimate.video.item, published: known.date), known.exact))
        }
        return Self.keepingPageOrder(resolved)
    }

    /// The Videos tab's uploads with dates estimated from their ages, and how far off each estimate can be.
    static func uploads(fromChannelPage html: String, channelID: String, now: Date) throws -> [(video: FeedVideo, precision: TimeInterval)] {
        let page = BrowseParser.channelUploads(try BrowseParser.initialData(in: html))
        var seen = Set<String>()
        return page.uploads.compactMap { upload -> (FeedVideo, TimeInterval)? in
            guard let estimate = RelativeTime.estimate(upload.age, now: now), seen.insert(upload.item.contentID).inserted else { return nil }
            let item = upload.item
            return (FeedVideo(item: BrowseItem(contentID: item.contentID, kind: .video, title: item.title, subtitle: page.channel,
                                               thumbnail: item.thumbnail, duration: item.duration, channelID: channelID), published: estimate.date),
                    estimate.precision)
        }
    }

    /// The Videos tab lists newest first, so an estimate never puts an upload ahead of the one listed above it.
    static func keepingPageOrder(_ videos: [(video: FeedVideo, exact: Bool)]) -> [FeedVideo] {
        var result: [FeedVideo] = []
        for (video, exact) in videos {
            if !exact, let above = result.last?.published, video.published >= above {
                result.append(FeedVideo(item: video.item, published: above.addingTimeInterval(-1)))
            } else {
                result.append(video)
            }
        }
        return result
    }

    private func rssVideos(channelID: String, uploadsPlaylist: Bool = false) async throws -> [FeedVideo] {
        if SoundCloudID.userNumber(channelID) != nil { return try await SoundCloudClient.shared.feed(channelID) }
        guard channelID.range(of: "^UC[A-Za-z0-9_-]{22}$", options: .regularExpression) != nil else { throw BrowseError.invalidInput }
        var url = URLComponents(string: "https://www.youtube.com/feeds/videos.xml")!
        // A channel's uploads playlist is its ID with UU in place of UC.
        url.queryItems = [uploadsPlaylist ? URLQueryItem(name: "playlist_id", value: "UU" + channelID.dropFirst(2))
                                          : URLQueryItem(name: "channel_id", value: channelID)]
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
    static func date(_ text: String, now: Date = Date()) -> Date? { estimate(text, now: now)?.date }
    /// The date, and the size of the unit it was given in: "13 min ago" is good to a minute, "2d ago" to a day.
    static func estimate(_ text: String, now: Date = Date()) -> (date: Date, precision: TimeInterval)? {
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
        return (now.addingTimeInterval(-count * seconds), seconds)
    }
}

/// Upload dates remembered across checks. An exact RSS time always wins; an age read from the Videos tab keeps
/// its most precise sighting ("13 min ago" beats a later "1h ago"), so dates don't drift on every refresh.
public actor FeedDates {
    struct Entry: Codable, Equatable { var date: Date; var precision: TimeInterval }
    private var entries: [String: Entry]
    private let file: URL?
    private let limit: Int

    public static let shared = FeedDates(file: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("feed-dates.json"))

    init(file: URL?, limit: Int = 4000) {
        self.file = file; self.limit = limit
        entries = file.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
    }

    func record(exact videos: [FeedVideo]) {
        var changed = false
        for video in videos where entries[video.item.contentID] != Entry(date: video.published, precision: 0) {
            entries[video.item.contentID] = Entry(date: video.published, precision: 0); changed = true
        }
        if changed { save() }
    }

    /// `id` is the YouTube video ID.
    func resolve(_ id: String, estimate: Date, precision: TimeInterval) -> (date: Date, exact: Bool) {
        if let known = entries[id], known.precision <= precision { return (known.date, known.precision == 0) }
        entries[id] = Entry(date: estimate, precision: precision)
        save()
        return (estimate, false)
    }

    private func save() {
        if entries.count > limit {
            for (id, _) in entries.sorted(by: { $0.value.date < $1.value.date }).prefix(entries.count - limit) { entries[id] = nil }
        }
        guard let file, let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
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
