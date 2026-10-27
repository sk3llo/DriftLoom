// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Where a shared YouTube or SoundCloud link should take the user.
public enum LinkTarget: Equatable, Sendable {
    case play(BrowseItem)
    case browse(BrowseRoute)
}

public enum LinkResolver {
    /// Resolve without network access where the link itself says what it is.
    public static func immediate(_ link: URL) -> LinkTarget? {
        if let request = try? VideoRequest(input: link.absoluteString) {
            return .play(BrowseItem(contentID: request.videoID, kind: .video, title: PlaybackSession.placeholderTitle))
        }
        guard let host = link.host?.lowercased(), host == "youtube.com" || host.hasSuffix(".youtube.com"),
              let components = URLComponents(url: link, resolvingAgainstBaseURL: false) else { return nil }
        let parts = link.path.split(separator: "/").map(String.init)
        if link.path == "/playlist", let list = components.queryItems?.first(where: { $0.name == "list" })?.value,
           list.range(of: "^[A-Za-z0-9_-]{2,150}$", options: .regularExpression) != nil, !list.hasPrefix("RD") {
            return .browse(.playlist(list))
        }
        if parts.count >= 2, parts[0] == "channel", ChannelIDs.valid(parts[1]), !SoundCloudID.isSoundCloud(parts[1]) {
            return .browse(.channel(parts[1]))
        }
        return nil
    }

    /// Resolve any supported link, asking the service when needed (YouTube handles, SoundCloud permalinks).
    /// Cookie-less like the browsing client, so EU visitors aren't sent to the consent page.
    public static let pageSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.urlCache = nil; configuration.timeoutIntervalForRequest = 25
        return URLSession(configuration: configuration)
    }()

    public static func resolve(_ link: URL, session: URLSession = pageSession) async throws -> LinkTarget {
        guard SharedLink.isSupported(link) else { throw BrowseError.unavailable(L("DriftLoom opens YouTube and SoundCloud links.")) }
        if let target = immediate(link) { return target }
        let host = link.host?.lowercased() ?? ""
        if host == "soundcloud.com" || host.hasSuffix(".soundcloud.com") {
            let item = try await SoundCloudClient.shared.resolve(link)
            if let route = item.destination { return .browse(route) }
            return .play(item)
        }
        // YouTube @handles and legacy /c/ and /user/ pages name a channel without its ID.
        let parts = link.path.split(separator: "/").map(String.init)
        if let first = parts.first, first.hasPrefix("@") || (parts.count >= 2 && ["c", "user"].contains(first)) {
            var request = URLRequest(url: link)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/18.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
            request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.url?.host == "www.youtube.com",
                  data.count < 8_000_000, let html = String(data: data, encoding: .utf8), let id = channelID(in: html) else {
                throw BrowseError.unavailable(L("YouTube couldn't find this channel."))
            }
            return .browse(.channel(id))
        }
        throw BrowseError.unavailable(L("This YouTube link isn't a video, playlist or channel DriftLoom can open."))
    }

    /// The channel a YouTube channel page is about, from its canonical link.
    static func channelID(in html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<link rel="canonical" href="https://www\.youtube\.com/channel/(UC[A-Za-z0-9_-]{22})""#),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[range])
    }
}
