// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Content from services other than YouTube is identified with a service prefix, so stored
/// libraries, queues and downloads stay readable by earlier builds' YouTube-only checks:
/// SoundCloud tracks are "sc:<id>", users "sc:user:<id>", playlists "sc:playlist:<id>".
public enum SoundCloudID {
    public static func track(_ id: Int) -> String { "sc:\(id)" }
    public static func user(_ id: Int) -> String { "sc:user:\(id)" }
    public static func playlist(_ id: Int) -> String { "sc:playlist:\(id)" }
    public static func trackNumber(_ value: String) -> Int? { number(value, prefix: "sc:") }
    public static func userNumber(_ value: String) -> Int? { number(value, prefix: "sc:user:") }
    public static func playlistNumber(_ value: String) -> Int? { number(value, prefix: "sc:playlist:") }
    public static func isSoundCloud(_ value: String) -> Bool { value.hasPrefix("sc:") }
    private static func number(_ value: String, prefix: String) -> Int? {
        guard value.hasPrefix(prefix) else { return nil }
        let digits = value.dropFirst(prefix.count)
        guard (1...19).contains(digits.count), digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber), let id = Int(digits), id > 0 else { return nil }
        return id
    }
}

/// Channel IDs accepted for subscriptions, groups and pinned tabs.
public enum ChannelIDs {
    public static func valid(_ id: String) -> Bool {
        id.range(of: "^UC[A-Za-z0-9_-]{22}$", options: .regularExpression) != nil || SoundCloudID.userNumber(id) != nil
    }
}

public enum SoundCloudSearchFilter: String, CaseIterable, Sendable {
    case tracks = "Tracks", users = "Users", playlists = "Playlists", all = "All"
    var path: String {
        switch self {
        case .tracks: return "/search/tracks"
        case .users: return "/search/users"
        case .playlists: return "/search/playlists"
        case .all: return "/search"
        }
    }
}

public struct SoundCloudStream: Sendable {
    public let url: URL
    public let title: String
    public let description: String
    public var item: BrowseItem? = nil
}

