// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import YouTubeKit

public struct VideoRequest: Equatable, Sendable {
    public let videoID: String
    public var watchURL: URL { URL(string: "https://www.youtube.com/watch?v=\(videoID)")! }

    public init(input: String) throws {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.validID(text) { videoID = text; return }
        guard let url = URLComponents(string: text),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil, url.port == nil,
              let host = url.host?.lowercased() else { throw PlaybackError.invalidURL }
        let parts = url.path.split(separator: "/").map(String.init)
        let id: String?
        if host == "youtu.be", parts.count == 1 {
            id = parts.first
        } else if ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"].contains(host) {
            if url.path == "/watch" {
                id = url.queryItems?.first(where: { $0.name == "v" })?.value
            } else if parts.count == 2, ["shorts", "live", "embed"].contains(parts[0]) {
                id = parts[1]
            } else { id = nil }
        } else { id = nil }
        guard let id, Self.validID(id) else { throw PlaybackError.invalidURL }
        videoID = id
    }

    private static func validID(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil
    }
}

public enum PlaybackError: LocalizedError {
    case invalidURL, noPlayableStream, extractionRefused

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Enter a YouTube video link or video ID."
        case .noPlayableStream: return "No stream supported by this device is available for this video."
        case .extractionRefused:
            return "YouTube didn't provide this video's streams. It may need a signed-in account, or YouTube may be limiting requests from this network. Try again later or on another network."
        }
    }

    /// Replace extractor errors that have no description with an explanation people can act on.
    static func readable(_ error: Error) -> Error {
        guard let kit = error as? YouTubeKitError else { return error }
        switch kit {
        case .extractError, .htmlParseError, .regexMatchError, .maxRetriesExceeded: return PlaybackError.extractionRefused
        case .videoRegionBlocked: return BrowseError.unavailable("This video isn't available in your region.")
        case .recordingUnavailable: return BrowseError.unavailable("This live recording isn't available.")
        default: return kit
        }
    }
}
