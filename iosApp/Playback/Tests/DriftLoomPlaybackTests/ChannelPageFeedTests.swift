// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import DriftLoomPlayback

final class ChannelPageFeedTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testRelativeTimesFromEnglishPagesBecomeDates() {
        let cases: [(String, Double)] = [
            ("13\u{00A0}min ago", 13 * 60), ("1h ago", 3600), ("11 hours ago", 11 * 3600), ("1d ago", 86400), ("2 days ago", 2 * 86400),
            ("3w ago", 21 * 86400), ("1 week ago", 7 * 86400), ("2mo ago", 60 * 86400), ("4 months ago", 120 * 86400),
            ("1y ago", 365 * 86400), ("6 years ago", 6 * 365 * 86400), ("Streamed 5h ago", 5 * 3600), ("30 seconds ago", 30),
        ]
        for (text, seconds) in cases {
            XCTAssertEqual(RelativeTime.date(text, now: now), now.addingTimeInterval(-seconds), text)
        }
        XCTAssertNil(RelativeTime.date("1.2M views", now: now))
        XCTAssertNil(RelativeTime.date("Premieres tomorrow", now: now))
    }

    func testChannelVideosTabBecomesFeedVideos() throws {
        func lockup(_ id: String, _ title: String, _ age: String) -> [String: Any] {
            ["lockupViewModel": [
                "contentId": id, "contentType": "LOCKUP_CONTENT_TYPE_VIDEO",
                "contentImage": ["thumbnailViewModel": ["image": ["sources": [["url": "https://i.ytimg.com/vi/\(id)/hqdefault.jpg", "width": 480, "height": 270]]]]],
                "metadata": ["lockupMetadataViewModel": [
                    "title": ["content": title],
                    "metadata": ["contentMetadataViewModel": ["metadataRows": [["metadataParts": [["text": ["content": "1.2K views"]], ["text": ["content": age]]]]]]],
                ]],
            ]]
        }
        let data: [String: Any] = [
            "metadata": ["channelMetadataRenderer": ["title": "CNN"]],
            "contents": ["twoColumnBrowseResultsRenderer": ["tabs": [["tabRenderer": ["content": ["richGridRenderer": ["contents": [
                ["richItemRenderer": ["content": lockup("aaaaaaaaaaa", "Newest", "13\u{00A0}min ago")]],
                ["richItemRenderer": ["content": lockup("bbbbbbbbbbb", "Older", "2d ago")]],
                ["richItemRenderer": ["content": lockup("ccccccccccc", "Undated", "Scheduled")]],
                ["richItemRenderer": ["content": lockup("aaaaaaaaaaa", "Newest", "13 min ago")]],
            ]]]]]]]],
        ]
        let json = String(data: try JSONSerialization.data(withJSONObject: data), encoding: .utf8)!
        let html = "<html><script>var ytInitialData = \(json);</script></html>"
        let estimates = try YouTubeFeedClient.uploads(fromChannelPage: html, channelID: "UCupvZG-5ko_eiXAupbDfxWw", now: now)
        XCTAssertEqual(estimates.map(\.precision), [60, 86400], "Each estimate is as good as its unit")
        let videos = estimates.map(\.video)
        XCTAssertEqual(videos.map(\.item.contentID), ["aaaaaaaaaaa", "bbbbbbbbbbb"], "Undated and repeated items are left out")
        XCTAssertEqual(videos.first?.item.title, "Newest")
        XCTAssertEqual(videos.first?.item.subtitle, "CNN", "Feed rows name the channel, as the RSS feed does")
        XCTAssertEqual(videos.first?.item.channelID, "UCupvZG-5ko_eiXAupbDfxWw")
        XCTAssertNotNil(videos.first?.item.thumbnail)
        XCTAssertEqual(videos.first?.published, now.addingTimeInterval(-13 * 60))
        XCTAssertEqual(videos.last?.published, now.addingTimeInterval(-2 * 86400))
    }

    func testRememberedDatesPreferExactThenMostPrecise() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file) }
        let dates = FeedDates(file: file)
        // First seen "13 min ago"; an hour later the page says "1h ago", which is coarser, so the first sighting stays.
        let first = await dates.resolve("a", estimate: now.addingTimeInterval(-13 * 60), precision: 60)
        XCTAssertEqual(first.date, now.addingTimeInterval(-13 * 60)); XCTAssertFalse(first.exact)
        let later = await dates.resolve("a", estimate: now.addingTimeInterval(-3600 + 3600), precision: 3600)
        XCTAssertEqual(later.date, now.addingTimeInterval(-13 * 60), "A coarser age doesn't move the date")
        // A finer sighting replaces a coarser one.
        _ = await dates.resolve("b", estimate: now.addingTimeInterval(-86400), precision: 86400)
        let finer = await dates.resolve("b", estimate: now.addingTimeInterval(-20 * 3600), precision: 3600)
        XCTAssertEqual(finer.date, now.addingTimeInterval(-20 * 3600))
        // An exact time from RSS beats any estimate, and survives a restart.
        let exact = now.addingTimeInterval(-777)
        await dates.record(exact: [FeedVideo(item: BrowseItem(contentID: "a", kind: .video, title: "A"), published: exact)])
        let reloaded = await FeedDates(file: file).resolve("a", estimate: now, precision: 1)
        XCTAssertEqual(reloaded.date, exact); XCTAssertTrue(reloaded.exact)
    }

    func testRememberedDatesAreBounded() async {
        let dates = FeedDates(file: nil, limit: 3)
        for index in 0..<5 { _ = await dates.resolve("v\(index)", estimate: now.addingTimeInterval(Double(index)), precision: 60) }
        let oldest = await dates.resolve("v0", estimate: now.addingTimeInterval(-5), precision: 60)
        XCTAssertEqual(oldest.date, now.addingTimeInterval(-5), "The oldest entries are dropped first")
    }

    func testEstimatesKeepTheVideosTabOrder() {
        func video(_ id: String, _ secondsAgo: Double) -> FeedVideo {
            FeedVideo(item: BrowseItem(contentID: id, kind: .video, title: id), published: now.addingTimeInterval(-secondsAgo))
        }
        // "b" was remembered from an earlier "2 min ago"; "c" now reads "1h ago" but is listed below "b".
        let ordered = YouTubeFeedClient.keepingPageOrder([(video("a", 60), false), (video("b", 3 * 3600), true), (video("c", 3600), false)])
        XCTAssertEqual(ordered.map(\.item.contentID), ["a", "b", "c"])
        XCTAssertEqual(ordered[1].published, now.addingTimeInterval(-3 * 3600), "Exact dates are never moved")
        XCTAssertEqual(ordered[2].published, now.addingTimeInterval(-3 * 3600 - 1), "An estimate stays below the upload listed above it")
    }

    func testLiveChannelVideosTab() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["DRIFTLOOM_LIVE"] == nil, "Live YouTube check; set DRIFTLOOM_LIVE=1")
        let videos = try await YouTubeFeedClient(dates: FeedDates(file: nil)).channelPageVideos(channelID: "UCupvZG-5ko_eiXAupbDfxWw")
        XCTAssertGreaterThan(videos.count, 10)
        XCTAssertTrue(videos.allSatisfy { $0.item.subtitle == "CNN" && !$0.item.title.isEmpty })
        XCTAssertLessThan(Date().timeIntervalSince(videos.map(\.published).max()!), 7 * 86400, "CNN uploads daily")
        print("LIVE", videos.prefix(5).map { "\($0.item.contentID) \($0.published) \($0.item.title)" })
        let feed = try await YouTubeFeedClient(dates: FeedDates(file: nil)).videos(channelID: "UCupvZG-5ko_eiXAupbDfxWw")
        XCTAssertGreaterThan(feed.count, 10, "videos(channelID:) works whether or not RSS is up")
    }
}
