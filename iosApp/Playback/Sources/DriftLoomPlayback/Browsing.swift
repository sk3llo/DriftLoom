// SPDX-License-Identifier: GPL-3.0-or-later
import Combine
import Foundation

public enum BrowseRoute: Hashable, Sendable {
    case search(String), channel(String), playlist(String), related(String)
    case filteredSearch(String, SearchFilter), channelTab(String, ChannelTab)
    case mix(playlist: String, seed: String)
}

public enum SearchFilter: String, CaseIterable, Sendable {
    case all = "All", videos = "Videos", channels = "Channels", playlists = "Playlists"
    var parameter: String? {
        switch self {
        case .all: return nil
        case .videos: return "EgIQAQ=="
        case .channels: return "EgIQAg=="
        case .playlists: return "EgIQAw=="
        }
    }
}

public enum ChannelTab: String, CaseIterable, Sendable {
    case videos = "Videos", shorts = "Shorts", streams = "Live", playlists = "Playlists"
    var path: String { self == .streams ? "streams" : rawValue.lowercased() }
}

public struct BrowseHeader: Sendable {
    public let description: String
    public let thumbnail: URL?
    public let tabs: [ChannelTab]
    public init(description: String = "", thumbnail: URL? = nil, tabs: [ChannelTab] = []) {
        self.description = description; self.thumbnail = thumbnail; self.tabs = tabs
    }
}

public struct BrowseItem: Identifiable, Equatable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case video, channel, playlist }
    public let contentID: String
    public let kind: Kind
    public let title: String
    public let subtitle: String
    public let thumbnail: URL?
    public let duration: String?
    public let channelID: String?
    public let playlistSeed: String?
    public var id: String { kind.rawValue + ":" + contentID }
    public var destination: BrowseRoute? {
        switch kind {
        case .video: return nil
        case .channel: return .channel(contentID)
        case .playlist:
            if contentID.hasPrefix("RD"), let playlistSeed { return .mix(playlist: contentID, seed: playlistSeed) }
            return .playlist(contentID)
        }
    }

    public init(contentID: String, kind: Kind, title: String, subtitle: String = "",
                thumbnail: URL? = nil, duration: String? = nil, channelID: String? = nil, playlistSeed: String? = nil) {
        self.contentID = contentID; self.kind = kind; self.title = title
        self.subtitle = subtitle; self.thumbnail = thumbnail
        self.duration = duration; self.channelID = channelID; self.playlistSeed = playlistSeed
    }
}

public struct BrowseCursor: Equatable, Sendable {
    public let token: String
    public let clientVersion: String
    public let isSearch: Bool
    public let isRelated: Bool
    public init(token: String, clientVersion: String, isSearch: Bool, isRelated: Bool = false) {
        self.token = token; self.clientVersion = clientVersion
        self.isSearch = isSearch; self.isRelated = isRelated
    }
}

public struct BrowsePage: Sendable {
    public let title: String
    public let items: [BrowseItem]
    public let next: BrowseCursor?
    public let header: BrowseHeader?
    public init(title: String, items: [BrowseItem], next: BrowseCursor? = nil, header: BrowseHeader? = nil) {
        self.title = title; self.items = items; self.next = next; self.header = header
    }
}

public protocol Browsing: Sendable {
    func page(for route: BrowseRoute) async throws -> BrowsePage
    func nextPage(_ cursor: BrowseCursor) async throws -> BrowsePage
}

public enum BrowseError: LocalizedError {
    case invalidInput, unavailable(String), unsupportedResponse
    public var errorDescription: String? {
        switch self {
        case .invalidInput: return "Enter a search term or choose a valid channel or playlist."
        case let .unavailable(message): return message
        case .unsupportedResponse: return "YouTube returned a page DriftLoom cannot read. Please try again later."
        }
    }
}

