// SPDX-License-Identifier: GPL-3.0-or-later
import Combine
import Foundation
import NaturalLanguage

public enum BrowseRoute: Hashable, Sendable {
    case search(String), channel(String), playlist(String), related(String)
    case advancedSearch(String, SearchOptions)
    case trendingMusic
    case kiosk(YouTubeKiosk)
    case soundCloudSearch(String, SoundCloudSearchFilter), soundCloudTrending
    case filteredSearch(String, SearchFilter), channelTab(String, ChannelTab)
    case mix(playlist: String, seed: String)
}

/// YouTube's own curated pages, matching the kiosks NewPipe's extractor offers.
public enum YouTubeKiosk: String, CaseIterable, Codable, Sendable {
    case live = "Live", gaming = "Gaming", podcasts = "Podcasts", trailers = "Movie trailers"
    /// Page path on www.youtube.com; trailers come from YouTube Charts instead.
    var path: String? {
        switch self {
        case .live: return "/channel/UC4R8DWoMoI7CAwX8_LjQHig/livetab"
        case .gaming: return "/channel/UCOpNcN46UbXVtpKMrmU4Abg/trending"
        case .podcasts: return "/podcasts"
        case .trailers: return nil
        }
    }
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
    /// The item's page on its service's website (set for SoundCloud, where links aren't derivable from IDs).
    public let webURL: URL?
    public var id: String { kind.rawValue + ":" + contentID }
    public var isSoundCloud: Bool { SoundCloudID.isSoundCloud(contentID) }
    /// Link for sharing.
    public var shareURL: URL? {
        if let webURL { return webURL }
        switch kind {
        case .video: return isSoundCloud ? nil : URL(string: "https://www.youtube.com/watch?v=\(contentID)")
        case .channel: return isSoundCloud ? nil : URL(string: "https://www.youtube.com/channel/\(contentID)")
        case .playlist: return isSoundCloud ? nil : URL(string: "https://www.youtube.com/playlist?list=\(contentID)")
        }
    }
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
                thumbnail: URL? = nil, duration: String? = nil, channelID: String? = nil, playlistSeed: String? = nil, webURL: URL? = nil) {
        self.contentID = contentID; self.kind = kind; self.title = title
        self.subtitle = subtitle; self.thumbnail = thumbnail
        self.duration = duration; self.channelID = channelID; self.playlistSeed = playlistSeed; self.webURL = webURL
    }
}

public struct BrowseCursor: Equatable, Sendable {
    public let token: String
    public let clientVersion: String
    public let isSearch: Bool
    public let isRelated: Bool
    public let locale: ContentLocale
    /// Kiosk shelves still to expand once the current list runs out; an empty token opens the first of them.
    public let shelves: [BrowseShelf]
    /// YouTube's visitor ID from the first page; continuations of expanded shelves come back empty without it.
    public let visitorData: String?
    public init(token: String, clientVersion: String, isSearch: Bool, isRelated: Bool = false, locale: ContentLocale = .current(),
                shelves: [BrowseShelf] = [], visitorData: String? = nil) {
        self.locale = locale
        self.token = token; self.clientVersion = clientVersion
        self.isSearch = isSearch; self.isRelated = isRelated
        self.shelves = shelves; self.visitorData = visitorData
    }
}

/// A kiosk shelf's "Show more" list, such as Live's "Live Now" or "Upcoming Live Streams".
public struct BrowseShelf: Equatable, Sendable {
    public let browseID: String
    public let params: String?
}

extension BrowseCursor {
    /// Paging through a kiosk's shelves rather than one list's continuation.
    var isKioskPaging: Bool { token.isEmpty || !shelves.isEmpty || visitorData != nil }
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
        case .invalidInput: return L("Enter a search term or choose a valid channel or playlist.")
        case let .unavailable(message): return message
        case .unsupportedResponse: return L("YouTube returned a page DriftLoom cannot read. Please try again later.")
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

