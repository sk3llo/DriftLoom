// SPDX-License-Identifier: GPL-3.0-or-later
import Combine
import Foundation

public struct CommentCursor: Equatable, Sendable {
    public let token: String
    public let clientVersion: String
    public let locale: ContentLocale
    public init(token: String, clientVersion: String, locale: ContentLocale = .current()) {
        self.token = token; self.clientVersion = clientVersion; self.locale = locale
    }
}
public struct VideoComment: Identifiable, Sendable {
    public let id: String
    public let author: String
    public let channelID: String?
    public let text: String
    public let published: String
    public let likes: String
    public let replies: CommentCursor?
}
public struct CommentPage: Sendable {
    public let comments: [VideoComment]
    public let next: CommentCursor?
}
public struct VideoDetails: Sendable {
    public let views: String
    public let date: String
    public let description: String
    public let comments: CommentCursor?
}
public protocol DiscussionLoading: Sendable {
    func details(videoID: String) async throws -> VideoDetails
    func comments(_ cursor: CommentCursor) async throws -> CommentPage
}

public actor YouTubeDiscussionClient: DiscussionLoading {
    private let session: URLSession
    public init(session: URLSession? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 25
        self.session = session ?? URLSession(configuration: configuration)
    }
    public func details(videoID: String) async throws -> VideoDetails {
        if SoundCloudID.isSoundCloud(videoID) { return try await SoundCloudClient.shared.details(videoID) }
        guard (try? VideoRequest(input: videoID).videoID) == videoID else { throw BrowseError.invalidInput }
        let locale = ContentLocale.current()
        var components = URLComponents(string: "https://www.youtube.com/watch")!
        components.queryItems = [URLQueryItem(name: "v", value: videoID), URLQueryItem(name: "hl", value: locale.language), URLQueryItem(name: "gl", value: locale.country)]
        let url = components.url!
        let data = try await fetch(URLRequest(url: url))
        guard let html = String(data: data, encoding: .utf8) else { throw BrowseError.unsupportedResponse }
        let root = try BrowseParser.initialData(in: html)
        let version = BrowseParser.clientVersion(in: html)
        return DiscussionParser.details(root, version: version)
    }
    public func comments(_ cursor: CommentCursor) async throws -> CommentPage {
        if cursor.clientVersion == SoundCloudClient.paginationMarker { return try await SoundCloudClient.shared.comments(cursor) }
        var request = URLRequest(url: URL(string: "https://www.youtube.com/youtubei/v1/next?prettyPrint=false")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "context": ["client": ["clientName": "WEB", "clientVersion": cursor.clientVersion, "hl": cursor.locale.language, "gl": cursor.locale.country]],
            "continuation": cursor.token
        ])
        let data = try await fetch(request)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw BrowseError.unsupportedResponse }
        return try DiscussionParser.comments(root, version: cursor.clientVersion)
    }
    private func fetch(_ original: URLRequest) async throws -> Data {
        var request = original
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.url?.host == "www.youtube.com", data.count < 8_000_000 else { throw BrowseError.unsupportedResponse }
        guard http.statusCode == 200 else { throw BrowseError.unavailable("YouTube couldn't load comments (\(http.statusCode)). Try again.") }
        return data
    }
}

