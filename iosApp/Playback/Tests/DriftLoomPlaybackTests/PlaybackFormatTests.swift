// SPDX-License-Identifier: GPL-3.0-or-later
import AVFoundation
import XCTest
@testable import DriftLoomPlayback

private actor LocalFormatResolver: StreamResolving {
    let url: URL
    private(set) var choices: [DownloadChoice?] = []
    init(url: URL) { self.url = url }
    func resolve(_ request: VideoRequest) async throws -> ResolvedVideo { try await resolve(request, choice: nil) }
    func resolve(_ request: VideoRequest, choice: DownloadChoice?) async throws -> ResolvedVideo {
        choices.append(choice)
        return ResolvedVideo(title: "Local format fixture", streamURL: url, usesHLS: false)
    }
}

@MainActor
final class PlaybackFormatTests: XCTestCase {
    func testChangingFormatKeepsPausedStateAndPositionWithRealMedia() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: file) }
        var wav = Data()
        func word(_ value: UInt32, _ bytes: Int) { for index in 0..<bytes { wav.append(UInt8((value >> (index * 8)) & 255)) } }
        wav.append(Data("RIFF".utf8)); word(960036, 4); wav.append(Data("WAVEfmt ".utf8)); word(16, 4)
        word(1, 2); word(1, 2); word(8000, 4); word(16000, 4); word(2, 2); word(16, 2)
        wav.append(Data("data".utf8)); word(960000, 4); wav.append(Data(repeating: 0, count: 960000))
        try wav.write(to: file)
        let resolver = LocalFormatResolver(url: file)
        let session = PlaybackSession(resolver: resolver)
        session.player.isMuted = true
        session.open("11-9ZaYiTPE")
        for _ in 0..<100 where session.phase != .playing { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(session.phase, .playing)
        session.player.pause()
        _ = await session.player.seek(to: CMTime(seconds: 8, preferredTimescale: 600))
        for _ in 0..<100 where session.phase != .paused { try await Task.sleep(nanoseconds: 20_000_000) }
        let choice = DownloadChoice(id: "18", name: "360p", kind: .video)
        session.selectFormat(choice)
        for _ in 0..<100 where session.player.currentItem?.status != .readyToPlay || session.phase != .paused {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(session.player.rate, 0)
        XCTAssertEqual(session.phase, .paused)
        XCTAssertEqual(session.player.currentTime().seconds, 8, accuracy: 0.1)
        let calls = await resolver.choices
        XCTAssertEqual(calls.count, 2); XCTAssertEqual(calls.last!, choice)
        session.stop()
    }
}
