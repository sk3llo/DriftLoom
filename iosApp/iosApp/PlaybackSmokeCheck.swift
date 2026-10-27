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
    // --subtitle-smoke-translate: allow YouTube's machine translation when no native track matches.
    if arguments.contains("--subtitle-smoke-translate") { session.translatesSubtitles = true }
    var subtitleReported = subtitleFlag == nil
    if let flag, arguments.indices.contains(flag + 1) { session.open(arguments[flag + 1]) }
    // --playback-smoke-merged: play the highest separate video+audio format this device decodes.
    if arguments.contains("--playback-smoke-merged"), let id = session.videoID {
        guard let merged = (try? await YouTubeDownloadResolver().choices(videoID: id))?.last(where: { $0.kind == .merged }) else {
            NSLog("DriftLoomSmoke: FAIL no merged format"); return
        }
        NSLog("DriftLoomSmoke: START %@", merged.name)
        session.selectFormat(merged)
    }
    var hasSeeked = false
    // --chapters-smoke: give the video sample chapters (YouTube refuses most videos with real ones from test networks).
    var needsChapters = arguments.contains("--chapters-smoke")
    for _ in 0..<90 {
        do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
        if needsChapters, session.player.currentItem?.status == .readyToPlay, let id = session.videoID {
            needsChapters = false
            session.useChapters(fromDescription: "0:00 Intro\n0:43 First verse\n1:25 Chorus\n2:30 Bridge\n3:00 Final chorus", videoID: id)
        }
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
            let size = session.player.currentItem?.presentationSize ?? .zero
            NSLog("DriftLoomSmoke: PASS advanced past 65 seconds; HLS=%d; separate audio=%d; %dx%d", session.video?.usesHLS == true ? 1 : 0,
                  session.video?.audioURL != nil ? 1 : 0, Int(size.width), Int(size.height))
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
