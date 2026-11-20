// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Official chart source used by NewPipe's trending-music extractor.
/// Fetch the current Charts client version instead of guessing a browser search query.
public actor YouTubeChartsClient {
    private let session: URLSession
    public init(session: URLSession? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 25
        self.session = session ?? URLSession(configuration: configuration)
    }
    /// The country's "Trending 20" chart from YouTube Music. charts.youtube.com now asks for a reCAPTCHA
    /// token on every chart request, so its API answers 403 to anything but its own page.
    public func music(locale: ContentLocale) async throws -> BrowsePage {
        let playlist = try await trendingPlaylist(locale: locale)
        let page = try await YouTubeBrowsingClient(session: session).page(for: .playlist(playlist))
        guard !page.items.isEmpty else { throw BrowseError.unsupportedResponse }
        return BrowsePage(title: L("Trending music") + " · " + locale.country, items: page.items, next: page.next)
    }
    private func trendingPlaylist(locale: ContentLocale) async throws -> String {
        var home = URLComponents(string: "https://music.youtube.com/")!
        home.queryItems = [URLQueryItem(name: "hl", value: locale.language), URLQueryItem(name: "gl", value: locale.country)]
        guard let version = BrowseParser.clientVersion(in: String(decoding: try await fetch(URLRequest(url: home.url!), host: "music.youtube.com"), as: UTF8.self)) else {
            throw BrowseError.unsupportedResponse
        }
        var request = URLRequest(url: URL(string: "https://music.youtube.com/youtubei/v1/browse?prettyPrint=false")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("67", forHTTPHeaderField: "X-Youtube-Client-Name")
        request.setValue(version, forHTTPHeaderField: "X-Youtube-Client-Version")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "context": ["client": ["clientName": "WEB_REMIX", "clientVersion": version, "hl": locale.language, "gl": locale.country]],
            "browseId": "FEmusic_charts",
            "formData": ["selectedValues": [locale.country]]
        ])
        let data: Data
        do { data = try await fetch(request, host: "music.youtube.com") } catch BrowseError.unavailable(_) {
            throw BrowseError.unavailable(L("YouTube Music has no charts for this content region. Choose another region in Settings."))
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let id = ChartsParser.trendingPlaylist(root) else {
            throw BrowseError.unavailable(L("YouTube Music has no charts for this content region. Choose another region in Settings."))
        }
        return id
    }
    private func fetch(_ original: URLRequest, host: String) async throws -> Data {
        var request = original
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.url?.host == host, data.count < 8_000_000 else { throw BrowseError.unsupportedResponse }
        guard http.statusCode == 200 else { throw BrowseError.unavailable(L("YouTube couldn't load this chart (\(http.statusCode)). Try another content region or try again later.")) }
        return data
    }
}

enum ChartsParser {
    typealias Object = [String: Any]
    /// The first album-style playlist (OLAK5uy_…) on the charts page is the country's "Trending 20";
    /// the other video and genre charts are regular PL… playlists.
    static func trendingPlaylist(_ root: Object) -> String? {
        let tabs = ((root["contents"] as? Object)?["singleColumnBrowseResultsRenderer"] as? Object)?["tabs"] as? [Object] ?? []
        let sections = (((tabs.first?["tabRenderer"] as? Object)?["content"] as? Object)?["sectionListRenderer"] as? Object)?["contents"] as? [Object] ?? []
        for section in sections {
            for item in (section["musicCarouselShelfRenderer"] as? Object)?["contents"] as? [Object] ?? [] {
                let endpoint = ((item["musicTwoRowItemRenderer"] as? Object)?["navigationEndpoint"] as? Object)?["browseEndpoint"] as? Object
                guard let browseID = endpoint?["browseId"] as? String, browseID.hasPrefix("VLOLAK5uy_") else { continue }
                let id = String(browseID.dropFirst(2))
                if id.range(of: "^[A-Za-z0-9_-]{10,100}$", options: .regularExpression) != nil { return id }
            }
        }
        return nil
    }
}