/// SoundCloud's web API (api-v2), authorised the way NewPipe does it: with the public client ID
/// that soundcloud.com's own scripts carry. The ID is cached in memory and refreshed once when
/// SoundCloud rejects it.
public actor SoundCloudClient {
    typealias Object = [String: Any]
    public static let shared = SoundCloudClient()
    static let api = "api-v2.soundcloud.com"
    static let paginationMarker = "soundcloud"
    private let session: URLSession
    private var clientID: String?
    public init(session: URLSession? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 25
        self.session = session ?? URLSession(configuration: configuration)
    }

    // MARK: Browsing

    public func search(_ query: String, filter: SoundCloudSearchFilter) async throws -> BrowsePage {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 500 else { throw BrowseError.invalidInput }
        var components = URLComponents(string: "https://\(Self.api)\(filter.path)")!
        components.queryItems = [URLQueryItem(name: "q", value: text), URLQueryItem(name: "limit", value: "20"), URLQueryItem(name: "offset", value: "0")]
        return try SoundCloudParser.page(try await json(components.url!), title: text)
    }
    public func user(_ id: String) async throws -> BrowsePage {
        guard let number = SoundCloudID.userNumber(id) else { throw BrowseError.invalidInput }
        let user = try await json(URL(string: "https://\(Self.api)/users/\(number)")!)
        var components = URLComponents(string: "https://\(Self.api)/users/\(number)/tracks")!
        components.queryItems = [URLQueryItem(name: "limit", value: "20"), URLQueryItem(name: "linked_partitioning", value: "1")]
        let tracks = try SoundCloudParser.page(try await json(components.url!), title: user["username"] as? String ?? "SoundCloud")
        let avatar = SoundCloudParser.artwork(user["avatar_url"] as? String)
        return BrowsePage(title: tracks.title, items: tracks.items, next: tracks.next,
                          header: BrowseHeader(description: user["description"] as? String ?? "", thumbnail: avatar))
    }
    public func playlist(_ id: String) async throws -> BrowsePage {
        guard let number = SoundCloudID.playlistNumber(id) else { throw BrowseError.invalidInput }
        let playlist = try await json(URL(string: "https://\(Self.api)/playlists/\(number)")!)
        let entries = playlist["tracks"] as? [[String: Any]] ?? []
        guard entries.count <= 5000 else { throw BrowseError.unavailable("This playlist is too large to open.") }
        // Only the first tracks come with metadata; the rest are IDs to fetch in batches of 50.
        var full = Dictionary(uniqueKeysWithValues: entries.compactMap { entry -> (Int, [String: Any])? in
            guard let id = entry["id"] as? Int, entry["title"] != nil else { return nil }; return (id, entry)
        })
        let missing = entries.compactMap { $0["id"] as? Int }.filter { full[$0] == nil }
        for start in stride(from: 0, to: missing.count, by: 50) {
            var components = URLComponents(string: "https://\(Self.api)/tracks")!
            components.queryItems = [URLQueryItem(name: "ids", value: missing[start..<min(start + 50, missing.count)].map(String.init).joined(separator: ","))]
            for track in try await jsonArray(components.url!) { if let id = track["id"] as? Int { full[id] = track } }
        }
        let ordered = entries.compactMap { ($0["id"] as? Int).flatMap { full[$0] } }
        return BrowsePage(title: playlist["title"] as? String ?? "Playlist", items: ordered.compactMap(SoundCloudParser.track), next: nil, header: nil)
    }
    public func related(_ id: String) async throws -> BrowsePage {
        guard let number = SoundCloudID.trackNumber(id) else { throw BrowseError.invalidInput }
        var components = URLComponents(string: "https://\(Self.api)/tracks/\(number)/related")!
        components.queryItems = [URLQueryItem(name: "limit", value: "20")]
        return try SoundCloudParser.page(try await json(components.url!), title: "Related tracks")
    }
    /// SoundCloud's trending chart, the source of NewPipe's SoundCloud kiosk.
    public func trending() async throws -> BrowsePage {
        var components = URLComponents(string: "https://\(Self.api)/charts")!
        components.queryItems = [URLQueryItem(name: "kind", value: "trending"), URLQueryItem(name: "genre", value: "soundcloud:genres:all-music"),
                                 URLQueryItem(name: "limit", value: "50")]
        return try SoundCloudParser.page(try await json(components.url!), title: "SoundCloud trending")
    }
    /// Plays, date and description, with a cursor for the track's comments.
    public func details(_ id: String) async throws -> VideoDetails {
        guard let number = SoundCloudID.trackNumber(id) else { throw BrowseError.invalidInput }
        let track = try await json(URL(string: "https://\(Self.api)/tracks/\(number)")!)
        let plays = (track["playback_count"] as? Int).map { "\($0.formatted()) plays" } ?? ""
        let date = ((track["display_date"] ?? track["created_at"]) as? String).flatMap(ISO8601DateFormatter().date)
            .map { $0.formatted(date: .abbreviated, time: .omitted) } ?? ""
        var comments: CommentCursor?
        if (track["comment_count"] as? Int ?? 0) > 0, track["commentable"] as? Bool != false {
            var components = URLComponents(string: "https://\(Self.api)/tracks/\(number)/comments")!
            components.queryItems = [URLQueryItem(name: "threaded", value: "1"), URLQueryItem(name: "filter_replies", value: "1"),
                                     URLQueryItem(name: "limit", value: "20"), URLQueryItem(name: "offset", value: "0")]
            comments = CommentCursor(token: components.url!.absoluteString, clientVersion: Self.paginationMarker)
        }
        return VideoDetails(views: plays, date: date, description: track["description"] as? String ?? "", comments: comments)
    }
    public func comments(_ cursor: CommentCursor) async throws -> CommentPage {
        guard cursor.clientVersion == Self.paginationMarker, let url = URL(string: cursor.token), url.scheme == "https", url.host == Self.api else {
            throw BrowseError.invalidInput
        }
        let root = try await json(url)
        let comments = (root["collection"] as? [Object] ?? []).prefix(200).compactMap { comment -> VideoComment? in
            guard let id = comment["id"] as? Int, let body = comment["body"] as? String, !body.isEmpty else { return nil }
            let user = comment["user"] as? Object
            let published = (comment["created_at"] as? String).flatMap(ISO8601DateFormatter().date)
                .map { $0.formatted(date: .abbreviated, time: .omitted) } ?? ""
            return VideoComment(id: "sc-\(id)", author: user?["username"] as? String ?? "SoundCloud user",
                                channelID: (user?["id"] as? Int).map(SoundCloudID.user), text: body, published: published, likes: "", replies: nil)
        }
        let next = (root["next_href"] as? String).flatMap(URL.init(string:)).flatMap { url -> CommentCursor? in
            guard url.scheme == "https", url.host == Self.api, !comments.isEmpty else { return nil }
            return CommentCursor(token: url.absoluteString, clientVersion: Self.paginationMarker)
        }
        return CommentPage(comments: comments, next: next)
    }
    /// A user's latest tracks with publication dates, for the subscriptions feed.
    public func feed(_ id: String) async throws -> [FeedVideo] {
        guard let number = SoundCloudID.userNumber(id) else { throw BrowseError.invalidInput }
        var components = URLComponents(string: "https://\(Self.api)/users/\(number)/tracks")!
        components.queryItems = [URLQueryItem(name: "limit", value: "15")]
        let collection = (try await json(components.url!))["collection"] as? [Object] ?? []
        let dates = ISO8601DateFormatter()
        return collection.compactMap { track in
            guard let item = SoundCloudParser.track(track),
                  let date = ((track["display_date"] ?? track["created_at"]) as? String).flatMap(dates.date) else { return nil }
            return FeedVideo(item: item, published: date)
        }
    }
    public func nextPage(_ cursor: BrowseCursor) async throws -> BrowsePage {
        guard cursor.clientVersion == Self.paginationMarker, let url = URL(string: cursor.token), url.scheme == "https", url.host == Self.api else {
            throw BrowseError.invalidInput
        }
        return try SoundCloudParser.page(try await json(url), title: "")
    }
    /// A soundcloud.com link turned into a track, user or playlist.
    public func resolve(_ shared: URL) async throws -> BrowseItem {
        var link = shared
        // on.soundcloud.com share links redirect to the permalink.
        if link.host?.lowercased() == "on.soundcloud.com" {
            let (_, response) = try await session.data(for: request(link))
            guard let final = (response as? HTTPURLResponse)?.url, final.host?.hasSuffix("soundcloud.com") == true, final.host != "on.soundcloud.com" else {
                throw BrowseError.unavailable("This SoundCloud link couldn't be opened.")
            }
            link = final
        }
        guard link.scheme == "https", ["soundcloud.com", "www.soundcloud.com", "m.soundcloud.com"].contains(link.host?.lowercased() ?? "") else {
            throw BrowseError.invalidInput
        }
        var components = URLComponents(string: "https://\(Self.api)/resolve")!
        components.queryItems = [URLQueryItem(name: "url", value: link.absoluteString)]
        let object = try await json(components.url!)
        guard let item = SoundCloudParser.item(object) else { throw BrowseError.unavailable("This SoundCloud link isn't a track, profile or playlist.") }
        return item
    }

    // MARK: Playback

    public func stream(_ id: String) async throws -> SoundCloudStream {
        guard let number = SoundCloudID.trackNumber(id) else { throw PlaybackError.invalidURL }
        let track = try await json(URL(string: "https://\(Self.api)/tracks/\(number)")!)
        if track["policy"] as? String == "BLOCK" { throw BrowseError.unavailable("This track isn't available in your country.") }
        let transcodings = ((track["media"] as? [String: Any])?["transcodings"] as? [[String: Any]]) ?? []
        guard let transcoding = SoundCloudParser.bestTranscoding(transcodings) else {
            throw BrowseError.unavailable(SoundCloudParser.unplayableReason(transcodings))
        }
        guard let raw = transcoding["url"] as? String, var components = URLComponents(string: raw), components.host == Self.api else {
            throw BrowseError.unsupportedResponse
        }
        if let authorization = track["track_authorization"] as? String {
            components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "track_authorization", value: authorization)]
        }
        let location = try await json(components.url!)
        guard let value = location["url"] as? String, let url = URL(string: value), url.scheme == "https" else { throw BrowseError.unsupportedResponse }
        return SoundCloudStream(url: url, title: track["title"] as? String ?? "SoundCloud track", description: track["description"] as? String ?? "",
                                item: SoundCloudParser.track(track))
    }

    // MARK: Requests

    private func json(_ url: URL) async throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: try await authorized(url)) as? [String: Any] else { throw BrowseError.unsupportedResponse }
        return object
    }
    private func jsonArray(_ url: URL) async throws -> [[String: Any]] {
        guard let array = try JSONSerialization.jsonObject(with: try await authorized(url)) as? [[String: Any]] else { throw BrowseError.unsupportedResponse }
        return array
    }
    /// Adds the client ID; on 401/403 fetches a fresh one and retries once.
    private func authorized(_ url: URL, retry: Bool = true) async throws -> Data {
        let id = try await currentClientID()
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false), components.host == Self.api else { throw BrowseError.unsupportedResponse }
        components.queryItems = (components.queryItems ?? []).filter { $0.name != "client_id" } + [URLQueryItem(name: "client_id", value: id)]
        let (data, response) = try await session.data(for: request(components.url!))
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.url?.host == Self.api, data.count <= 8_000_000 else { throw BrowseError.unsupportedResponse }
        if [401, 403].contains(http.statusCode), retry { clientID = nil; return try await authorized(url, retry: false) }
        if http.statusCode == 404 { throw BrowseError.unavailable("SoundCloud couldn't find this item. It may be private or removed.") }
        if http.statusCode == 429 { throw BrowseError.unavailable("SoundCloud is limiting requests right now. Try again later.") }
        guard http.statusCode == 200 else { throw BrowseError.unavailable("SoundCloud couldn't load this (\(http.statusCode)). Try again later.") }
        return data
    }
    private func currentClientID() async throws -> String {
        if let clientID { return clientID }
        let homeData = try await fetch(request(URL(string: "https://soundcloud.com")!), hosts: ["soundcloud.com"], limit: 4_000_000)
        guard let home = String(data: homeData, encoding: .utf8) else { throw BrowseError.unsupportedResponse }
        // The ID sits in one of the site's asset scripts, usually a later one; read only their start.
        for script in SoundCloudParser.assetScripts(in: home).reversed().prefix(12) {
            // Ask for the uncompressed start only; compressed responses ignore the range.
            var scriptRequest = request(script)
            scriptRequest.setValue("bytes=0-50000", forHTTPHeaderField: "Range")
            scriptRequest.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            guard let data = try? await fetch(scriptRequest, hosts: ["a-v2.sndcdn.com"], limit: 6_000_000),
                  let id = SoundCloudParser.clientID(in: String(decoding: data, as: UTF8.self)) else { continue }
            clientID = id
            return id
        }
        throw BrowseError.unavailable("SoundCloud couldn't be reached. Try again later.")
    }
    private func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        return request
    }
    private func fetch(_ request: URLRequest, hosts: Set<String>, limit: Int) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, hosts.contains(http.url?.host ?? ""), (200..<300).contains(http.statusCode), data.count <= limit else {
            throw BrowseError.unsupportedResponse
        }
        return data
    }
}

