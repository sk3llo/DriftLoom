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
    func testYouTubeMusicChartsPickTheTrendingPlaylist() {
        func shelf(_ ids: [String]) -> [String: Any] {
            ["musicCarouselShelfRenderer": ["contents": ids.map { ["musicTwoRowItemRenderer": ["navigationEndpoint": ["browseEndpoint": ["browseId": $0]]]] }]]
        }
        func root(_ sections: [[String: Any]]) -> [String: Any] {
            ["contents": ["singleColumnBrowseResultsRenderer": ["tabs": [["tabRenderer": ["content": ["sectionListRenderer": ["contents": sections]]]]]]]]
        }
        let charts = root([["musicShelfRenderer": [:]], shelf(["VLPL4fGSI1pDJn4yCNzulPkUbxgr4pl0gmI-", "VLOLAK5uy_kNWGJvgWVqlt5LsFDL9Sdluly4M8TvGkM"]),
                           shelf(["VLOLAK5uy_second00000000000000000000000000"])])
        XCTAssertEqual(ChartsParser.trendingPlaylist(charts), "OLAK5uy_kNWGJvgWVqlt5LsFDL9Sdluly4M8TvGkM")
        XCTAssertNil(ChartsParser.trendingPlaylist(root([shelf(["VLPL4fGSI1pDJn4yCNzulPkUbxgr4pl0gmI-", "VLOLAK5uy_bad&id"])])))
        XCTAssertNil(ChartsParser.trendingPlaylist(["error": "x"]))
    }
}
