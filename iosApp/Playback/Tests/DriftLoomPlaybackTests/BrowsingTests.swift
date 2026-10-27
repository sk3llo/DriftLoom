// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import DriftLoomPlayback

private let firstID = "11-9ZaYiTPE"
private let secondID = "QdBZY2fkU-0"
private let channelID = "UCabcdefghijklmnopqrstuv"
private let cursor = BrowseCursor(token: "next", clientVersion: "2.test", isSearch: true)
private func video(_ id: String) -> BrowseItem { BrowseItem(contentID: id, kind: .video, title: id) }
private func makePage(_ ids: [String], next: BrowseCursor? = nil, title: String = "Results") -> BrowsePage {
    BrowsePage(title: title, items: ids.map(video), next: next)
}
private func renderer(_ id: String) -> [String: Any] {
    ["videoRenderer": ["videoId": id, "title": ["runs": [["text": "A video"]]],
                       "lengthText": ["simpleText": "2:36"],
                       "ownerText": ["runs": [["text": "An artist", "navigationEndpoint": ["browseEndpoint": ["browseId": channelID]]]]],
                       "thumbnail": ["thumbnails": [["url": "https://i.ytimg.com/test.jpg"]]]]]
}
private func searchRoot(_ rows: [[String: Any]]) -> [String: Any] {
    ["contents": ["twoColumnSearchResultsRenderer": ["primaryContents": ["sectionListRenderer": ["contents": rows]]]]]
}

final class BrowseParserTests: XCTestCase {
    func testEmbeddedJSONHandlesQuotedBracesAndEscapes() throws {
        let title = "A {brace} and a \\ and a \"quote\""
        let object: [String: Any] = ["title": title, "nested": ["valid": true]]
        let json = String(data: try JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
        let html = "<script>var ytInitialData = \(json); window.extra = {broken};</script>"
        XCTAssertEqual(try BrowseParser.initialData(in: html)["title"] as? String, title)
        XCTAssertThrowsError(try BrowseParser.initialData(in: "var ytInitialData = {\"unfinished\":"))
    }

    func testModernAndLegacyRowsPreserveOrderAndIgnoreMenusAndAds() throws {
        let playlist: [String: Any] = ["lockupViewModel": [
            "contentId": "PLabcdefghijk", "contentType": "LOCKUP_CONTENT_TYPE_PLAYLIST",
            "metadata": ["lockupMetadataViewModel": ["title": ["content": "A playlist"]]]]]
        let channel: [String: Any] = ["channelRenderer": ["channelId": channelID, "title": ["simpleText": "Artist"]]]
        let rows: [[String: Any]] = [renderer(firstID), ["menu": renderer(secondID)],
                                    ["adSlotRenderer": renderer(secondID)], playlist, channel, renderer(firstID)]
        let result = try BrowseParser.page(searchRoot(rows), fallbackTitle: "Search", clientVersion: "2.test", isSearch: true)
        XCTAssertEqual(result.items.map(\.kind), [.video, .playlist, .channel])
        XCTAssertEqual(result.items.first?.channelID, channelID)
        XCTAssertEqual(result.items.first?.duration, "2:36")
        XCTAssertNil(result.items[1].duration)
    }

    func testSelectedChannelTabExcludesOtherTabs() throws {
        let root: [String: Any] = ["metadata": ["channelMetadataRenderer": ["title": "Artist"]],
            "contents": ["twoColumnBrowseResultsRenderer": ["tabs": [
                ["tabRenderer": ["selected": false, "content": renderer(firstID)]],
                ["tabRenderer": ["selected": true, "content": renderer(secondID)]]]]]]
        let result = try BrowseParser.page(root, fallbackTitle: "Channel", clientVersion: nil, isSearch: false)
        XCTAssertEqual(result.title, "Artist")
        XCTAssertEqual(result.items.map(\.contentID), [secondID])
    }

    func testContinuationUsesCorrectEndpointAndModernVideoModel() throws {
        let root: [String: Any] = ["onResponseReceivedActions": [["appendContinuationItemsAction": ["continuationItems": [
            ["lockupViewModel": ["contentId": firstID, "contentType": "LOCKUP_CONTENT_TYPE_VIDEO",
                "metadata": ["lockupMetadataViewModel": ["title": ["content": "New format"]]]]],
            ["continuationItemRenderer": ["continuationEndpoint": ["continuationCommand": ["token": "opaque"]]]]
        ]]]]]
        let result = try BrowseParser.page(root, fallbackTitle: "", clientVersion: "2.test", isSearch: false)
        XCTAssertEqual(result.items.first?.title, "New format")
        XCTAssertEqual(result.next?.token, "opaque")
        XCTAssertEqual(result.next?.isSearch, false)
    }

    func testUnavailableAndUnknownPagesAreErrorsAndEmptySearchIsValid() throws {
        XCTAssertThrowsError(try BrowseParser.page(["alerts": [["alertRenderer": ["type": "ERROR", "text": ["simpleText": "Private"]]]]],
                                                  fallbackTitle: "", clientVersion: nil, isSearch: false))
        XCTAssertThrowsError(try BrowseParser.page(["contents": ["unknown": [:]]], fallbackTitle: "", clientVersion: nil, isSearch: true))
        XCTAssertTrue(try BrowseParser.page(searchRoot([]), fallbackTitle: "Empty", clientVersion: nil, isSearch: true).items.isEmpty)
    }

    func testShortsUseTapTargetAndNotMenuVideoIDs() throws {
        let row: [String: Any] = ["shortsLockupViewModel": [
            "onTap": ["innertubeCommand": ["reelWatchEndpoint": ["videoId": firstID]]],
            "menuOnTap": ["videoId": secondID],
            "overlayMetadata": ["primaryText": ["content": "A short"], "secondaryText": ["content": "10 views"]]]]
        let result = try BrowseParser.page(searchRoot([row]), fallbackTitle: "", clientVersion: nil, isSearch: true)
        XCTAssertEqual(result.items.first?.contentID, firstID)
        XCTAssertEqual(result.items.first?.duration, "Short")
    }

    func testRelatedContinuationKeepsNextEndpoint() throws {
        let root: [String: Any] = ["contents": ["twoColumnWatchNextResults": ["secondaryResults": ["secondaryResults": ["results": [
            renderer(firstID),
            ["continuationItemRenderer": ["continuationEndpoint": ["continuationCommand": ["token": "related-next"]]]]
        ]]]]]]
        let result = try BrowseParser.page(root, fallbackTitle: "Related", clientVersion: "2.test", isSearch: false, isRelated: true)
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.next?.isRelated, true)
    }