enum SoundCloudParser {
    typealias Object = [String: Any]
    static func assetScripts(in html: String) -> [URL] {
        let pattern = #"<script[^>]+src="(https://a-v2\.sndcdn\.com/assets/[A-Za-z0-9_./-]+\.js)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).prefix(50).compactMap {
            Range($0.range(at: 1), in: html).flatMap { URL(string: String(html[$0])) }
        }
    }
    static func clientID(in script: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #",client_id:"([A-Za-z0-9]{20,64})""#),
              let match = regex.firstMatch(in: script, range: NSRange(script.startIndex..., in: script)),
              let range = Range(match.range(at: 1), in: script) else { return nil }
        return String(script[range])
    }
    static func page(_ root: Object, title: String) throws -> BrowsePage {
        guard let collection = root["collection"] as? [Object] else { throw BrowseError.unsupportedResponse }
        // Charts wrap each track as {"track": …}.
        let items = collection.prefix(200).compactMap { item(($0["track"] as? Object) ?? $0) }
        let next = (root["next_href"] as? String).flatMap(URL.init(string:)).flatMap { url -> BrowseCursor? in
            guard url.scheme == "https", url.host == SoundCloudClient.api else { return nil }
            return BrowseCursor(token: url.absoluteString, clientVersion: SoundCloudClient.paginationMarker, isSearch: false)
        }
        return BrowsePage(title: title, items: items, next: items.isEmpty ? nil : next, header: nil)
    }
    static func item(_ object: Object) -> BrowseItem? {
        switch object["kind"] as? String {
        case "track": return track(object)
        case "user":
            guard let id = object["id"] as? Int, let name = object["username"] as? String, !name.isEmpty else { return nil }
            let followers = object["followers_count"] as? Int
            return BrowseItem(contentID: SoundCloudID.user(id), kind: .channel, title: name,
                              subtitle: followers.map { "\($0.formatted()) followers" } ?? "SoundCloud",
                              thumbnail: artwork(object["avatar_url"] as? String), webURL: web(object["permalink_url"]))
        case "playlist":
            guard let id = object["id"] as? Int, let title = object["title"] as? String, !title.isEmpty else { return nil }
            let owner = (object["user"] as? Object)?["username"] as? String ?? "SoundCloud"
            let count = object["track_count"] as? Int ?? 0
            return BrowseItem(contentID: SoundCloudID.playlist(id), kind: .playlist, title: title, subtitle: "\(owner) · \(count) tracks",
                              thumbnail: artwork(object["artwork_url"] as? String), webURL: web(object["permalink_url"]))
        default: return nil
        }
    }
    static func track(_ object: Object) -> BrowseItem? {
        guard let id = object["id"] as? Int, let title = object["title"] as? String, !title.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let user = object["user"] as? Object
        let milliseconds = object["full_duration"] as? Int ?? object["duration"] as? Int
        let duration = milliseconds.flatMap { value -> String? in
            let seconds = value / 1000
            guard seconds > 0, seconds < 8_640_000 else { return nil }
            return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60) : String(format: "%d:%02d", seconds / 60, seconds % 60)
        }
        return BrowseItem(contentID: SoundCloudID.track(id), kind: .video, title: title, subtitle: user?["username"] as? String ?? "",
                          thumbnail: artwork(object["artwork_url"] as? String) ?? artwork(user?["avatar_url"] as? String),
                          duration: duration, channelID: (user?["id"] as? Int).map(SoundCloudID.user), webURL: web(object["permalink_url"]))
    }
    /// Prefer full-length HLS AAC, then other full-length HLS. Snippets (previews) are skipped.
    static func bestTranscoding(_ transcodings: [Object]) -> Object? {
        let full = transcodings.filter { $0["snipped"] as? Bool != true && (($0["format"] as? Object)?["protocol"] as? String) == "hls" }
        func mime(_ item: Object) -> String { ((item["format"] as? Object)?["mime_type"] as? String) ?? "" }
        return full.first { mime($0).contains("mp4a") || mime($0).contains("aac") } ?? full.first { mime($0) == "audio/mpegurl" }
    }
    /// Why no transcoding is usable: none at all, DRM-only (encrypted HLS), or previews only.
    static func unplayableReason(_ transcodings: [Object]) -> String {
        if transcodings.isEmpty { return "SoundCloud doesn't offer playback for this track." }
        let protocols = transcodings.compactMap { ($0["format"] as? Object)?["protocol"] as? String }
        if protocols.allSatisfy({ $0.contains("encrypted") }) {
            return "This track is only available as DRM-protected audio, which DriftLoom can't play."
        }
        if transcodings.allSatisfy({ $0["snipped"] as? Bool == true }) { return "Only a preview of this track is available." }
        return "SoundCloud offers this track only in a format this device can't play."
    }
    /// SoundCloud artwork comes as "-large" (100 px); ask for the 500 px rendition.
    static func artwork(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value.replacingOccurrences(of: "-large.", with: "-t500x500.")), url.scheme == "https" else { return nil }
        return url
    }
    private static func web(_ value: Any?) -> URL? {
        guard let text = value as? String, let url = URL(string: text), url.scheme == "https", url.host?.hasSuffix("soundcloud.com") == true else { return nil }
        return url
    }
}

