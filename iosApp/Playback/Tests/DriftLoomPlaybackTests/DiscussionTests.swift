// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import DriftLoomPlayback

final class DiscussionParserTests: XCTestCase {
    func testEntityCommentsUseThreadOrderAndSeparateReplyContinuations() throws {
        func thread(_ key: String, replies: Bool = false) -> [String: Any] {
            var result: [String: Any] = ["commentViewModel": ["commentViewModel": ["commentKey": key]]]
            if replies { result["replies"] = ["commentRepliesRenderer": ["contents": [["continuationItemRenderer": ["continuationEndpoint": ["continuationCommand": ["token": "replies"]]]]]]] }
            return ["commentThreadRenderer": result]
        }
        let root: [String: Any] = [
            "onResponseReceivedEndpoints": [["appendContinuationItemsAction": ["continuationItems": [thread("b", replies: true), thread("a"), ["continuationItemRenderer": ["continuationEndpoint": ["continuationCommand": ["token": "next"]]]]]]]],
            "frameworkUpdates": ["entityBatchUpdate": ["mutations": ["a", "b"].map { key in
                ["entityKey": key, "payload": ["commentEntityPayload": ["properties": ["commentId": key, "content": ["content": "Text " + key], "publishedTime": "today"], "author": ["displayName": "Author " + key], "toolbar": ["likeCountNotliked": "2"]]]]
            }]]
        ]
        let page = try DiscussionParser.comments(root, version: "current")
        XCTAssertEqual(page.comments.map(\.id), ["b", "a"])
        XCTAssertEqual(page.comments.first?.text, "Text b")
        XCTAssertEqual(page.comments.first?.replies?.token, "replies")
        XCTAssertEqual(page.next?.token, "next")
    }
    func testLegacyRepliesAndUnsupportedResponse() throws {
        let root: [String: Any] = ["onResponseReceivedEndpoints": [["appendContinuationItemsAction": ["continuationItems": [["commentRenderer": ["commentId": "reply", "authorText": ["simpleText": "Author"], "contentText": ["runs": [["text": "hello "], ["text": "world"]]]]]]]]]]
        XCTAssertEqual(try DiscussionParser.comments(root, version: "v").comments.first?.text, "hello world")
        XCTAssertThrowsError(try DiscussionParser.comments([:], version: "v"))
    }
    func testDirectReplyViewModelUsesEntityPayload() throws {
        let root: [String: Any] = [
            "onResponseReceivedEndpoints": [["appendContinuationItemsAction": ["continuationItems": [["commentViewModel": ["commentKey": "r"]]]]]],
            "frameworkUpdates": ["entityBatchUpdate": ["mutations": [["entityKey": "r", "payload": ["commentEntityPayload": ["properties": ["commentId": "reply", "content": ["content": "reply text"]]]]]]]]
        ]
        XCTAssertEqual(try DiscussionParser.comments(root, version: "v").comments.first?.text, "reply text")
    }
    func testUnavailableCommentsDoNotConsumeRelatedContinuation() {
        let details = DiscussionParser.details(["itemSectionRenderer": ["targetId": "related", "contents": [["continuationCommand": ["token": "wrong"]]]]], version: "v")
        XCTAssertNil(details.comments)
    }
}