    static func acceptLanguage(_ locale: ContentLocale) -> String {
        let content = "\(locale.language)-\(locale.country),\(locale.language);q=0.9"
        guard let titles = locale.titleLanguage else { return content }
        return "\(titles),\(locale.language)-\(locale.country);q=0.8,\(locale.language);q=0.7"
    }
    /// The language a search was typed in, when Apple's on-device recognizer is fairly sure of it.
    /// Short or ambiguous queries (борщ could be Ukrainian or Russian) go to the interface language when the
    /// recognizer finds it plausible, so view counts and dates don't switch to a neighbouring language.
    static func queryLanguage(_ text: String, preferring preferred: String? = Locale.preferredLanguages.first) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 5)
        func base(_ code: String) -> String { code.split(separator: "-").first.map(String.init) ?? code }
        if let preferred = preferred.map(base), let match = hypotheses.first(where: { base($0.key.rawValue) == preferred }), match.value >= 0.15 {
            return preferred
        }
        guard let (language, confidence) = hypotheses.max(by: { $0.value < $1.value }), confidence >= 0.5 else { return nil }
        return base(language.rawValue)
    }
    public func page(for route: BrowseRoute) async throws -> BrowsePage {
        if route == .trendingMusic { return try await YouTubeChartsClient(session: session).music(locale: .current()) }
        if route == .kiosk(.trailers) { return try await YouTubeChartsClient(session: session).trailers(locale: .current()) }
        switch route {
        case let .soundCloudSearch(query, filter): return try await SoundCloudClient.shared.search(query, filter: filter)
        case .soundCloudTrending: return try await SoundCloudClient.shared.trending()
        case let .channel(id) where SoundCloudID.isSoundCloud(id), let .channelTab(id, _) where SoundCloudID.isSoundCloud(id):
            return try await SoundCloudClient.shared.user(id)
        case let .playlist(id) where SoundCloudID.isSoundCloud(id): return try await SoundCloudClient.shared.playlist(id)
        case let .related(id) where SoundCloudID.isSoundCloud(id): return try await SoundCloudClient.shared.related(id)
        default: break
        }
        var components = URLComponents(string: "https://www.youtube.com")!
        let title: String
        let isSearch: Bool
        var isRelated = false
        var isMix = false
        var locale = ContentLocale.current()
        if case let .search(value) = route { locale = locale.titles(in: Self.queryLanguage(value)) }
        if case let .filteredSearch(value, _) = route { locale = locale.titles(in: Self.queryLanguage(value)) }
        if case let .advancedSearch(value, _) = route { locale = locale.titles(in: Self.queryLanguage(value)) }
        var query = [URLQueryItem(name: "hl", value: locale.language), URLQueryItem(name: "gl", value: locale.country)]
        switch route {
        case .trendingMusic, .soundCloudSearch, .soundCloudTrending: throw BrowseError.invalidInput // Handled above.
        case let .kiosk(kiosk):
            guard let path = kiosk.path else { throw BrowseError.invalidInput }
            components.path = path
            title = kiosk.title; isSearch = false
        case let .search(value), let .filteredSearch(value, _), let .advancedSearch(value, _):
            let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.count <= 500 else { throw BrowseError.invalidInput }
            components.path = "/results"
            query.append(URLQueryItem(name: "search_query", value: value))
            if case let .filteredSearch(_, filter) = route, let parameter = filter.parameter {
                query.append(URLQueryItem(name: "sp", value: parameter))
            }
            if case let .advancedSearch(_, options) = route, let parameter = options.parameter {
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
            title = L("Related videos"); isSearch = false; isRelated = true
        case let .playlist(id):
            guard Self.validID(id) else { throw BrowseError.invalidInput }
            components.path = "/playlist"
            query.append(URLQueryItem(name: "list", value: id))
            title = "Playlist"; isSearch = false
        }
        components.queryItems = query
        let data: Data
        do {
            data = try await fetch(URLRequest(url: components.url!), locale: locale)
        } catch where route == .kiosk(.podcasts) && locale.language != "en" {
            // YouTube's podcasts page is 404 in some interface languages (Ukrainian, Russian, Japanese); the
            // same country's page in English still lists its podcasts, titled as published.
            locale = ContentLocale(language: "en", country: locale.country)
            components.queryItems = [URLQueryItem(name: "hl", value: "en"), URLQueryItem(name: "gl", value: locale.country)]
            data = try await fetch(URLRequest(url: components.url!), locale: locale)
        }
        guard let html = String(data: data, encoding: .utf8) else { throw BrowseError.unsupportedResponse }
        let root = try BrowseParser.initialData(in: html)
        let version = BrowseParser.clientVersion(in: html)
        let page = try BrowseParser.page(root, fallbackTitle: title, clientVersion: version, isSearch: isSearch, isRelated: isRelated, isMix: isMix, locale: locale)
        // Kiosk pages are shelves of a dozen items with no continuation; paging goes on through each shelf's full list.
        if case .kiosk = route, page.next == nil, let version {
            let shelves = BrowseParser.shelfLinks(root)
            if !shelves.isEmpty {
                return BrowsePage(title: page.title, items: page.items,
                                  next: BrowseCursor(token: "", clientVersion: version, isSearch: false, locale: locale,
                                                     shelves: shelves, visitorData: BrowseParser.visitorData(root)),
                                  header: page.header)
            }
        }
        return page
    }

    public func nextPage(_ cursor: BrowseCursor) async throws -> BrowsePage {
        if cursor.clientVersion == SoundCloudClient.paginationMarker { return try await SoundCloudClient.shared.nextPage(cursor) }
        let shelf = cursor.token.isEmpty ? cursor.shelves.first : nil
        if cursor.token.isEmpty, shelf == nil { throw BrowseError.invalidInput }
        let endpoint = cursor.isRelated ? "next" : cursor.isSearch ? "search" : "browse"
        var request = URLRequest(url: URL(string: "https://www.youtube.com/youtubei/v1/\(endpoint)?prettyPrint=false")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("1", forHTTPHeaderField: "X-Youtube-Client-Name")
        request.setValue(cursor.clientVersion, forHTTPHeaderField: "X-Youtube-Client-Version")
        var client: [String: Any] = ["clientName": "WEB", "clientVersion": cursor.clientVersion, "hl": cursor.locale.language, "gl": cursor.locale.country]
        if let visitor = cursor.visitorData {
            client["visitorData"] = visitor
            request.setValue(visitor, forHTTPHeaderField: "X-Goog-Visitor-Id")
        }
        var body: [String: Any] = ["context": ["client": client]]
        if let shelf {
            body["browseId"] = shelf.browseID
            if let params = shelf.params { body["params"] = params }
        } else {
            body["continuation"] = cursor.token
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await fetch(request, locale: cursor.locale)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BrowseError.unsupportedResponse
        }
        let page = try BrowseParser.page(root, fallbackTitle: "", clientVersion: cursor.clientVersion,
                                         isSearch: cursor.isSearch, isRelated: cursor.isRelated, locale: cursor.locale)
        guard cursor.isKioskPaging else { return page }
        // Carry the remaining shelves and the visitor ID along: this shelf's next page first, then the next shelf.
        let remaining = shelf == nil ? cursor.shelves : Array(cursor.shelves.dropFirst())
        let visitor = cursor.visitorData ?? BrowseParser.visitorData(root)
        let next = page.next.map { BrowseCursor(token: $0.token, clientVersion: $0.clientVersion, isSearch: false, locale: cursor.locale, shelves: remaining, visitorData: visitor) }
            ?? (remaining.isEmpty ? nil : BrowseCursor(token: "", clientVersion: cursor.clientVersion, isSearch: false, locale: cursor.locale, shelves: remaining, visitorData: visitor))
        return BrowsePage(title: page.title, items: page.items, next: next, header: page.header)
    }

    private func fetch(_ original: URLRequest, locale: ContentLocale) async throws -> Data {
        var request = original
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/18.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        // YouTube picks the language of video titles (uploaders' translations and its own) from this header,
        // not from hl; a fixed English header showed foreign videos under English titles.
        request.setValue(Self.acceptLanguage(locale), forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw BrowseError.unsupportedResponse }
        guard (200..<300).contains(response.statusCode) else {
            throw BrowseError.unavailable(L("YouTube couldn't load this page (\(response.statusCode)). Try again later."))
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
            var page = try await client.nextPage(cursor)
            try Task.checkCancellation()
            guard generation == token else { return }
            var added = append(page)
            // An expanded kiosk shelf starts with the items already shown; fetch on until a useful number are new.
            var extra = 0
            while added < 10, extra < 5, let next = page.next, next != cursor {
                page = try await client.nextPage(next)
                try Task.checkCancellation()
                guard generation == token else { return }
                added += append(page); extra += 1
            }
            // Repeated tokens cannot send the user into an endless pagination loop.
            if self.cursor == cursor { self.cursor = nil; canLoadMore = false }
        } catch {
            if generation == token, !Task.isCancelled { paginationError = error.localizedDescription }
        }
        if generation == token { isLoadingMore = false }
    }

    /// Adds the page's new items and returns how many there were.
    @discardableResult private func append(_ page: BrowsePage) -> Int {
        var ids = Set(items.map(\.id))
        let new = page.items.filter { ids.insert($0.id).inserted }
        items.append(contentsOf: new)
        cursor = page.next
        canLoadMore = cursor != nil
        return new.count
    }
}
