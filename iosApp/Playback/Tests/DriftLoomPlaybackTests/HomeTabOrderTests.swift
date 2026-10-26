// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import DriftLoomPlayback

@MainActor
final class HomeTabOrderTests: XCTestCase {
    private var file: URL!
    override func setUp() async throws {
        file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("home-tabs.json")
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    private let channel = BrowseItem(contentID: "UC" + String(repeating: "a", count: 22), kind: .channel, title: "Channel")

    func testKeysRoundTripAndRejectMalformedValues() {
        let id = UUID()
        for key in [HomeTabKey.section(.feed), .pinned("channel:x"), .local(id)] { XCTAssertEqual(HomeTabKey(rawValue: key.rawValue), key) }
        for raw in ["", "section:Nope", "local:not-a-uuid", "pinned:", "other:x", "nocolon"] { XCTAssertNil(HomeTabKey(rawValue: raw), raw) }
    }
    func testDefaultArrangementGroupsAndSavedOrderInterleaves() throws {
        let tabs = PinnedHomeTabs(fileURL: file)
        let playlist = UUID()
        tabs.toggle(channel); tabs.toggleLocal(playlist)
        let pinned = try XCTUnwrap(tabs.tabs.first).id
        XCTAssertEqual(tabs.arrangement(sections: [.subscriptions, .feed], localPlaylistIDs: [playlist]),
                       [.section(.subscriptions), .section(.feed), .pinned(pinned), .local(playlist)])
        tabs.setOrder([.local(playlist), .section(.feed), .pinned(pinned), .section(.subscriptions)])
        let reloaded = PinnedHomeTabs(fileURL: file)
        XCTAssertEqual(reloaded.arrangement(sections: [.subscriptions, .feed], localPlaylistIDs: [playlist]),
                       [.local(playlist), .section(.feed), .pinned(pinned), .section(.subscriptions)])
        // Hidden sections and deleted playlists drop out; newly shown sections are appended.
        XCTAssertEqual(reloaded.arrangement(sections: [.feed, .history], localPlaylistIDs: []),
                       [.section(.feed), .pinned(pinned), .section(.history)])
    }
    func testOnlyPinnedTabsStillWriteVersionOneForEarlierBuilds() throws {
        let tabs = PinnedHomeTabs(fileURL: file)
        tabs.toggle(channel)
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        XCTAssertEqual(json["version"] as? Int, 1); XCTAssertNil(json["order"])
        let playlist = UUID()
        tabs.toggleLocal(playlist)
        json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        XCTAssertEqual(json["version"] as? Int, 2)
        tabs.removeLocal(playlist)
        json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        XCTAssertEqual(json["version"] as? Int, 1)
    }
    func testRemovingTabsAndDeletedPlaylistsCleansSavedOrder() throws {
        let tabs = PinnedHomeTabs(fileURL: file)
        let kept = UUID(), deleted = UUID()
        tabs.toggle(channel); tabs.toggleLocal(kept); tabs.toggleLocal(deleted)
        let pinned = try XCTUnwrap(tabs.tabs.first).id
        tabs.setOrder([.local(deleted), .pinned(pinned), .local(kept), .section(.feed)])
        tabs.retainLocal([kept])
        XCTAssertEqual(tabs.localPlaylists, [kept]); XCTAssertEqual(tabs.order, [.pinned(pinned), .local(kept), .section(.feed)])
        tabs.remove(pinned)
        XCTAssertEqual(tabs.order, [.local(kept), .section(.feed)])
        tabs.toggleLocal(kept)
        XCTAssertFalse(tabs.containsLocal(kept)); XCTAssertEqual(tabs.order, [.section(.feed)])
    }
    func testInvalidOrNewerDocumentsStayUntouched() throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        for body in [#"{"version":3,"tabs":[]}"#, #"{"version":1,"tabs":[],"order":["section:Trending music"]}"#,
                     #"{"version":2,"tabs":[],"order":["section:History","section:History"]}"#, #"{"version":2,"tabs":[],"order":["bogus"]}"#] {
            try Data(body.utf8).write(to: file)
            let tabs = PinnedHomeTabs(fileURL: file)
            XCTAssertFalse(tabs.isWritable, body)
            tabs.toggleLocal(UUID())
            XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), body)
        }
    }
}
