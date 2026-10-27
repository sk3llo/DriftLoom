// SPDX-License-Identifier: GPL-3.0-or-later
import AVFoundation
import XCTest
@testable import DriftLoomPlayback

final class VideoRequestTests: XCTestCase {
    func testSupportedYouTubeLinksNormalizeToSameVideo() throws {
        for input in ["11-9ZaYiTPE", " https://www.youtube.com/watch?v=11-9ZaYiTPE&t=30 ",
                      "https://youtu.be/11-9ZaYiTPE?si=test", "https://m.youtube.com/watch?v=11-9ZaYiTPE",
                      "https://youtube.com/shorts/11-9ZaYiTPE", "https://youtube.com/live/11-9ZaYiTPE",
                      "https://www.youtube.com/embed/11-9ZaYiTPE"] {
            XCTAssertEqual(try VideoRequest(input: input).videoID, "11-9ZaYiTPE")
        }
    }

    func testRejectsSpoofedHostsAndNonVideoInputs() {
        for input in ["", "https://youtube.com.evil.test/watch?v=11-9ZaYiTPE",
                      "https://youtube.com@evil.test/watch?v=11-9ZaYiTPE",
                      "file:///11-9ZaYiTPE", "https://youtu.be/short", "https://youtube.com/playlist?list=11-9ZaYiTPE",
                      "https://youtu.be/11-9ZaYiTPE/extra", "https://example.com/watch?v=11-9ZaYiTPE"] {
            XCTAssertThrowsError(try VideoRequest(input: input), input)
        }
    }
}

final class RecoveryTests: XCTestCase {
    func testRefreshesForbiddenURLOnlyOncePerPlayback() {
        var policy = PlaybackRecoveryPolicy()
        XCTAssertFalse(policy.shouldRefresh(httpStatus: nil))
        XCTAssertFalse(policy.shouldRefresh(httpStatus: 500))
        XCTAssertFalse(policy.shouldRefresh(httpStatus: 404))
        XCTAssertTrue(policy.shouldRefresh(httpStatus: 403))
        XCTAssertFalse(policy.shouldRefresh(httpStatus: 403))
        policy = PlaybackRecoveryPolicy()
        XCTAssertTrue(policy.shouldRefresh(httpStatus: 403))
    }
}

private actor SuspendedResolver: StreamResolving {
    private var pending: [String: CheckedContinuation<ResolvedVideo, Error>] = [:]
    private var started: [String: CheckedContinuation<Void, Never>] = [:]

    func resolve(_ request: VideoRequest) async throws -> ResolvedVideo {
        try await withCheckedThrowingContinuation { continuation in
            pending[request.videoID] = continuation
            started.removeValue(forKey: request.videoID)?.resume()
        }
    }

    func waitForRequest(_ id: String) async {
        if pending[id] != nil { return }
        await withCheckedContinuation { started[id] = $0 }
    }

    func finish(_ id: String) {
        pending.removeValue(forKey: id)?.resume(returning: ResolvedVideo(
            title: id, streamURL: URL(string: "https://example.invalid/\(id).m3u8")!, usesHLS: true
        ))
    }
}

@MainActor
final class PlaybackSessionTests: XCTestCase {
    func testStoppedResolutionCannotInstallAnOldVideo() async {
        let resolver = SuspendedResolver()
        let session = PlaybackSession(resolver: resolver)
        session.open("11-9ZaYiTPE")
        await resolver.waitForRequest("11-9ZaYiTPE")
        session.stop()
        await resolver.finish("11-9ZaYiTPE")
        // Drain tasks on the main actor after the non-cooperative resolver returns.
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(session.phase, .idle)
        XCTAssertNil(session.player.currentItem)
        XCTAssertNil(session.video)
    }

    func testNewRequestWinsOverLateOldResolution() async {
        let resolver = SuspendedResolver()
        let session = PlaybackSession(resolver: resolver)
        session.open("11-9ZaYiTPE")
        await resolver.waitForRequest("11-9ZaYiTPE")
        session.open("QdBZY2fkU-0")
        await resolver.waitForRequest("QdBZY2fkU-0")
        await resolver.finish("11-9ZaYiTPE")
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(session.phase, .resolving)
        XCTAssertNil(session.player.currentItem)
        session.stop()
        await resolver.finish("QdBZY2fkU-0")
    }

    func testInvalidInputCancelsPreviousPlayback() async {
        let resolver = SuspendedResolver()
        let session = PlaybackSession(resolver: resolver)
        session.open("11-9ZaYiTPE")
        await resolver.waitForRequest("11-9ZaYiTPE")
        session.open("https://example.com/video")
        await resolver.finish("11-9ZaYiTPE")
        for _ in 0..<10 { await Task.yield() }
        guard case .failed = session.phase else { return XCTFail("Expected input error") }
        XCTAssertNil(session.player.currentItem)
    }
}
