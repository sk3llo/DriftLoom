// SPDX-License-Identifier: GPL-3.0-or-later
import AVFoundation
import DriftLoomPlayback
import Foundation

@main
struct PlaybackProbe {
    @MainActor
    static func main() async throws {
        let input = CommandLine.arguments.dropFirst().first ?? "https://www.youtube.com/watch?v=11-9ZaYiTPE"
        let session = PlaybackSession()
        session.player.isMuted = true
        session.open(input)
        let checksSeek = CommandLine.arguments.contains("--seek-60")
        var hasSeeked = false
        for _ in 0..<120 {
            try await Task.sleep(for: .seconds(1))
            if case let .failed(message) = session.phase {
                session.stop()
                throw NSError(domain: "DriftLoomProbe", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: message])
            }
            let seconds = session.player.currentTime().seconds
            if checksSeek, !hasSeeked, seconds.isFinite, seconds >= 3 {
                hasSeeked = true
                let completed = await session.player.seek(to: CMTime(seconds: 60, preferredTimescale: 600))
                guard completed else {
                    throw NSError(domain: "DriftLoomProbe", code: 3,
                                  userInfo: [NSLocalizedDescriptionKey: "Seek to 60 seconds failed"])
                }
                session.player.play()
                continue
            }
            if seconds.isFinite, seconds >= (checksSeek ? 65 : 3) {
                print("PASS: native playback advanced to \(seconds)s; HLS=\(session.video?.usesHLS == true)")
                session.stop()
                return
            }
        }
        session.stop()
        throw NSError(domain: "DriftLoomProbe", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Playback did not advance within 120 seconds"])
    }
}
