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
    public func music(locale: ContentLocale) async throws -> BrowsePage {
        var page = URLComponents(string: "https://charts.youtube.com/charts/TrendingVideos/\(locale.country.lowercased())")!
        page.queryItems = [URLQueryItem(name: "hl", value: locale.language)]
        let htmlData = try await fetch(URLRequest(url: page.url!))
        guard let html = String(data: htmlData, encoding: .utf8),
              let version = BrowseParser.clientVersion(in: html.replacingOccurrences(of: "\\\"", with: "\"")) else { throw BrowseError.unsupportedResponse }
        var request = URLRequest(url: URL(string: "https://charts.youtube.com/youtubei/v1/browse?alt=json&prettyPrint=false")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://charts.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://charts.youtube.com", forHTTPHeaderField: "Referer")
        request.setValue("31", forHTTPHeaderField: "X-Youtube-Client-Name")
        request.setValue(version, forHTTPHeaderField: "X-Youtube-Client-Version")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "context": ["client": ["clientName": "WEB_MUSIC_ANALYTICS", "clientVersion": version,
                                      "hl": locale.language, "gl": locale.country, "utcOffsetMinutes": 0]],
            "browseId": "FEmusic_analytics_charts_home",
            "query": "perspective=CHART_DETAILS&chart_params_country_code=\(locale.country)&chart_params_chart_type=TRENDING_VIDEOS"
        ])
        let data = try await fetch(request)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw BrowseError.unsupportedResponse }
        return try ChartsParser.music(root, country: locale.country)
    }
    private func fetch(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.url?.host == "charts.youtube.com", data.count < 8_000_000 else { throw BrowseError.unsupportedResponse }
        guard http.statusCode == 200 else { throw BrowseError.unavailable("YouTube couldn't load this chart (\(http.statusCode)). Try another content region or try again later.") }
        return data
    }
}

enum ChartsParser {
    typealias Object = [String: Any]
    static func music(_ root: Object, country: String) throws -> BrowsePage {
        guard let sections = ((root["contents"] as? Object)?["sectionListRenderer"] as? Object)?["contents"] as? [Object] else { throw BrowseError.unsupportedResponse }
        var rows: [Object] = [], found = false
        for section in sections {
            guard let renderer = section["musicAnalyticsSectionRenderer"] as? Object,
                  let videos = (renderer["content"] as? Object)?["videos"] as? [Object] else { continue }
            found = true
            rows += videos.flatMap { $0["videoViews"] as? [Object] ?? [] }
        }
        guard found, rows.count <= 1000 else { throw BrowseError.unsupportedResponse }
        var seen = Set<String>()
        let items = rows.compactMap { row -> BrowseItem? in
            guard row["isAvailable"] as? Bool != false, row["isVisible"] as? Bool != false,
                  let id = row["id"] as? String, (try? VideoRequest(input: id).videoID) == id,
                  let title = row["title"] as? String, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  seen.insert(id).inserted else { return nil }
            let thumbnail = ((row["thumbnail"] as? Object)?["thumbnails"] as? [Object])?.last?["url"] as? String
            let url = thumbnail.flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
            let seconds = (row["videoDuration"] as? Int) ?? (row["videoDuration"] as? String).flatMap(Int.init)
            let duration = seconds.flatMap { value -> String? in
                guard value > 0, value < 8_640_000 else { return nil }
                return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, (value % 3600) / 60, value % 60) : String(format: "%d:%02d", value / 60, value % 60)
            }
            let channel = (row["externalChannelId"] as? String).flatMap {
                $0.range(of: "^UC[A-Za-z0-9_-]{22}$", options: .regularExpression) != nil ? $0 : nil
            }
            return BrowseItem(contentID: id, kind: .video, title: title, subtitle: row["channelName"] as? String ?? "",
                              thumbnail: url, duration: duration, channelID: channel)
        }
        return BrowsePage(title: "Trending music · " + country, items: items)
    }
}
