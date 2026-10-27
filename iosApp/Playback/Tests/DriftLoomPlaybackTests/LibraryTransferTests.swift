// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import DriftLoomPlayback

@MainActor
final class LibraryTransferTests: XCTestCase {
    private func stores(_ directory: URL) -> (LibraryStore, PlaylistStore) {
        (LibraryStore(fileURL: directory.appendingPathComponent("library.json")), PlaylistStore(fileURL: directory.appendingPathComponent("playlists.json")))
    }
    func testBackupRoundTripMergesWithoutOverwritingPrivacyOrDuplicates() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let (source, sourcePlaylists) = stores(root.appendingPathComponent("source"))
        let video = BrowseItem(contentID: "11-9ZaYiTPE", kind: .video, title: "Saved")
        source.toggleSaved(video); source.recordPlayback(video)
        _ = sourcePlaylists.create(name: "List", item: video)
        let backup = try LibraryTransfer.export(library: source, playlists: sourcePlaylists)
        let plan = try LibraryTransfer.preview(backup)
        let destination = root.appendingPathComponent("destination")
        let (library, playlists) = stores(destination)
        library.setHistoryEnabled(false)
        try LibraryTransfer.apply(plan, library: library, playlists: playlists)
        try LibraryTransfer.apply(plan, library: library, playlists: playlists)
        XCTAssertEqual(library.saved.count, 1); XCTAssertEqual(library.history.count, 1)
        XCTAssertFalse(library.historyEnabled)
        XCTAssertEqual(playlists.playlists.count, 1); XCTAssertEqual(playlists.playlists.first?.entries.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("transfer-recovery.json").path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.appendingPathComponent("PreImportBackups").path).count, 2)
    }
    func testNewPipeSubscriptionJSONOnlyImportsValidSupportedChannels() throws {
        let data = Data("""
        {"app_version":"0.29.1","subscriptions":[
        {"service_id":0,"url":"https://www.youtube.com/channel/UCUb-HI7Kd-Dr1fBvYjV1IYg","name":"Channel"},
        {"service_id":1,"url":"https://soundcloud.com/name","name":"Unsupported"},
        {"service_id":0,"url":"https://evil.example/channel/UCUb-HI7Kd-Dr1fBvYjV1IYg","name":"Wrong host"}]}
        """.utf8)
        let plan = try LibraryTransfer.preview(data)
        XCTAssertEqual(plan.warnings.count, 1)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let (library, playlists) = stores(directory)
        try LibraryTransfer.apply(plan, library: library, playlists: playlists)
        XCTAssertEqual(library.subscriptions.map { $0.item.title }, ["Channel"])
        XCTAssertThrowsError(try LibraryTransfer.preview(Data("{\"format\":\"other\",\"version\":99}".utf8)))
    }
    func testSecondFileWriteFailureRollsBackBothFilesAndKeepsRecoveryCopy() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let oldLibrary = Data("old library".utf8), oldPlaylists = Data("old playlists".utf8)
        try oldLibrary.write(to: directory.appendingPathComponent("library.json"))
        try oldPlaylists.write(to: directory.appendingPathComponent("playlists.json"))
        XCTAssertThrowsError(try LibraryTransfer.transaction(directory: directory, library: Data("new".utf8), playlists: Data("new".utf8)) { data, url in
            if url.lastPathComponent == "playlists.json" { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: .atomic)
        })
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("library.json")), oldLibrary)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("playlists.json")), oldPlaylists)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("PreImportBackups").path).count, 1)
    }
    func testRecoveryRestoresInterruptedImportBeforeStoresOpen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = Data("preserve".utf8)
        let journal: [String: Any] = ["version": 1, "library": old.base64EncodedString()]
        try JSONSerialization.data(withJSONObject: journal).write(to: directory.appendingPathComponent("transfer-recovery.json"))
        try Data("partially imported".utf8).write(to: directory.appendingPathComponent("library.json"))
        try Data("new playlist".utf8).write(to: directory.appendingPathComponent("playlists.json"))
        try LibraryTransfer.recover(directory: directory)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("library.json")), old)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("playlists.json").path))
    }
}
