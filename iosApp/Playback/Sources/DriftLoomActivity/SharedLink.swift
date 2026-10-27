// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Links handed to DriftLoom from other apps: found in shared text, wrapped in the app's
/// `driftloom://open?url=` scheme by the share extension, and unwrapped again by the app.
public enum SharedLink {
    public static let scheme = "driftloom"
    static let hosts = ["youtube.com", "youtu.be", "soundcloud.com"]

    /// YouTube (including youtu.be and music.youtube.com) and SoundCloud (including on.soundcloud.com) over https.
    public static func isSupported(_ url: URL) -> Bool {
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.user == nil, url.password == nil,
              let host = url.host?.lowercased() else { return false }
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }
    /// The first supported link in shared text, e.g. "Watch this! https://youtu.be/… via YouTube".
    public static func firstSupportedURL(in text: String) -> URL? {
        guard text.count <= 20_000, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).lazy.compactMap(\.url).first(where: isSupported)
    }
    /// `driftloom://open?url=<link>` for a supported link.
    public static func appURL(for link: URL) -> URL? {
        guard isSupported(link) else { return nil }
        var components = URLComponents()
        components.scheme = scheme; components.host = "open"
        components.queryItems = [URLQueryItem(name: "url", value: link.absoluteString)]
        return components.url
    }
    /// The link inside an app URL, or the link itself when it's already a supported web link.
    public static func target(of url: URL) -> URL? {
        if url.scheme?.lowercased() == scheme {
            guard url.host == "open", let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "url" })?.value,
                  value.count <= 4096, let link = URL(string: value), isSupported(link) else { return nil }
            return link
        }
        return isSupported(url) ? url : nil
    }
}
