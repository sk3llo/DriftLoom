// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import DriftLoomPlayback

final class FeedCheckTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func video(_ id: String, hoursAgo: Double, channel: String = "Channel") -> FeedVideo {
        FeedVideo(item: BrowseItem(contentID: id, kind: .video, title: "Video " + id, subtitle: channel), published: now.addingTimeInterval(-hoursAgo * 3600))
    }
    func testFirstCheckOnlyRecordsAndLaterChecksReportNewRecentVideos() {
        let first = FeedCheck.evaluate([video("a", hoursAgo: 2), video("b", hoursAgo: 30)], state: FeedCheckState(), now: now)
        XCTAssertTrue(first.newVideos.isEmpty, "Enabling notifications doesn't announce the existing feed")
        XCTAssertEqual(first.state.lastCheck, now)
        let later = now.addingTimeInterval(3600)
        let second = FeedCheck.evaluate([video("a", hoursAgo: 2), video("c", hoursAgo: 0.5), video("old", hoursAgo: 24 * 10), video("future", hoursAgo: -5)],
                                        state: first.state, now: later)
        XCTAssertEqual(second.newVideos.map(\.item.contentID), ["c"], "Old back-catalogue and far-future items never notify")
        let third = FeedCheck.evaluate([video("c", hoursAgo: 1)], state: second.state, now: later.addingTimeInterval(60))
        XCTAssertTrue(third.newVideos.isEmpty, "A video is announced once")
    }
    func testSeenListIsBounded() {
        var state = FeedCheckState(); state.lastCheck = now
        state.seen = (0..<FeedCheckState.seenLimit).map { "old\($0)" }
        let result = FeedCheck.evaluate((0..<10).map { video("n\($0)", hoursAgo: Double($0)) }, state: state, now: now)
        XCTAssertEqual(result.state.seen.count, FeedCheckState.seenLimit)
        XCTAssertTrue(result.state.seen.contains("n0")); XCTAssertFalse(result.state.seen.contains("old0"))
        XCTAssertEqual(result.newVideos.count, 10)
    }
    func testMessagesListFewVideosAndSummariseMany() {
        let few = FeedCheck.messages(for: [video("a", hoursAgo: 1, channel: "Lofi Girl")])
        XCTAssertEqual(few.count, 1); XCTAssertEqual(few[0].title, "Lofi Girl"); XCTAssertEqual(few[0].body, "Video a"); XCTAssertEqual(few[0].videoID, "a")
        let many = FeedCheck.messages(for: (0..<6).map { video("v\($0)", hoursAgo: 1, channel: "C\($0)") })
        XCTAssertEqual(many.count, 1); XCTAssertEqual(many[0].title, "6 new videos"); XCTAssertEqual(many[0].body, "From C0, C1, C2 and 3 more")
        XCTAssertNil(many[0].videoID)
        XCTAssertTrue(FeedCheck.messages(for: []).isEmpty)
    }
    func testFetchSkipsDuplicateChannelsAndCountsFailures() async {
        struct Loader: FeedLoading {
            func videos(channelID: String) async throws -> [FeedVideo] {
                if channelID == "bad" { throw BrowseError.unsupportedResponse }
                return [FeedVideo(item: BrowseItem(contentID: channelID + "-v", kind: .video, title: "x"), published: Date())]
            }
        }
        let result = await FeedCheck.fetch(channelIDs: ["a", "b", "a", "bad", "c"], client: Loader(), limit: 3)
        XCTAssertEqual(Set(result.videos.map(\.item.contentID)), ["a-v", "b-v"]); XCTAssertEqual(result.failed, 1)
    }
}
