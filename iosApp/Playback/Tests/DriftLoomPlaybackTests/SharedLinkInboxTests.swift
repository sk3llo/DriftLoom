// SPDX-License-Identifier: GPL-3.0-or-later
import DriftLoomActivity
import XCTest

final class SharedLinkInboxTests: XCTestCase {
    private func directory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func testSharingAcrossInstancesKeepsAllLinksUntilExplicitlyRemoved() throws {
        let root = directory(), writer = SharedLinkInbox(directory: root)
        let first = try writer.save(URL(string: "https://youtu.be/dQw4w9WgXcQ")!)
        let second = try writer.save(URL(string: "https://soundcloud.com/lofi_girl")!)
        let reader = SharedLinkInbox(directory: root)
        XCTAssertEqual(try reader.next(), first)
        XCTAssertEqual(try reader.next(), first, "Later or restarting must not consume the link")
        try reader.remove(first)
        XCTAssertEqual(try reader.next(), second, "Saving another link must not overwrite the first")
        try reader.remove(second)
        XCTAssertNil(try reader.next())
    }
    func testRejectsUnsupportedAndOversizedLinksWithoutCreatingInbox() throws {
        let root = directory(), inbox = SharedLinkInbox(directory: root)
        XCTAssertThrowsError(try inbox.save(URL(string: "https://youtube.com.evil.test/watch")!))
        XCTAssertThrowsError(try inbox.save(URL(string: "https://youtu.be/" + String(repeating: "a", count: 4096))!))
        XCTAssertNil(try inbox.next())
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }
    func testMalformedAndMismatchedFilesDoNotBlockValidLinks() throws {
        let root = directory(), inbox = SharedLinkInbox(directory: root)
        let entry = try inbox.save(URL(string: "https://youtu.be/dQw4w9WgXcQ")!)
        try Data("invalid".utf8).write(to: root.appendingPathComponent(UUID().uuidString + ".json"))
        try Data(repeating: 0, count: 16_385).write(to: root.appendingPathComponent(UUID().uuidString + ".json"))
        let validFile = root.appendingPathComponent(entry.id.uuidString + ".json")
        try FileManager.default.copyItem(at: validFile, to: root.appendingPathComponent(UUID().uuidString + ".json"))
        XCTAssertEqual(try inbox.next(), entry)
        try inbox.remove(entry)
        XCTAssertNil(try inbox.next(), "A renamed record must not be replayed")
    }
}