public actor YouTubeBrowsingClient: Browsing {
    private let session: URLSession
    public init(session: URLSession? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 25
        self.session = session ?? URLSession(configuration: configuration)
    }

    public func page(for route: BrowseRoute) async throws -> BrowsePage {
        var components = URLComponents(string: "https://www.youtube.com")!
        let title: String
        let isSearch: Bool
        var isRelated = false
        var isMix = false
        var query = [URLQueryItem(name: "hl", value: "en"), URLQueryItem(name: "gl", value: "PT")]
        switch route {
        case let .search(value), let .filteredSearch(value, _):
            let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.count <= 500 else { throw BrowseError.invalidInput }
            components.path = "/results"
            query.append(URLQueryItem(name: "search_query", value: value))
            if case let .filteredSearch(_, filter) = route, let parameter = filter.parameter {
                query.append(URLQueryItem(name: "sp", value: parameter))
            }
            title = value; isSearch = true
        case let .channel(id), let .channelTab(id, _):
            guard id.range(of: "^UC[A-Za-z0-9_-]{22}$", options: .regularExpression) != nil else { throw BrowseError.invalidInput }
            let tab: ChannelTab
            if case let .channelTab(_, selected) = route { tab = selected } else { tab = .videos }
            components.path = "/channel/\(id)/\(tab.path)"
            title = "Channel"; isSearch = false
        case let .mix(playlist, seed):
            guard Self.validID(playlist), (try? VideoRequest(input: seed)) != nil else { throw BrowseError.invalidInput }
            components.path = "/watch"
            query.append(URLQueryItem(name: "v", value: seed))
            query.append(URLQueryItem(name: "list", value: playlist))
            title = "Mix"; isSearch = false; isMix = true
        case let .related(id):
            guard (try? VideoRequest(input: id)) != nil else { throw BrowseError.invalidInput }
            components.path = "/watch"
            query.append(URLQueryItem(name: "v", value: id))
            title = "Related videos"; isSearch = false; isRelated = true
        case let .playlist(id):
            guard Self.validID(id) else { throw BrowseError.invalidInput }
            components.path = "/playlist"
            query.append(URLQueryItem(name: "list", value: id))
            title = "Playlist"; isSearch = false
        }
        components.queryItems = query
        let data = try await fetch(URLRequest(url: components.url!))
        guard let html = String(data: data, encoding: .utf8) else { throw BrowseError.unsupportedResponse }
        let root = try BrowseParser.initialData(in: html)
        let version = BrowseParser.clientVersion(in: html)
        return try BrowseParser.page(root, fallbackTitle: title, clientVersion: version, isSearch: isSearch, isRelated: isRelated, isMix: isMix)
    }

    public func nextPage(_ cursor: BrowseCursor) async throws -> BrowsePage {
        let endpoint = cursor.isRelated ? "next" : cursor.isSearch ? "search" : "browse"
        var request = URLRequest(url: URL(string: "https://www.youtube.com/youtubei/v1/\(endpoint)?prettyPrint=false")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("1", forHTTPHeaderField: "X-Youtube-Client-Name")
        request.setValue(cursor.clientVersion, forHTTPHeaderField: "X-Youtube-Client-Version")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "context": ["client": ["clientName": "WEB", "clientVersion": cursor.clientVersion,
                                     "hl": "en", "gl": "PT"]],
            "continuation": cursor.token
        ])
        let data = try await fetch(request)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BrowseError.unsupportedResponse
        }
        return try BrowseParser.page(root, fallbackTitle: "", clientVersion: cursor.clientVersion,
                                     isSearch: cursor.isSearch, isRelated: cursor.isRelated)
    }

    private func fetch(_ original: URLRequest) async throws -> Data {
        var request = original
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/18.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw BrowseError.unsupportedResponse }
        guard (200..<300).contains(response.statusCode) else {
            throw BrowseError.unavailable("YouTube couldn't load this page (\(response.statusCode)). Try again later.")
        }
        guard response.url?.host == "www.youtube.com", data.count <= 8_000_000 else {
            throw BrowseError.unsupportedResponse
        }
        return data
    }

    private static func validID(_ id: String) -> Bool {
        id.range(of: "^[A-Za-z0-9_-]{2,150}$", options: .regularExpression) != nil
    }
}

@MainActor
public final class BrowseStore: ObservableObject {
    @Published public private(set) var items: [BrowseItem] = []
    @Published public private(set) var title = ""
    @Published public private(set) var header: BrowseHeader?
    @Published public private(set) var isLoading = false
    @Published public private(set) var isLoadingMore = false
    @Published public private(set) var error: String?
    @Published public private(set) var paginationError: String?
    @Published public private(set) var hasLoaded = false
    @Published public private(set) var canLoadMore = false
    private let client: any Browsing
    private var cursor: BrowseCursor?
    private var generation = UUID()

    public init(client: any Browsing = YouTubeBrowsingClient()) { self.client = client }

    public func load(_ route: BrowseRoute) async {
        generation = UUID()
        let token = generation
        title = ""
        header = nil
        items = []; cursor = nil; canLoadMore = false; hasLoaded = false
        error = nil; paginationError = nil; isLoading = true; isLoadingMore = false
        do {
            let page = try await client.page(for: route)
            try Task.checkCancellation()
            guard generation == token else { return }
            title = page.title
            header = page.header
            append(page)
            hasLoaded = true
        } catch {
            if generation == token, !Task.isCancelled { self.error = error.localizedDescription }
        }
        if generation == token { isLoading = false }
    }

    public func loadMore() async {
        guard let cursor, !isLoading, !isLoadingMore else { return }
        let token = generation
        isLoadingMore = true; paginationError = nil
        do {
            let page = try await client.nextPage(cursor)
            try Task.checkCancellation()
            guard generation == token else { return }
            append(page)
            // Repeated tokens cannot send the user into an endless pagination loop.
            if self.cursor == cursor { self.cursor = nil; canLoadMore = false }
        } catch {
            if generation == token, !Task.isCancelled { paginationError = error.localizedDescription }
        }
        if generation == token { isLoadingMore = false }
    }

    private func append(_ page: BrowsePage) {
        var ids = Set(items.map(\.id))
        items.append(contentsOf: page.items.filter { ids.insert($0.id).inserted })
        cursor = page.next
        canLoadMore = cursor != nil
    }
}
