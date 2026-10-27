// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import DriftLoomPlayback

final class SharedLinkTests: XCTestCase {
    func testFindsTheFirstSupportedLinkInSharedText() {
        XCTAssertEqual(SharedLink.firstSupportedURL(in: "Look https://example.com/x then https://youtu.be/dQw4w9WgXcQ?si=abc 🎶")?.absoluteString,
                       "https://youtu.be/dQw4w9WgXcQ?si=abc")
        XCTAssertEqual(SharedLink.firstSupportedURL(in: "on.soundcloud.com/AbC123")?.host, "on.soundcloud.com")
        XCTAssertNil(SharedLink.firstSupportedURL(in: "nothing here https://youtube.com.evil.test/watch?v=dQw4w9WgXcQ"))
        XCTAssertNil(SharedLink.firstSupportedURL(in: String(repeating: "a", count: 20_001)))
    }
    func testOnlyYouTubeAndSoundCloudAreSupported() {
        for good in ["https://www.youtube.com/watch?v=dQw4w9WgXcQ", "https://music.youtube.com/watch?v=dQw4w9WgXcQ", "https://youtu.be/x",
                     "https://soundcloud.com/a/b", "https://m.soundcloud.com/a", "http://youtube.com/@name"] {
            XCTAssertTrue(SharedLink.isSupported(URL(string: good)!), good)
        }
        for bad in ["https://evilyoutube.com/watch", "https://youtube.com@evil.test/", "ftp://youtube.com/x", "driftloom://open", "https://soundcloud.com.evil.test/a"] {
            XCTAssertFalse(SharedLink.isSupported(URL(string: bad)!), bad)
        }
    }
    func testAppURLsRoundTripAndRejectOtherLinks() throws {
        let link = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PL1&t=42")!
        let app = try XCTUnwrap(SharedLink.appURL(for: link))
        XCTAssertEqual(app.scheme, "driftloom"); XCTAssertEqual(app.host, "open")
        XCTAssertEqual(SharedLink.target(of: app), link, "Query characters in the link survive")
        XCTAssertEqual(SharedLink.target(of: link), link)
        XCTAssertNil(SharedLink.appURL(for: URL(string: "https://example.com")!))
        XCTAssertNil(SharedLink.target(of: URL(string: "driftloom://open?url=https%3A%2F%2Fexample.com")!))
        XCTAssertNil(SharedLink.target(of: URL(string: "driftloom://delete?url=https%3A%2F%2Fyoutu.be%2Fx")!))
    }
    func testLinksResolveToVideosPlaylistsAndChannelsWithoutNetwork() {
        func target(_ text: String) -> LinkTarget? { LinkResolver.immediate(URL(string: text)!) }
        XCTAssertEqual(target("https://youtu.be/dQw4w9WgXcQ?si=x"), .play(BrowseItem(contentID: "dQw4w9WgXcQ", kind: .video, title: "YouTube video")))
        XCTAssertEqual(target("https://youtube.com/shorts/dQw4w9WgXcQ?si=x"), .play(BrowseItem(contentID: "dQw4w9WgXcQ", kind: .video, title: "YouTube video")))
        XCTAssertEqual(target("https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PLx"), .play(BrowseItem(contentID: "dQw4w9WgXcQ", kind: .video, title: "YouTube video")))
        XCTAssertEqual(target("https://youtube.com/playlist?list=PLabc_123&si=x"), .browse(.playlist("PLabc_123")))
        XCTAssertEqual(target("https://www.youtube.com/channel/UCUb-HI7Kd-Dr1fBvYjV1IYg/videos"), .browse(.channel("UCUb-HI7Kd-Dr1fBvYjV1IYg")))
        XCTAssertNil(target("https://www.youtube.com/@someone"), "Handles need a lookup")
        XCTAssertNil(target("https://www.youtube.com/playlist?list=RDdQw4w9WgXcQ"), "Mixes need a seed video")
        XCTAssertNil(target("https://soundcloud.com/a/b"), "SoundCloud permalinks need a lookup")
    }
    func testChannelPagesNameTheirChannelInTheCanonicalLink() {
        XCTAssertEqual(LinkResolver.channelID(in: #"<link rel="canonical" href="https://www.youtube.com/channel/UCUb-HI7Kd-Dr1fBvYjV1IYg">"#), "UCUb-HI7Kd-Dr1fBvYjV1IYg")
        XCTAssertNil(LinkResolver.channelID(in: #"<link rel="canonical" href="https://evil.test/channel/UCUb-HI7Kd-Dr1fBvYjV1IYg">"#))
    }
}
