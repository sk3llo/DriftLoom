// SPDX-License-Identifier: GPL-3.0-or-later
#if DEBUG || DRIFTLOOM_DEVICE_TESTING
import AVFoundation
import DriftLoomPlayback
import Foundation
import os

@MainActor
func runDownloadSmokeCheck(_ playback: PlaybackSession) async {
    let arguments = ProcessInfo.processInfo.arguments
    guard arguments.contains("--download-smoke") || arguments.contains("--download-smoke-verify") else { return }
    playback.player.isMuted = true
    let log = Logger(subsystem: "net.driftloom.app", category: "DriftLoomDownloadSmoke")
    let manager = DownloadManager.shared
    do {
        for _ in 0..<50 where manager.reconnecting { try await Task.sleep(nanoseconds: 200_000_000) }
        let item = BrowseItem(contentID: "11-9ZaYiTPE", kind: .video, title: "Offline verification")
        let id: UUID
        if arguments.contains("--download-smoke-verify") {
            guard let record = manager.records.first(where: { $0.state == .completed }) else { throw BrowseError.unavailable("No completed download to verify") }
            id = record.id
            log.notice("START: verifying saved download after cold launch")
        } else {
            let choices = try await YouTubeDownloadResolver().choices(videoID: item.contentID)
            guard let choice = choices.first(where: { $0.kind == .hls }), let started = manager.start(item: item, choice: choice) else { throw PlaybackError.noPlayableStream }
            id = started
            log.notice("START: downloading verification HLS asset")
        }
        for _ in 0..<240 {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            guard let record = manager.records.first(where: { $0.id == id }) else { throw PlaybackError.noPlayableStream }
            if record.state == .failed { throw BrowseError.unavailable(record.error ?? "Download failed") }
            if record.state == .completed {
                guard let url = manager.localURL(record) else { throw PlaybackError.noPlayableStream }
                let asset = AVURLAsset(url: url)
                guard asset.assetCache?.isPlayableOffline == true else { throw PlaybackError.noPlayableStream }
                playback.open(item)
                var baseline: Double?
                for _ in 0..<50 {
                    try await Task.sleep(nanoseconds: 500_000_000)
                    let seconds = playback.player.currentTime().seconds
                    if playback.phase == .playing, seconds.isFinite, baseline == nil { baseline = seconds }
                    if let baseline, seconds - baseline > 5, playback.video?.streamURL.isFileURL == true {
                        log.notice("PASS: HLS asset is playable offline and local playback advanced past five seconds")
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
