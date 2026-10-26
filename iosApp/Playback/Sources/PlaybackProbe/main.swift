// SPDX-License-Identifier: GPL-3.0-or-later
import AVFoundation
import DriftLoomPlayback
import Foundation

@main
struct PlaybackProbe {
    @MainActor
    static func main() async throws {
        let input = CommandLine.arguments.dropFirst().first ?? "https://www.youtube.com/watch?v=11-9ZaYiTPE"
        let arguments = CommandLine.arguments
        let subtitleLanguage = arguments.firstIndex(of: "--subtitles").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        let session = PlaybackSession(subtitles: subtitleLanguage == nil ? nil : YouTubeSubtitleClient())
        session.preferredSubtitleLanguage = subtitleLanguage
        session.player.isMuted = true
        session.open(input)
        // --merged: play the highest separate video+audio format instead of automatic HLS.
        if arguments.contains("--merged"), let id = session.videoID {
            let choices = try await YouTubeDownloadResolver().choices(videoID: id)
            guard let merged = choices.last(where: { $0.kind == .merged }) else {
                throw NSError(domain: "DriftLoomProbe", code: 5, userInfo: [NSLocalizedDescriptionKey: "No merged format offered"])
            }
            print("Merged formats:", choices.filter { $0.kind == .merged }.map(\.name).joined(separator: ", "))
            session.selectFormat(merged)
        }
        var shownSubtitle: String?
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
            if let text = session.subtitleText { shownSubtitle = text }
            if let error = session.subtitleError {
                throw NSError(domain: "DriftLoomProbe", code: 4, userInfo: [NSLocalizedDescriptionKey: "Subtitles failed: " + error])
            }
            if subtitleLanguage != nil, shownSubtitle == nil { continue }
            if seconds.isFinite, seconds >= (checksSeek ? 65 : 3) {
                if let track = session.selectedSubtitle, let shownSubtitle {
                    print("PASS: subtitles \(track.id) of \(session.subtitleTracks.count) tracks; shown: \(shownSubtitle.replacingOccurrences(of: "\n", with: " / "))")
                }
                print("PASS: native playback advanced to \(seconds)s; HLS=\(session.video?.usesHLS == true); separate audio=\(session.video?.audioURL != nil); size=\(session.player.currentItem?.presentationSize ?? .zero)")
                session.stop()
                return
            }
        }
        session.stop()
        throw NSError(domain: "DriftLoomProbe", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Playback did not advance within 120 seconds"])
    }
}
