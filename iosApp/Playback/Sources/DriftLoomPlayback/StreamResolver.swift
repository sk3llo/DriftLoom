// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import YouTubeKit

public struct ResolvedVideo: Sendable {
    public let title: String
    public let streamURL: URL
    public let usesHLS: Bool
    public let description: String
    /// Separate audio stream to play alongside a video-only `streamURL`.
    public let audioURL: URL?

    public init(title: String, streamURL: URL, usesHLS: Bool, description: String = "", audioURL: URL? = nil) {
        self.title = title
        self.streamURL = streamURL
        self.usesHLS = usesHLS
        self.description = description
        self.audioURL = audioURL
    }
}

public protocol StreamResolving: Sendable {
    func resolve(_ request: VideoRequest) async throws -> ResolvedVideo
    func resolve(_ request: VideoRequest, choice: DownloadChoice?) async throws -> ResolvedVideo
}

public extension StreamResolving {
    func resolve(_ request: VideoRequest, choice: DownloadChoice?) async throws -> ResolvedVideo {
        guard choice == nil else { throw PlaybackError.noPlayableStream }
        return try await resolve(request)
    }
}

public struct YouTubeStreamResolver: StreamResolving {
    public init() {}

    public func resolve(_ request: VideoRequest, choice: DownloadChoice?) async throws -> ResolvedVideo {
        do { return try await resolveChoice(request, choice: choice) } catch { throw PlaybackError.readable(error) }
    }
    private func resolveChoice(_ request: VideoRequest, choice: DownloadChoice?) async throws -> ResolvedVideo {
        guard let choice else { return try await resolveDefault(request) }
        let source = try await YouTubeDownloadResolver().source(videoID: request.videoID, choice: choice)
        let metadata = try? await YouTube(videoID: request.videoID, methods: [.local]).metadata
        return ResolvedVideo(title: metadata?.title ?? "YouTube video", streamURL: source.url,
                             usesHLS: choice.kind == .hls, description: metadata?.description ?? "", audioURL: source.audioURL)
    }

    public func resolve(_ request: VideoRequest) async throws -> ResolvedVideo {
        do { return try await resolveDefault(request) } catch { throw PlaybackError.readable(error) }
    }
    private func resolveDefault(_ request: VideoRequest) async throws -> ResolvedVideo {
        // A new instance for every resolution avoids reusing expired signed URLs.
        // Explicitly disable the library's optional third-party remote extraction.
        let video = YouTube(videoID: request.videoID, methods: [.local])
        let metadata = try? await video.metadata
        let title = metadata?.title ?? "YouTube video"
        try Task.checkCancellation()
        if let stream = try? await video.livestreams.first(where: { $0.streamType == .hls }) {
            return ResolvedVideo(title: title, streamURL: stream.url, usesHLS: true, description: metadata?.description ?? "")
        }
        try Task.checkCancellation()
        let streams = try await video.streams
        guard let stream = streams.filterVideoAndAudio()
            .filter({ $0.isNativelyPlayable }).highestResolutionStream() else {
            throw PlaybackError.noPlayableStream
        }
        return ResolvedVideo(title: title, streamURL: stream.url, usesHLS: false, description: metadata?.description ?? "")
    }
}

public struct PlaybackRecoveryPolicy {
    public private(set) var hasRefreshed = false
    public init() {}

    public mutating func shouldRefresh(httpStatus: Int?) -> Bool {
        guard httpStatus == 403, !hasRefreshed else { return false }
        hasRefreshed = true
        return true
    }
}
