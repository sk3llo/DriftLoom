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
        let videos = try YouTubeFeedClient.uploads(fromChannelPage: html, channelID: "UCupvZG-5ko_eiXAupbDfxWw", now: now)
        XCTAssertEqual(videos.map(\.item.contentID), ["aaaaaaaaaaa", "bbbbbbbbbbb"], "Undated and repeated items are left out")
        XCTAssertEqual(videos.first?.item.title, "Newest")
        XCTAssertEqual(videos.first?.item.subtitle, "CNN", "Feed rows name the channel, as the RSS feed does")
        XCTAssertEqual(videos.first?.item.channelID, "UCupvZG-5ko_eiXAupbDfxWw")
        XCTAssertNotNil(videos.first?.item.thumbnail)
        XCTAssertEqual(videos.first?.published, now.addingTimeInterval(-13 * 60))
        XCTAssertEqual(videos.last?.published, now.addingTimeInterval(-2 * 86400))
    }

    func testLiveChannelVideosTab() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["DRIFTLOOM_LIVE"] == nil, "Live YouTube check; set DRIFTLOOM_LIVE=1")
        let videos = try await YouTubeFeedClient().channelPageVideos(channelID: "UCupvZG-5ko_eiXAupbDfxWw")
        XCTAssertGreaterThan(videos.count, 10)
        XCTAssertTrue(videos.allSatisfy { $0.item.subtitle == "CNN" && !$0.item.title.isEmpty })
        XCTAssertLessThan(Date().timeIntervalSince(videos.map(\.published).max()!), 7 * 86400, "CNN uploads daily")
        print("LIVE", videos.prefix(5).map { "\($0.item.contentID) \($0.published) \($0.item.title)" })
        let feed = try await YouTubeFeedClient().videos(channelID: "UCupvZG-5ko_eiXAupbDfxWw")
        XCTAssertGreaterThan(feed.count, 10, "videos(channelID:) works whether or not RSS is up")
    }
}