    func testMixContentsExcludeUnrelatedSidebarVideos() throws {
        let root: [String: Any] = ["contents": ["twoColumnWatchNextResults": [
            "playlist": ["playlist": ["contents": [["playlistPanelVideoRenderer": ["videoId": firstID, "title": ["simpleText": "Mix track"]]]]]],
            "secondaryResults": ["secondaryResults": ["results": [renderer(secondID)]]]
        ]]]
        let result = try BrowseParser.page(root, fallbackTitle: "Mix", clientVersion: "2.test", isSearch: false, isMix: true)
        XCTAssertEqual(result.items.map(\.contentID), [firstID])
        let mix: [String: Any] = ["lockupViewModel": [
            "contentId": "RD\(firstID)", "contentType": "LOCKUP_CONTENT_TYPE_PLAYLIST",
            "rendererContext": ["commandContext": ["onTap": ["innertubeCommand": ["watchEndpoint": ["videoId": firstID]]]]],
            "metadata": ["lockupMetadataViewModel": ["title": ["content": "Mix"]]]]]
        let search = try BrowseParser.page(searchRoot([mix]), fallbackTitle: "", clientVersion: nil, isSearch: true)
        XCTAssertEqual(search.items.first?.destination, .mix(playlist: "RD\(firstID)", seed: firstID))
    }

    func testUnplayablePlaylistEntriesAreSkipped() throws {
        let row: [String: Any] = ["playlistVideoRenderer": ["videoId": firstID, "isPlayable": false, "title": ["simpleText": "Private video"]]]
        let result = try BrowseParser.page(searchRoot([row]), fallbackTitle: "", clientVersion: nil, isSearch: false)
        XCTAssertTrue(result.items.isEmpty)
    }

    func testClientVersionIsReadFromPageInsteadOfHardCoded() {
        XCTAssertEqual(BrowseParser.clientVersion(in: "ytcfg.set({\"INNERTUBE_CLIENT_VERSION\": \"2.20261023.01.00\"});"), "2.20261023.01.00")
        XCTAssertNil(BrowseParser.clientVersion(in: "changed response"))
    }
}