/// Saves a SoundCloud HLS stream as one file. SoundCloud serves a bare media playlist (init.mp4 plus
/// .m4s fragments, or .mp3 segments), which AVAssetDownloadTask can't store for offline playback;
/// concatenating the map and segments in order yields a regular fragmented MP4 (or MP3) file.
public enum SoundCloudDownload {
    public struct Playlist: Equatable, Sendable {
        public let map: URL?
        public let segments: [URL]
    }
    static let mediaHosts = ["soundcloud.cloud", "sndcdn.com"]

    static func trusted(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return mediaHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }
    /// Parse a VOD media playlist; reject encrypted, nested or off-host playlists.
    public static func parse(_ text: String, base: URL) throws -> Playlist {
        guard text.hasPrefix("#EXTM3U") else { throw BrowseError.unsupportedResponse }
        var map: URL?, segments: [URL] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#EXT-X-KEY"), !line.contains("METHOD=NONE") { throw BrowseError.unavailable("This track is encrypted and can't be saved.") }
            if line.hasPrefix("#EXT-X-STREAM-INF") { throw BrowseError.unsupportedResponse }
            if line.hasPrefix("#EXT-X-MAP:"), let start = line.range(of: "URI=\""), let end = line[start.upperBound...].firstIndex(of: "\"") {
                map = URL(string: String(line[start.upperBound..<end]), relativeTo: base)?.absoluteURL
            } else if !line.isEmpty, !line.hasPrefix("#"), let url = URL(string: line, relativeTo: base)?.absoluteURL {
                segments.append(url)
            }
        }
        guard !segments.isEmpty, segments.count <= 5000, segments.allSatisfy(trusted), map.map(trusted) ?? true else { throw BrowseError.unsupportedResponse }
        return Playlist(map: map, segments: segments)
    }

    /// Download the playlist's media into `directory/baseName.m4a` (fragmented MP4) or `.mp3`,
    /// reporting progress from 0 to 1, and return the file.
    public static func save(playlist url: URL, directory: URL, baseName: String, session: URLSession = .shared,
                            progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard trusted(url) else { throw BrowseError.unsupportedResponse }
        let (data, _) = try await session.data(from: url)
        guard data.count < 2_000_000, let text = String(data: data, encoding: .utf8) else { throw BrowseError.unsupportedResponse }
        let playlist = try parse(text, base: url)
        let output = directory.appendingPathComponent(baseName).appendingPathExtension(playlist.map == nil ? "mp3" : "m4a")
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: output.path, contents: nil)
        let handle = try FileHandle(forWritingTo: output)
        do {
            let parts = (playlist.map.map { [$0] } ?? []) + playlist.segments
            var written = 0
            for (index, part) in parts.enumerated() {
                try Task.checkCancellation()
                let (bytes, response) = try await session.data(from: part)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200, trusted(http.url ?? part) else {
                    throw BrowseError.unavailable("SoundCloud stopped the download. Retry to get a fresh link.")
                }
                written += bytes.count
                guard written <= 1_000_000_000 else { throw BrowseError.unavailable("This track is too large to save.") }
                try handle.write(contentsOf: bytes)
                progress(Double(index + 1) / Double(parts.count))
            }
            try handle.close()
            return output
        } catch {
            try? handle.close(); try? FileManager.default.removeItem(at: output)
            throw error
        }
    }
}
