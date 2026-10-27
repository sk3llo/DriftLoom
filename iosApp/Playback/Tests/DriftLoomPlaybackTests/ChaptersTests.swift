// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import DriftLoomPlayback

final class ChaptersTests: XCTestCase {
    func testParsesLeadingAndTrailingTimestamps() {
        let description = """
        My album, full length.
        0:00 Intro
        (1:15) – Second song
        Third song - 4:02
        1:02:03 Finale
        Thanks for watching! Follow me at 12:30 on Fridays.
        """
        let chapters = VideoChapters.parse(description)
        XCTAssertEqual(chapters.map(\.start), [0, 75, 242, 3723])
        XCTAssertEqual(chapters.map(\.title), ["Intro", "Second song", "Third song", "Finale"])
    }

    func testYouTubeRulesRejectInvalidLists() {
        XCTAssertEqual(VideoChapters.parse("0:00 A\n1:00 B"), [], "At least three")
        XCTAssertEqual(VideoChapters.parse("0:05 A\n1:00 B\n2:00 C"), [], "The first starts at 0:00")
        XCTAssertEqual(VideoChapters.parse("0:00 A\n0:05 B\n2:00 C"), [], "At least 10 seconds apart")
        XCTAssertEqual(VideoChapters.parse("Song at 3:00 is great\nno chapters here"), [])
    }

    func testOutOfOrderLinesAreIgnoredAndDurationTrims() {
        let chapters = VideoChapters.parse("00:00 A\n02:00 B\n01:00 stray\n03:00 C\n09:00 D", duration: 300)
        XCTAssertEqual(chapters.map(\.title), ["A", "B", "C"])
        XCTAssertEqual(VideoChapters.index(at: 130, in: chapters), 1)
        XCTAssertEqual(VideoChapters.index(at: 0, in: chapters), 0)
    }
}

@MainActor
final class DefaultResolutionTests: XCTestCase {
    func testPlayerChoiceLastsUntilTheNextVideoAndDefaultsFollowTheNetwork() {
        let playback = PlaybackSession(resolver: UnavailableResolver())
        playback.defaultMaximumHeight = 480
        playback.open("dQw4w9WgXcQ")
        XCTAssertEqual(playback.maximumHeight, 480)
        playback.setMaximumHeight(1080)
        playback.defaultMaximumHeight = 360
        XCTAssertEqual(playback.maximumHeight, 1080, "A choice in the player wins over a network change")
        playback.open("11-9ZaYiTPE")
        XCTAssertEqual(playback.maximumHeight, 360, "The next video starts from the default")
        playback.defaultMaximumHeight = 0
        XCTAssertEqual(playback.maximumHeight, 0)
    }
}

@MainActor
final class AutoplayRelatedTests: XCTestCase {
    private let a = BrowseItem(contentID: "11-9ZaYiTPE", kind: .video, title: "A")
    private let b = BrowseItem(contentID: "dQw4w9WgXcQ", kind: .video, title: "B")
    private let c = BrowseItem(contentID: "jNQXAC9IVRw", kind: .video, title: "C")

    private func queue(_ related: [BrowseItem]) -> PlaybackQueue {
        let queue = PlaybackQueue(playback: PlaybackSession(resolver: UnavailableResolver()))
        queue.relatedVideos = { _ in related }
        return queue
    }

    func testLastVideoEndingQueuesTheFirstRelatedVideoNotAlreadyQueued() async throws {
        let queue = queue([BrowseItem(contentID: "UCx", kind: .channel, title: "Channel"), a, c])
        queue.autoplaysRelated = true
        queue.start([a, b], at: 1)
        queue.didFinishCurrent()
        for _ in 0..<50 where queue.entries.count < 3 { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(queue.entries.map(\.item.contentID), [a.contentID, b.contentID, c.contentID])
        XCTAssertEqual(queue.entries.last?.id, queue.currentID, "The related video plays")
    }

    func testOffByDefaultAndWithRepeat() async throws {
        let off = queue([c])
        off.start([a])
        off.didFinishCurrent()
        let repeating = queue([c])
        repeating.autoplaysRelated = true
        repeating.repeatMode = .all
        repeating.start([a, b], at: 1)
        repeating.didFinishCurrent()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(off.entries.count, 1)
        XCTAssertEqual(repeating.entries.count, 2)
        XCTAssertEqual(repeating.currentIndex, 0, "Repeat all goes back to the start instead")
    }
}
