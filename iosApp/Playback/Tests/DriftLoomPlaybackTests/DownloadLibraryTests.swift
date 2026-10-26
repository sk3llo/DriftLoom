// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import DriftLoomPlayback

@MainActor
final class DownloadLibraryTests: XCTestCase {
    func testRelativePathNormalizesSymlinkAliasesAndRejectsEscape() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: home)
        let file = home.appendingPathComponent("asset.movpkg")
        try Data().write(to: file)
        XCTAssertEqual(DownloadPaths.relativePath(for: file, home: alias), "asset.movpkg")
        XCTAssertEqual(DownloadPaths.relativePath(for: alias.appendingPathComponent("asset.movpkg"), home: home), "asset.movpkg")
        XCTAssertNil(DownloadPaths.relativePath(for: root.appendingPathComponent("outside"), home: home))
        XCTAssertNil(DownloadPaths.relativePath(for: URL(string: "https://example.com/media")!, home: home))
    }
    func testJobLifecyclePersistsWithoutSignedURLs() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("downloads.json")
        let store = DownloadLibrary(fileURL: url)
        let item = BrowseItem(contentID: "11-9ZaYiTPE", kind: .video, title: "Video")
        var job = DownloadRecord(item: item, choice: DownloadChoice(id: "hls", name: "Video", kind: .hls))
        XCTAssertTrue(store.add(job))
        job.transferID = UUID(); job.state = .downloading; job.progress = 0.5
        XCTAssertTrue(store.update(job))
        XCTAssertEqual(DownloadLibrary(fileURL: url).records.first, job)
        job.state = .completed; job.progress = 1; job.localPath = "Library/Media/asset.movpkg"
        XCTAssertTrue(store.update(job))
        let restored = DownloadLibrary(fileURL: url)
        XCTAssertEqual(restored.records.first?.localPath, job.localPath)
        XCTAssertFalse(String(decoding: try Data(contentsOf: url), as: UTF8.self).contains("googlevideo.com"))
        XCTAssertTrue(restored.remove(job.id)); XCTAssertTrue(DownloadLibrary(fileURL: url).records.isEmpty)
    }
    func testInvalidPathsAndProgressAreRejected() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = DownloadLibrary(fileURL: url)
        var job = DownloadRecord(item: BrowseItem(contentID: "11-9ZaYiTPE", kind: .video, title: "Video"), choice: DownloadChoice(id: "hls", name: "Video", kind: .hls))
        job.localPath = "../other-file"; XCTAssertFalse(store.add(job))
        job.localPath = "/tmp/other-file"; XCTAssertFalse(store.add(job))
        job.localPath = nil; job.progress = .infinity; XCTAssertFalse(store.add(job))
    }
    func testUnsupportedDocumentAndFailedWritePreserveData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("downloads.json")
        let bytes = Data("{\"version\":99,\"records\":[]}".utf8); try bytes.write(to: url)
        let store = DownloadLibrary(fileURL: url)
        XCTAssertFalse(store.isWritable)
        XCTAssertFalse(store.remove(UUID()))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        let blocked = DownloadLibrary(fileURL: directory)
        XCTAssertFalse(blocked.isWritable)
    }
}
