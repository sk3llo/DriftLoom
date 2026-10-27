// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import DriftLoomPlayback

final class CommentSortTests: XCTestCase {
    private func page(_ ids: [String], sortMenu: Bool) -> [String: Any] {
        var items: [Any] = ids.map { id in
            ["commentThreadRenderer": ["comment": ["commentRenderer": ["commentId": id, "authorText": ["simpleText": "@a"], "contentText": ["simpleText": id]]]]]
        }
        if sortMenu {
            items.insert(["commentsHeaderRenderer": ["sortMenu": ["sortFilterSubMenuRenderer": ["subMenuItems": [
                ["title": "Top comments", "serviceEndpoint": ["continuationCommand": ["token": "TOP"]]],
                ["title": "Newest first", "serviceEndpoint": ["continuationCommand": ["token": "NEW"]]]
            ]]]]], at: 0)
        }
        items.append(["continuationItemRenderer": ["continuationEndpoint": ["continuationCommand": ["token": "MORE-" + ids[0]]]]])
        return ["onResponseReceivedEndpoints": [["reloadContinuationItemsCommand": ["continuationItems": items]]]]
    }

    func testFirstPageOffersTopAndNewest() throws {
        let first = try DiscussionParser.comments(page(["a", "b"], sortMenu: true), version: "2.0")
        XCTAssertEqual(first.comments.map(\.id), ["a", "b"])
        XCTAssertEqual(first.sorts[.top]?.token, "TOP")
        XCTAssertEqual(first.sorts[.newest]?.token, "NEW")
        XCTAssertEqual(first.next?.token, "MORE-a", "The sort menu isn't taken for the next page")
        XCTAssertTrue(try DiscussionParser.comments(page(["c"], sortMenu: false), version: "2.0").sorts.isEmpty)
    }

    @MainActor
    func testStoreReloadsInTheChosenOrder() async throws {
        struct Client: DiscussionLoading {
            let pages: [String: [String: Any]]
            func details(videoID: String) async throws -> VideoDetails {
                VideoDetails(views: "", date: "", description: "", comments: CommentCursor(token: "FIRST", clientVersion: "2.0"))
            }
            func comments(_ cursor: CommentCursor) async throws -> CommentPage {
                try DiscussionParser.comments(pages[cursor.token]!, version: "2.0")
            }
        }
        let store = DiscussionStore(client: Client(pages: ["FIRST": page(["a", "b"], sortMenu: true), "NEW": page(["z", "y"], sortMenu: true)]))
        await store.load(videoID: "dQw4w9WgXcQ")
        await store.loadMore()
        XCTAssertEqual(store.sortOptions, [.top, .newest])
        XCTAssertEqual(store.comments.map(\.id), ["a", "b"])
        await store.setSort(.newest)
        XCTAssertEqual(store.sort, .newest)
        XCTAssertEqual(store.comments.map(\.id), ["z", "y"], "Newest replaces the list instead of appending")
    }
}
