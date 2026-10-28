// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import DriftLoomPlayback

final class KioskPagingTests: XCTestCase {
    func testShelfShowMoreLinksAndVisitorIDAreRead() {
        func shelf(_ title: String, _ endpoint: [String: Any]?) -> [String: Any] {
            var renderer: [String: Any] = ["title": ["runs": [["text": title]]], "contents": []]
            if let endpoint { renderer["endpoint"] = ["browseEndpoint": endpoint] }
            return ["richSectionRenderer": ["content": ["richShelfRenderer": renderer]]]
        }
        let root: [String: Any] = [
            "responseContext": ["visitorData": "CgtWaXNpdG9y"],
            "contents": ["twoColumnBrowseResultsRenderer": ["tabs": [["tabRenderer": ["content": ["richGridRenderer": ["contents": [
                shelf("Live Now", ["browseId": "UC4R8DWoMoI7CAwX8_LjQHig", "params": "EgdsaXZldGFikgEDCKEK"]),
                shelf("Upcoming", ["browseId": "UC4R8DWoMoI7CAwX8_LjQHig", "params": "EgdsaXZldGFikgEDCKMK"]),
                shelf("Live now", nil),
                shelf("Live Now", ["browseId": "UC4R8DWoMoI7CAwX8_LjQHig", "params": "EgdsaXZldGFikgEDCKEK"]),
            ]]]]]]]],
        ]
        XCTAssertEqual(BrowseParser.shelfLinks(root), [BrowseShelf(browseID: "UC4R8DWoMoI7CAwX8_LjQHig", params: "EgdsaXZldGFikgEDCKEK"),
                                                      BrowseShelf(browseID: "UC4R8DWoMoI7CAwX8_LjQHig", params: "EgdsaXZldGFikgEDCKMK")],
                       "Shelves without a Show more link are skipped, repeats listed once")
        XCTAssertEqual(BrowseParser.visitorData(root), "CgtWaXNpdG9y")
    }

    @MainActor func testStoreFetchesOnWhenAPageOnlyRepeats() async {
        struct Client: Browsing {
            func page(for route: BrowseRoute) async throws -> BrowsePage {
                BrowsePage(title: "Live", items: ["a", "b"].map(item), next: cursor("1"))
            }
            func nextPage(_ cursor: BrowseCursor) async throws -> BrowsePage {
                cursor.token == "1" ? BrowsePage(title: "", items: ["a", "b"].map(item), next: self.cursor("2"))
                                    : BrowsePage(title: "", items: ["b", "c"].map(item), next: nil)
            }
            func item(_ id: String) -> BrowseItem { BrowseItem(contentID: id, kind: .video, title: id) }
            func cursor(_ token: String) -> BrowseCursor { BrowseCursor(token: token, clientVersion: "2", isSearch: false) }
        }
        let store = BrowseStore(client: Client())
        await store.load(.kiosk(.live))
        await store.loadMore()
        XCTAssertEqual(store.items.map(\.contentID), ["a", "b", "c"], "One Load more fetches on past repeats")
        XCTAssertFalse(store.canLoadMore)
    }

    func testPodcastsLoadInLanguagesYouTubeDoesNotServeThemIn() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["DRIFTLOOM_LIVE"] == nil, "Live YouTube check; set DRIFTLOOM_LIVE=1")
        let defaults = UserDefaults.standard, saved = (defaults.string(forKey: "contentLanguage"), defaults.string(forKey: "contentCountry"))
        defaults.set("uk", forKey: "contentLanguage"); defaults.set("UA", forKey: "contentCountry")
        defer { defaults.set(saved.0, forKey: "contentLanguage"); defaults.set(saved.1, forKey: "contentCountry") }
        let page = try await YouTubeBrowsingClient().page(for: .kiosk(.podcasts))
        XCTAssertGreaterThan(page.items.count, 10)
        XCTAssertNotNil(page.next, "Popular podcasts can still be expanded")
    }

    func testLiveKiosksPageThroughTheirShelves() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["DRIFTLOOM_LIVE"] == nil, "Live YouTube check; set DRIFTLOOM_LIVE=1")
        let client = YouTubeBrowsingClient()
        for (route, minimum) in [(BrowseRoute.kiosk(.live), 150), (.kiosk(.podcasts), 80)] {
            var page = try await client.page(for: route)
            var ids = Set(page.items.map(\.id)); var pages = 1
            while let next = page.next, pages < 15 { page = try await client.nextPage(next); pages += 1; page.items.forEach { ids.insert($0.id) } }
            print("LIVE \(route) pages=\(pages) unique=\(ids.count)")
            XCTAssertGreaterThan(ids.count, minimum, "\(route) offers more than its first page")
        }
    }
}
