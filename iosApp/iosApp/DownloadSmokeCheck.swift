// SPDX-License-Identifier: GPL-3.0-or-later
#if DEBUG || DRIFTLOOM_DEVICE_TESTING
import AVFoundation
import DriftLoomPlayback
import Foundation
import os

@MainActor
func runDownloadSmokeCheck(_ playback: PlaybackSession) async {
    let arguments = ProcessInfo.processInfo.arguments
    if arguments.contains("--download-smoke-cleanup"), arguments.contains("--library-smoke-run") {
        // Delete this isolated run's downloads, media and subtitle files through the normal delete path.
        let manager = DownloadManager.shared
        for _ in 0..<50 where manager.reconnecting { try? await Task.sleep(nanoseconds: 200_000_000) }
        let ids = manager.records.map(\.id)
        ids.forEach(manager.remove)
        let left = manager.records.count
        Logger(subsystem: "net.driftloom.app", category: "DriftLoomDownloadSmoke")
            .notice("\(left == 0 ? "PASS" : "FAIL", privacy: .public): cleanup removed \(ids.count - left) of \(ids.count) downloads")
        return
    }
    guard arguments.contains("--download-smoke") || arguments.contains("--download-smoke-verify") else { return }
    playback.player.isMuted = true
    let log = Logger(subsystem: "net.driftloom.app", category: "DriftLoomDownloadSmoke")
    let manager = DownloadManager.shared
    do {
        for _ in 0..<50 where manager.reconnecting { try await Task.sleep(nanoseconds: 200_000_000) }
        func value(after flag: String) -> String? {
            arguments.firstIndex(of: flag).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        }
        // --download-smoke-video ID picks another video; --download-smoke-subtitles LANG also saves
        // subtitles with the download and requires them to show from the saved file.
        let videoID = value(after: "--download-smoke-video").flatMap { try? VideoRequest(input: $0).videoID } ?? "11-9ZaYiTPE"
        let subtitleLanguage = value(after: "--download-smoke-subtitles")
        let item = BrowseItem(contentID: videoID, kind: .video, title: "Offline verification")
        let id: UUID
        if arguments.contains("--download-smoke-verify") {
            guard let record = manager.records.first(where: { $0.state == .completed && $0.item.contentID == videoID }) else { throw BrowseError.unavailable("No completed download to verify") }
            id = record.id
            log.notice("START: verifying saved download after cold launch")
        } else {
            let choices = try await YouTubeDownloadResolver().choices(videoID: item.contentID)
            // --download-smoke-merged: download the lowest separate video+audio format and combine it.
            let kind: DownloadChoice.Kind = SoundCloudID.isSoundCloud(videoID) ? .audio : arguments.contains("--download-smoke-merged") ? .merged : .hls
            guard let choice = choices.first(where: { $0.kind == kind }),
                  let started = manager.start(item: item, choice: choice, subtitleLanguage: subtitleLanguage) else { throw PlaybackError.noPlayableStream }
            id = started
            log.notice("START: downloading verification asset \(choice.name, privacy: .public)")
        }
        for _ in 0..<240 {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            guard let record = manager.records.first(where: { $0.id == id }) else { throw PlaybackError.noPlayableStream }
            if record.state == .failed { throw BrowseError.unavailable(record.error ?? "Download failed") }
            if record.state == .completed {
                guard let url = manager.localURL(record) else { throw PlaybackError.noPlayableStream }
                let asset = AVURLAsset(url: url)
                if record.choice.kind == .hls {
                    guard asset.assetCache?.isPlayableOffline == true else { throw PlaybackError.noPlayableStream }
                } else {
                    let videoTracks = try await asset.loadTracks(withMediaType: .video), audioTracks = try await asset.loadTracks(withMediaType: .audio)
                    guard (record.choice.kind == .audio || !videoTracks.isEmpty), !audioTracks.isEmpty else { throw PlaybackError.noPlayableStream }
                    let size = try await videoTracks.first?.load(.naturalSize) ?? .zero
                    log.notice("FILE: \(record.choice.name, privacy: .public) has \(videoTracks.count) video and \(audioTracks.count) audio tracks, \(Int(size.width))x\(Int(size.height))")
                }
                if let subtitleLanguage {
                    guard record.subtitlePath != nil else { throw BrowseError.unavailable("Subtitles weren't saved: " + (record.subtitleError ?? "unknown")) }
                    playback.preferredSubtitleLanguage = subtitleLanguage
                }
                playback.open(item)
                var baseline: Double?, subtitleSeen = subtitleLanguage == nil
                for _ in 0..<120 {
                    try await Task.sleep(nanoseconds: 500_000_000)
                    let seconds = playback.player.currentTime().seconds
                    if playback.phase == .playing, seconds.isFinite, baseline == nil { baseline = seconds }
                    if !subtitleSeen, playback.selectedSubtitle?.url.isFileURL == true, let text = playback.subtitleText {
                        subtitleSeen = true
                        log.notice("PASS: saved subtitles shown from the download: \(text, privacy: .public)")
                    }
                    if let baseline, seconds - baseline > 5, playback.video?.streamURL.isFileURL == true, subtitleSeen {
                        log.notice("PASS: \(record.choice.kind.rawValue, privacy: .public) asset is playable offline and local playback advanced past five seconds")
                        return
                    }
                    if case let .failed(message) = playback.phase { throw BrowseError.unavailable(message) }
                }
                throw BrowseError.unavailable("Local playback did not advance")
            }
        }
        throw BrowseError.unavailable("Download timed out")
    } catch { log.error("FAIL: \(error.localizedDescription, privacy: .public)") }
}
#endif
