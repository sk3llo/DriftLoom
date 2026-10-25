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
        guard channelID.range(of: "^UC[A-Za-z0-9_-]{22}$", options: .regularExpression) != nil else { throw BrowseError.invalidInput }
        var url = URLComponents(string: "https://www.youtube.com/feeds/videos.xml")!
        url.queryItems = [URLQueryItem(name: "channel_id", value: channelID)]
        let (data, response) = try await session.data(from: url.url!)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.url?.host == "www.youtube.com", data.count <= 1_000_000 else {
            throw BrowseError.unavailable("This channel's feed could not be loaded.")
        }
        return try FeedXMLParser.parse(data, channelID: channelID)
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
    public init(client: any FeedLoading = YouTubeFeedClient()) { self.client = client }
    public func load(channelIDs: [String]) async {
        let token = UUID(); generation = token
        loading = true; failedChannels = 0; completedChannels = 0
        var seen = Set<String>(), collected: [FeedVideo] = []
        let ids = channelIDs.filter { seen.insert($0).inserted }
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
