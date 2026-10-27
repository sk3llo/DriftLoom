// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import DriftLoomPlayback

@MainActor
final class PinnedHomeTabTests: XCTestCase {
    func testPinsOrderAndRemovalSurviveRelaunch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("tabs.json")
        let tabs = PinnedHomeTabs(fileURL: url)
        let channel = BrowseItem(contentID: "UCUb-HI7Kd-Dr1fBvYjV1IYg", kind: .channel, title: "Channel")
        let playlist = BrowseItem(contentID: "PL-example", kind: .playlist, title: "Playlist")
        tabs.toggle(channel); tabs.toggle(playlist)
        tabs.move(from: IndexSet(integer: 1), to: 0)
        let restored = PinnedHomeTabs(fileURL: url)
        XCTAssertEqual(restored.tabs.map(\.item), [playlist, channel])
        restored.toggle(channel)
        XCTAssertEqual(PinnedHomeTabs(fileURL: url).tabs.map(\.item), [playlist])
    }
    func testInvalidPinsAndCorruptDocumentsDoNotReplaceSavedBytes() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let tabs = PinnedHomeTabs(fileURL: url)
        tabs.toggle(BrowseItem(contentID: "RDexample", kind: .playlist, title: "Invalid Mix"))
        tabs.toggle(BrowseItem(contentID: "11-9ZaYiTPE", kind: .video, title: "Video"))
        XCTAssertTrue(tabs.tabs.isEmpty)
        let bytes = Data("{\"version\":99,\"tabs\":[]}".utf8); try bytes.write(to: url)
        let corrupt = PinnedHomeTabs(fileURL: url)
        XCTAssertFalse(corrupt.isWritable)
        corrupt.toggle(BrowseItem(contentID: "PL-example", kind: .playlist, title: "Playlist"))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
}

final class SuggestionParserTests: XCTestCase {
    func testNestedAndStringResponsesTrimDeduplicateAndIgnoreNonText() throws {
        let data = Data("[\"query\",[[\" first \"],[\"first\"],[\"\"],[12],\"second\"]]".utf8)
        XCTAssertEqual(try SuggestionParser.parse(data), ["first", "second"])
        XCTAssertThrowsError(try SuggestionParser.parse(Data("[\"q\",{}]".utf8)))
    }
}

private actor SuggestionFixture: Suggesting {
    private(set) var calls: [String] = []
    func suggestions(for query: String, locale: ContentLocale) async throws -> [String] {
        calls.append(query)
        if query == "old" { try await Task.sleep(nanoseconds: 500_000_000) }
        return [query + " suggestion"]
    }
}

@MainActor
final class SuggestionStoreTests: XCTestCase {
    func testDisabledShortAndLinkQueriesMakeNoNetworkRequest() async {
        let fixture = SuggestionFixture()
        let checked = SuggestionStore(client: fixture)
        await checked.load(query: "private", locale: ContentLocale(), enabled: false)
        await checked.load(query: "x", locale: ContentLocale())
        await checked.load(query: "https://www.youtube.com/watch?v=11-9ZaYiTPE", locale: ContentLocale())
        let calls = await fixture.calls
        XCTAssertTrue(calls.isEmpty); XCTAssertTrue(checked.suggestions.isEmpty)
    }
    func testLateOlderResponseCannotReplaceTheLatestQuery() async throws {
        let store = SuggestionStore(client: SuggestionFixture())
        let old = Task { await store.load(query: "old", locale: ContentLocale()) }
        try await Task.sleep(nanoseconds: 350_000_000)
        let newer = Task { await store.load(query: "new", locale: ContentLocale()) }
        await newer.value; await old.value
        XCTAssertEqual(store.suggestions, ["new suggestion"])
        store.clear(); XCTAssertTrue(store.suggestions.isEmpty)
    }
    func testSuggestionPreferencePersists() {
        let suite = "DriftLoom.Tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.setUsesSearchSuggestions(false)
        XCTAssertFalse(AppPreferences(defaults: defaults).usesSearchSuggestions)
    }
}

final class ChartsParserTests: XCTestCase {
    func testOfficialChartOrderVisibilityAndDuration() throws {
        let rows: [[String: Any]] = [
            ["id": "11-9ZaYiTPE", "title": "First", "channelName": "Artist", "videoDuration": 155],
            ["id": "dQw4w9WgXcQ", "title": "Hidden", "isAvailable": false],
            ["id": "11-9ZaYiTPE", "title": "Duplicate"],
            ["id": "jNQXAC9IVRw", "title": "Second", "videoDuration": "3601"]
        ]
        let root: [String: Any] = ["contents": ["sectionListRenderer": ["contents": [["musicAnalyticsSectionRenderer": ["content": ["videos": [["videoViews": rows]]]]]]]]]
        let page = try ChartsParser.music(root, country: "PT")
        XCTAssertEqual(page.items.map(\.title), ["First", "Second"])
        XCTAssertEqual(page.items.map(\.duration), ["2:35", "1:00:01"])
        XCTAssertEqual(page.title, "Trending music · PT")
        XCTAssertNil(page.next)
    }
    func testNonChartResponseIsNotMisrepresentedAsTrendingContent() {
        XCTAssertThrowsError(try ChartsParser.music(["items": []], country: "PT"))
    }
}
