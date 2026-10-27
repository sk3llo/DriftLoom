// SPDX-License-Identifier: GPL-3.0-or-later
import Combine
import Foundation

public protocol Suggesting: Sendable {
    func suggestions(for query: String, locale: ContentLocale) async throws -> [String]
}

/// Uses the same JSON endpoint as the Android extractor; no cookies or account state.
public actor YouTubeSuggestionsClient: Suggesting {
    private let session: URLSession
    public init(session: URLSession? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 10
        self.session = session ?? URLSession(configuration: configuration)
    }
    public func suggestions(for query: String, locale: ContentLocale) async throws -> [String] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...500).contains(query.count), !query.contains("://") else { return [] }
        var components = URLComponents(string: "https://suggestqueries-clients6.youtube.com/complete/search")!
        components.queryItems = [URLQueryItem(name: "client", value: "youtube"), URLQueryItem(name: "ds", value: "yt"),
                                 URLQueryItem(name: "xhr", value: "t"), URLQueryItem(name: "q", value: query),
                                 URLQueryItem(name: "gl", value: locale.country), URLQueryItem(name: "hl", value: locale.language)]
        var request = URLRequest(url: components.url!)
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.url?.host == "suggestqueries-clients6.youtube.com", data.count < 1_000_000 else { throw BrowseError.unsupportedResponse }
        return try SuggestionParser.parse(data)
    }
}

enum SuggestionParser {
    static func parse(_ data: Data) throws -> [String] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [Any], root.count >= 2,
              let suggestions = root[1] as? [Any] else { throw BrowseError.unsupportedResponse }
        var seen = Set<String>()
        return Array(suggestions.compactMap { entry -> String? in
            let value = ((entry as? [Any])?.first as? String) ?? entry as? String
            guard let value else { return nil }
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return !text.isEmpty && text.count <= 500 && seen.insert(text).inserted ? text : nil
        }.prefix(10))
    }
}

@MainActor
public final class SuggestionStore: ObservableObject {
    @Published public private(set) var suggestions: [String] = []
    private let client: any Suggesting
    private var generation = UUID()
    public init(client: any Suggesting = YouTubeSuggestionsClient()) { self.client = client }
    public func clear() { generation = UUID(); suggestions = [] }
    public func load(query: String, locale: ContentLocale, enabled: Bool = true) async {
        generation = UUID(); let token = generation; suggestions = []
        guard enabled, (2...500).contains(query.trimmingCharacters(in: .whitespacesAndNewlines).count), !query.contains("://") else { return }
        do {
            try await Task.sleep(nanoseconds: 300_000_000)
            try Task.checkCancellation()
            let values = try await client.suggestions(for: query, locale: locale)
            try Task.checkCancellation(); guard generation == token else { return }
            suggestions = values
        } catch { /* Suggestions are optional. Search and local history remain available. */ }
    }
}
