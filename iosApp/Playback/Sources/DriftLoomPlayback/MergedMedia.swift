// SPDX-License-Identifier: GPL-3.0-or-later
import AVFoundation
import Foundation

/// Plays and saves a video-only stream together with a separate audio stream, without re-encoding.
public enum MergedMedia {
    /// A composition of both streams, trimmed to the shorter one.
    public static func composition(video: URL, audio: URL) async throws -> AVComposition {
        let videoAsset = AVURLAsset(url: video), audioAsset = AVURLAsset(url: audio)
        async let videoTracks = videoAsset.loadTracks(withMediaType: .video)
        async let audioTracks = audioAsset.loadTracks(withMediaType: .audio)
        async let videoDuration = videoAsset.load(.duration)
        async let audioDuration = audioAsset.load(.duration)
        guard let videoTrack = try await videoTracks.first, let audioTrack = try await audioTracks.first else {
            throw PlaybackError.noPlayableStream
        }
        let duration = CMTimeMinimum(try await videoDuration, try await audioDuration)
        guard duration.isNumeric, duration.seconds > 0 else { throw PlaybackError.noPlayableStream }
        let composition = AVMutableComposition()
        guard let videoOut = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioOut = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw PlaybackError.noPlayableStream
        }
        let range = CMTimeRange(start: .zero, duration: duration)
        try videoOut.insertTimeRange(range, of: videoTrack, at: .zero)
        try audioOut.insertTimeRange(range, of: audioTrack, at: .zero)
        videoOut.preferredTransform = try await videoTrack.load(.preferredTransform)
        return composition
    }

    /// Write both local files into one MP4 by copying their samples (passthrough).
    public static func export(video: URL, audio: URL, to output: URL) async throws {
        let composition = try await composition(video: video, audio: audio)
        try? FileManager.default.removeItem(at: output)
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw PlaybackError.noPlayableStream
        }
        session.outputURL = output
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = false
        await withTaskCancellationHandler {
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in session.exportAsynchronously { done.resume() } }
        } onCancel: { session.cancelExport() }
        try Task.checkCancellation()
        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: output)
            throw session.error ?? PlaybackError.noPlayableStream
        }
    }
}
