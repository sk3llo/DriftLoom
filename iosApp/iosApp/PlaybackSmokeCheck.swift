#if DEBUG || DRIFTLOOM_DEVICE_TESTING
import AVFoundation
import DriftLoomPlayback
import Foundation
import UIKit

/// Opt-in device/simulator check. Compiled out of normal Release builds.
@MainActor
func runPlaybackSmokeCheck(_ session: PlaybackSession) async {
    let arguments = ProcessInfo.processInfo.arguments
    let flag = arguments.firstIndex(of: "--playback-smoke-url")
    guard flag != nil || arguments.contains("--browse-smoke-play") else { return }
    session.player.isMuted = true
    // --subtitle-smoke LANG: turn on subtitles in that language and require a visible cue.
    let subtitleFlag = arguments.firstIndex(of: "--subtitle-smoke")
    if let subtitleFlag, arguments.indices.contains(subtitleFlag + 1) { session.preferredSubtitleLanguage = arguments[subtitleFlag + 1] }
    var subtitleReported = subtitleFlag == nil
    if let flag, arguments.indices.contains(flag + 1) { session.open(arguments[flag + 1]) }
    var hasSeeked = false
    for _ in 0..<90 {
        do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
        if case .failed = session.phase {
            NSLog("DriftLoomSmoke: FAIL playback error")
            return
        }
        let seconds = session.player.currentTime().seconds
        if !subtitleReported, let error = session.subtitleError {
            subtitleReported = true; NSLog("DriftLoomSubtitleSmoke: FAIL %@", error)
        } else if !subtitleReported, hasSeeked, let text = session.subtitleText, let track = session.selectedSubtitle {
            subtitleReported = true
            NSLog("DriftLoomSubtitleSmoke: PASS track=%@ of %d at %.1fs: %@", track.id, session.subtitleTracks.count, seconds, text)
        }
        if !hasSeeked, seconds.isFinite, seconds >= 3 {
            hasSeeked = true
            let finished = await session.player.seek(to: CMTime(seconds: 60, preferredTimescale: 600))
            guard finished else { NSLog("DriftLoomSmoke: FAIL seeking"); return }
            session.player.play()
        } else if hasSeeked, seconds.isFinite, seconds >= 65 {
            NSLog("DriftLoomSmoke: PASS advanced past 65 seconds; HLS=%d", session.video?.usesHLS == true ? 1 : 0)
            return
        }
    }
    NSLog("DriftLoomSmoke: FAIL timed out")
}

@MainActor
func runBrowseSmokeCheck(_ store: BrowseStore, onPlay: (BrowseItem) -> Void) async {
    let arguments = ProcessInfo.processInfo.arguments
    guard arguments.contains("--browse-smoke-query"), !Task.isCancelled, !store.isLoading else { return }
    guard store.error == nil, !store.items.isEmpty else {
        NSLog("DriftLoomBrowseSmoke: FAIL search")
        return
    }
    NSLog("DriftLoomBrowseSmoke: PASS rendered search results=%d", store.items.count)
    if arguments.contains("--browse-smoke-play") {
        if store.canLoadMore {
            await store.loadMore()
            guard store.paginationError == nil else { NSLog("DriftLoomBrowseSmoke: FAIL pagination"); return }
            NSLog("DriftLoomBrowseSmoke: PASS pagination results=%d", store.items.count)
        }
        guard let video = store.items.first(where: { $0.kind == .video }) else {
            NSLog("DriftLoomBrowseSmoke: FAIL no video")
            return
        }
        onPlay(video)
    }
}

@MainActor
func runBackgroundSmokeCheck(_ session: PlaybackSession) async {
    guard ProcessInfo.processInfo.arguments.contains("--background-smoke"), session.phase == .playing else { return }
    NSLog("DriftLoomBackgroundSmoke: READY send app to background")
    var started: Double?
    for _ in 0..<60 {
        do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
        if UIApplication.shared.applicationState == .background {
            let seconds = session.player.currentTime().seconds
            guard seconds.isFinite else { continue }
            if let start = started, seconds - start >= 8 {
                NSLog("DriftLoomBackgroundSmoke: PASS playback advanced for eight seconds in background")
                return
            }
            if started == nil { started = seconds }
        } else { started = nil }
    }
    NSLog("DriftLoomBackgroundSmoke: FAIL playback did not advance in background")
}
#endif
