#if DEBUG
import AVFoundation
import DriftLoomPlayback
import Foundation

/// Opt-in simulator smoke check. No network traffic occurs unless the launch flag is supplied.
@MainActor
func runPlaybackSmokeCheck(_ session: PlaybackSession) async {
    let arguments = ProcessInfo.processInfo.arguments
    guard let flag = arguments.firstIndex(of: "--playback-smoke-url"),
          arguments.indices.contains(flag + 1) else { return }
    session.player.isMuted = true
    session.open(arguments[flag + 1])
    var hasSeeked = false
    for _ in 0..<90 {
        do { try await Task.sleep(for: .seconds(1)) } catch { return }
        if case .failed = session.phase {
            NSLog("DriftLoomSmoke: FAIL playback error")
            return
        }
        let seconds = session.player.currentTime().seconds
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
#endif