/// Handles legacy renderers and entity-backed comment view models without mixing replies into the top-level list.
enum DiscussionParser {
    typealias Object = [String: Any]
    static func nodes(_ value: Any, key: String, depth: Int = 0) -> [Object] {
        guard depth < 70 else { return [] }
        if let array = value as? [Any] { return array.flatMap { nodes($0, key: key, depth: depth + 1) } }
        guard let object = value as? Object else { return [] }
        if let match = object[key] as? Object { return [match] }
        return object.keys.sorted().flatMap { nodes(object[$0]!, key: key, depth: depth + 1) }
    }
    static func text(_ value: Any?) -> String {
        guard let o = value as? Object else { return value as? String ?? "" }
        return o["simpleText"] as? String ?? o["content"] as? String
            ?? (o["runs"] as? [Object] ?? []).compactMap { $0["text"] as? String }.joined()
    }
    static func cursor(_ object: Any, version: String) -> CommentCursor? {
        guard let token = nodes(object, key: "continuationCommand").first?["token"] as? String else { return nil }
        return CommentCursor(token: token, clientVersion: version)
    }
    static func details(_ root: Object, version: String?) -> VideoDetails {
        let primary = nodes(root, key: "videoPrimaryInfoRenderer").first ?? [:]
        let secondary = nodes(root, key: "videoSecondaryInfoRenderer").first ?? [:]
        let view = nodes(primary, key: "videoViewCountRenderer").first
        let section = nodes(root, key: "itemSectionRenderer").first { $0["targetId"] as? String == "comments-section" }
        let comments = version.flatMap { version in section.flatMap { cursor($0["contents"] ?? [], version: version) } }
        return VideoDetails(views: text(view?["viewCount"]), date: text(primary["dateText"]),
                            description: text(secondary["attributedDescription"] ?? secondary["description"]), comments: comments)
    }
    static func comments(_ root: Object, version: String) throws -> CommentPage {
        let endpoints = (root["onResponseReceivedEndpoints"] ?? root["onResponseReceivedActions"]) as? [Object] ?? []
        let commands = endpoints.flatMap { endpoint -> [Object] in
            [endpoint["reloadContinuationItemsCommand"], endpoint["appendContinuationItemsAction"]].compactMap { $0 as? Object }
        }
        guard !commands.isEmpty else { throw BrowseError.unsupportedResponse }
        let mutations = nodes(root["frameworkUpdates"] ?? [:], key: "entityBatchUpdate").first?["mutations"] as? [Object] ?? []
        var entities: [String: Object] = [:]
        for mutation in mutations {
            if let key = mutation["entityKey"] as? String, let payload = mutation["payload"] as? Object,
               let entity = payload["commentEntityPayload"] as? Object { entities[key] = entity }
        }
        var result: [VideoComment] = [], next: CommentCursor?
        for command in commands {
            for item in command["continuationItems"] as? [Object] ?? [] {
                if let continuation = item["continuationItemRenderer"] { next = cursor(continuation, version: version); continue }
                let thread = item["commentThreadRenderer"] as? Object ?? item
                let replies = (thread["replies"] as? Object)?["commentRepliesRenderer"] as? Object
                let replyCursor = replies.flatMap { cursor($0["contents"] ?? [], version: version) }
                let directModel = thread["commentViewModel"] as? Object
                let model = directModel?["commentKey"] != nil ? directModel : nodes(thread, key: "commentViewModel").first.flatMap { wrapper in
                    wrapper["commentKey"] != nil ? wrapper : wrapper["commentViewModel"] as? Object
                }
                if let model,
                   let key = model["commentKey"] as? String, let entity = entities[key],
                   let properties = entity["properties"] as? Object, let id = properties["commentId"] as? String {
                    let author = entity["author"] as? Object ?? [:]
                    result.append(VideoComment(id: id, author: author["displayName"] as? String ?? "YouTube user",
                        channelID: author["channelId"] as? String, text: text(properties["content"]),
                        published: properties["publishedTime"] as? String ?? "",
                        likes: (entity["toolbar"] as? Object)?["likeCountNotliked"] as? String ?? "", replies: replyCursor))
                } else if let legacy = nodes(thread["comment"] ?? thread, key: "commentRenderer").first,
                          let id = legacy["commentId"] as? String {
                    let channel = nodes(legacy["authorEndpoint"] ?? [:], key: "browseEndpoint").first?["browseId"] as? String
                    result.append(VideoComment(id: id, author: text(legacy["authorText"]), channelID: channel,
                        text: text(legacy["contentText"]), published: text(legacy["publishedTimeText"]), likes: text(legacy["voteCount"]), replies: replyCursor))
                }
            }
        }
        var seen = Set<String>()
        return CommentPage(comments: result.filter { seen.insert($0.id).inserted }, next: next)
    }
}

@MainActor
public final class DiscussionStore: ObservableObject {
    @Published public private(set) var details: VideoDetails?
    @Published public private(set) var comments: [VideoComment] = []
    @Published public private(set) var replies: [String: [VideoComment]] = [:]
    @Published public private(set) var loading = false
    @Published public private(set) var loadingReplies = Set<String>()
    @Published public private(set) var error: String?
    @Published public private(set) var hasLoadedComments = false
    @Published public private(set) var canLoadMore = false
    private let client: any DiscussionLoading
    private var next: CommentCursor?
    private var replyCursors: [String: CommentCursor] = [:]
    private var generation = UUID()
    public init(client: any DiscussionLoading = YouTubeDiscussionClient()) { self.client = client }
    public func load(videoID: String) async {
        generation = UUID(); let token = generation
        details = nil; comments = []; replies = [:]; next = nil; replyCursors = [:]
        canLoadMore = false; hasLoadedComments = false; error = nil; loading = true; loadingReplies = []
        do {
            let value = try await client.details(videoID: videoID)
            try Task.checkCancellation(); guard generation == token else { return }
            details = value; next = value.comments; canLoadMore = next != nil
        } catch { if generation == token, !Task.isCancelled { self.error = error.localizedDescription } }
        if generation == token { loading = false }
    }
    public func loadMore() async {
        guard !loading, let cursor = next else { return }
        let token = generation; loading = true; error = nil
        do {
            let page = try await client.comments(cursor)
            try Task.checkCancellation(); guard generation == token else { return }
            var ids = Set(comments.map(\.id)); comments += page.comments.filter { ids.insert($0.id).inserted }
            next = page.next == cursor ? nil : page.next; canLoadMore = next != nil; hasLoadedComments = true
        } catch { if generation == token, !Task.isCancelled { self.error = error.localizedDescription } }
        if generation == token { loading = false }
    }
    public func loadReplies(_ comment: VideoComment) async {
        guard !loadingReplies.contains(comment.id), let cursor = replyCursors[comment.id] ?? (replies[comment.id] == nil ? comment.replies : nil) else { return }
        let token = generation; loadingReplies.insert(comment.id)
        do {
            let page = try await client.comments(cursor)
            try Task.checkCancellation(); guard generation == token else { return }
            var list = replies[comment.id] ?? []; var ids = Set(list.map(\.id))
            list += page.comments.filter { ids.insert($0.id).inserted }; replies[comment.id] = list
            replyCursors[comment.id] = page.next == cursor ? nil : page.next
        } catch { if generation == token, !Task.isCancelled { self.error = error.localizedDescription } }
        if generation == token { loadingReplies.remove(comment.id) }
    }
    public func hasMoreReplies(_ comment: VideoComment) -> Bool { replyCursors[comment.id] != nil || (replies[comment.id] == nil && comment.replies != nil) }
}