private actor PaginatedBrowsing: Browsing {
    var failsOnce: Bool
    init(failsOnce: Bool = false) { self.failsOnce = failsOnce }
    func page(for route: BrowseRoute) async throws -> BrowsePage { makePage([firstID], next: cursor) }
    func nextPage(_ value: BrowseCursor) async throws -> BrowsePage {
        if failsOnce { failsOnce = false; throw BrowseError.unavailable("Temporary error") }
        return makePage([firstID, secondID], next: cursor)
    }
}

private actor BlockingBrowsing: Browsing {
    private var pending: [BrowseRoute: CheckedContinuation<BrowsePage, Error>] = [:]
    private var waiting: [BrowseRoute: CheckedContinuation<Void, Never>] = [:]
    func page(for route: BrowseRoute) async throws -> BrowsePage {
        try await withCheckedThrowingContinuation {
            pending[route] = $0
            waiting.removeValue(forKey: route)?.resume()
        }
    }
    func nextPage(_ cursor: BrowseCursor) async throws -> BrowsePage { makePage([]) }
    func waitFor(_ route: BrowseRoute) async {
        if pending[route] != nil { return }
        await withCheckedContinuation { waiting[route] = $0 }
    }
    func finish(_ route: BrowseRoute, result: BrowsePage) { pending.removeValue(forKey: route)?.resume(returning: result) }
}

@MainActor
final class BrowseStoreTests: XCTestCase {
    func testPaginationDeduplicatesAndStopsRepeatedCursor() async {
        let store = BrowseStore(client: PaginatedBrowsing())
        await store.load(.search("music"))
        XCTAssertTrue(store.canLoadMore)
        await store.loadMore()
        XCTAssertEqual(store.items.map(\.contentID), [firstID, secondID])
        XCTAssertFalse(store.canLoadMore)
    }

    func testPaginationFailurePreservesResultsAndCanRetry() async {
        let store = BrowseStore(client: PaginatedBrowsing(failsOnce: true))
        await store.load(.search("music"))
        await store.loadMore()
        XCTAssertEqual(store.items.count, 1)
        XCTAssertNotNil(store.paginationError)
        XCTAssertTrue(store.canLoadMore)
        await store.loadMore()
        XCTAssertEqual(store.items.count, 2)
        XCTAssertNil(store.paginationError)
    }

    func testLateSearchCannotOverwriteNewResults() async {
        let client = BlockingBrowsing()
        let store = BrowseStore(client: client)
        let old = Task { await store.load(.search("old")) }
        await client.waitFor(.search("old"))
        let new = Task { await store.load(.search("new")) }
        await client.waitFor(.search("new"))
        await client.finish(.search("new"), result: makePage([secondID], title: "New"))
        await new.value
        await client.finish(.search("old"), result: makePage([firstID], title: "Old"))
        await old.value
        XCTAssertEqual(store.title, "New")
        XCTAssertEqual(store.items.map(\.contentID), [secondID])
    }

    func testInvalidRoutesFailBeforeNetworkAccess() async {
        let client = YouTubeBrowsingClient()
        for route in [BrowseRoute.search("  "), .channel("../../evil"), .playlist("x&list=y")] {
            do { _ = try await client.page(for: route); XCTFail("Invalid route accepted") }
            catch { XCTAssertTrue(error is BrowseError) }
        }
    }
}


private actor DelayedPagination: Browsing {
    private var pending: CheckedContinuation<BrowsePage, Error>?
    private var started: CheckedContinuation<Void, Never>?
    func page(for route: BrowseRoute) async throws -> BrowsePage {
        if route == .search("new") { return makePage([secondID], title: "New") }
        return makePage([firstID], next: cursor)
    }
    func nextPage(_ cursor: BrowseCursor) async throws -> BrowsePage {
        try await withCheckedThrowingContinuation {
            pending = $0
            started?.resume(); started = nil
        }
    }
    func waitForPagination() async {
        if pending != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func finish() { pending?.resume(returning: makePage([firstID])); pending = nil }
}

extension BrowseStoreTests {
    func testLatePaginationCannotAppendToNewSearch() async {
        let client = DelayedPagination()
        let store = BrowseStore(client: client)
        await store.load(.search("old"))
        let oldPage = Task { await store.loadMore() }
        await client.waitForPagination()
        await store.load(.search("new"))
        await client.finish()
        await oldPage.value
        XCTAssertEqual(store.items.map(\.contentID), [secondID])
        XCTAssertFalse(store.isLoadingMore)
    }
}
