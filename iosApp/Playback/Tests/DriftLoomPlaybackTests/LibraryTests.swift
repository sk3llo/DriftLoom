// SPDX-License-Identifier: GPL-3.0-or-later
import AVFoundation
import Combine
import XCTest
@testable import DriftLoomPlayback

@MainActor
final class LibraryTests: XCTestCase {
    private func location() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("library.json")
    }
    private let video = BrowseItem(contentID: "11-9ZaYiTPE", kind: .video, title: "A discovery", subtitle: "Channel", channelID: "UCUb-HI7Kd-Dr1fBvYjV1IYg")
    private let channel = BrowseItem(contentID: "UCUb-HI7Kd-Dr1fBvYjV1IYg", kind: .channel, title: "Channel")

    func testRoundTripAndRemoval() throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = LibraryStore(fileURL: url)
        XCTAssertTrue(store.toggleSaved(video))
        XCTAssertTrue(store.toggleSubscription(channel))
        XCTAssertTrue(store.recordPlayback(video))
        let loaded = LibraryStore(fileURL: url)
        XCTAssertEqual(loaded.saved.first?.item, video)
        XCTAssertEqual(loaded.subscriptions.first?.item, channel)
        XCTAssertEqual(loaded.history.first?.item, video)
        loaded.removeSaved(video.contentID)
        loaded.unsubscribe(channel.contentID)
        loaded.removeHistory(video.contentID)
        let empty = LibraryStore(fileURL: url)
        XCTAssertTrue(empty.saved.isEmpty && empty.subscriptions.isEmpty && empty.history.isEmpty)
    }

    func testHistoryDeduplicatesCapsAndPersistsPreference() throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var document = LibraryDocument()
        document.history = (0..<500).map { index in
            LibraryRecord(item: BrowseItem(contentID: String(format: "%011d", index), kind: .video, title: "Video"), date: Date())
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(document).write(to: url)
        let store = LibraryStore(fileURL: url)
        XCTAssertTrue(store.recordPlayback(video, date: Date(timeIntervalSince1970: 1)))
        XCTAssertEqual(store.history.count, 500)
        XCTAssertTrue(store.recordPlayback(video, date: Date(timeIntervalSince1970: 2)))
        XCTAssertEqual(store.history.count, 500)
        XCTAssertEqual(store.history.first?.date, Date(timeIntervalSince1970: 2))
        store.setHistoryEnabled(false)
        let loaded = LibraryStore(fileURL: url)
        XCTAssertFalse(loaded.historyEnabled)
        XCTAssertFalse(loaded.recordPlayback(video))
        XCTAssertEqual(loaded.history.first?.date, Date(timeIntervalSince1970: 2))
        loaded.clearHistory()
        XCTAssertTrue(LibraryStore(fileURL: url).history.isEmpty)
    }

    func testUnreadableAndNewerDocumentsRemainUntouched() throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var newer = LibraryDocument(); newer.version = 2
        var duplicates = LibraryDocument()
        duplicates.saved = Array(repeating: LibraryRecord(item: video, date: Date()), count: 2)
        for bytes in [Data("broken json".utf8), try JSONEncoder().encode(newer), try JSONEncoder().encode(duplicates)] {
            try bytes.write(to: url)
            let store = LibraryStore(fileURL: url)
            XCTAssertFalse(store.isWritable)
            XCTAssertFalse(store.toggleSaved(video))
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
        let store = LibraryStore(fileURL: url)
        try JSONEncoder().encode(LibraryDocument()).write(to: url)
        store.reload()
        XCTAssertTrue(store.isWritable)
        XCTAssertTrue(store.toggleSaved(video))
    }

    func testWriteFailureRollsBackAndCanBeRetried() throws {
        let url = location()
        let parent = url.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: parent) }
        let store = LibraryStore(fileURL: url)
        try Data("obstruction".utf8).write(to: parent)
        XCTAssertFalse(store.toggleSaved(video))
        XCTAssertTrue(store.saved.isEmpty)
        XCTAssertNotNil(store.lastError)
        try FileManager.default.removeItem(at: parent)
        XCTAssertTrue(store.toggleSaved(video))
        XCTAssertEqual(LibraryStore(fileURL: url).saved.first?.item, video)
    }

    func testRejectsInvalidKindsAndIDs() {
        let store = LibraryStore(fileURL: location())
        XCTAssertFalse(store.toggleSaved(channel))
        XCTAssertFalse(store.toggleSubscription(video))
        XCTAssertFalse(store.recordPlayback(BrowseItem(contentID: "bad", kind: .video, title: "Bad")))
        XCTAssertTrue(store.saved.isEmpty && store.subscriptions.isEmpty && store.history.isEmpty)
    }

    func testFailedResolutionDoesNotEnterHistory() async {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = LibraryStore(fileURL: url)
        let playback = PlaybackSession(resolver: LibraryFailingResolver())
        let recorder = LibraryPlaybackRecorder(playback: playback, library: store)
        let failed = expectation(description: "Resolution failed")
        let observation = playback.$phase.sink { phase in
            if case .failed = phase { failed.fulfill() }
        }
        playback.open(video)
        await fulfillment(of: [failed], timeout: 2)
        XCTAssertTrue(store.history.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        playback.stop()
        withExtendedLifetime((recorder, observation)) {}
    }

    func testRecorderPreservesMetadataAndRecordsOncePerOpen() async throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let audio = url.deletingLastPathComponent().appendingPathComponent("silence.wav")
        var wav = Data()
        func word(_ value: UInt32, bytes: Int) { for index in 0..<bytes { wav.append(UInt8((value >> (index * 8)) & 255)) } }
        wav.append(Data("RIFF".utf8)); word(160036, bytes: 4)
        wav.append(Data("WAVEfmt ".utf8)); word(16, bytes: 4); word(1, bytes: 2); word(1, bytes: 2)
        word(8000, bytes: 4); word(16000, bytes: 4); word(2, bytes: 2); word(16, bytes: 2)
        wav.append(Data("data".utf8)); word(160000, bytes: 4); wav.append(Data(repeating: 0, count: 160000))
        try wav.write(to: audio)
        let store = LibraryStore(fileURL: url)
        let playback = PlaybackSession(resolver: LibraryTestResolver(url: audio))
        playback.player.isMuted = true
        let recorder = LibraryPlaybackRecorder(playback: playback, library: store)
        let recorded = expectation(description: "Actual playback recorded")
        let observation = store.$history.dropFirst().filter { !$0.isEmpty }.prefix(1).sink { _ in recorded.fulfill() }
        playback.open(video)
        await fulfillment(of: [recorded], timeout: 10)
        XCTAssertEqual(store.history.first?.item.channelID, video.channelID)
        XCTAssertEqual(store.history.first?.item.title, "Resolved title")
        let date = store.history.first?.date
        playback.player.pause(); playback.player.play()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(store.history.count, 1)
        XCTAssertEqual(store.history.first?.date, date)
        playback.stop()
        withExtendedLifetime((recorder, observation)) {}
        XCTAssertFalse(try String(contentsOf: url).contains(audio.absoluteString))
    }
}

private struct LibraryTestResolver: StreamResolving {
    let url: URL
    func resolve(_ request: VideoRequest) async throws -> ResolvedVideo {
        ResolvedVideo(title: "Resolved title", streamURL: url, usesHLS: false)
    }
}

private struct LibraryFailingResolver: StreamResolving {
    func resolve(_ request: VideoRequest) async throws -> ResolvedVideo {
        throw URLError(.notConnectedToInternet)
    }
}
