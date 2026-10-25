// SPDX-License-Identifier: GPL-3.0-or-later
import AVFoundation
import XCTest
@testable import DriftLoomPlayback

private let items = ["11-9ZaYiTPE", "QdBZY2fkU-0", "dQw4w9WgXcQ"].map {
    BrowseItem(contentID: $0, kind: .video, title: $0)
}
private struct UnavailableResolver: StreamResolving {
    func resolve(_ request: VideoRequest) async throws -> ResolvedVideo { throw URLError(.notConnectedToInternet) }
}

@MainActor
final class PlaybackQueueTests: XCTestCase {
    func testNextPreviousRepeatAndEnd() {
        let session = PlaybackSession(resolver: UnavailableResolver())
        let queue = PlaybackQueue(playback: session)
        queue.start(items)
        XCTAssertEqual(session.videoID, items[0].contentID)
        queue.next()
        XCTAssertEqual(session.videoID, items[1].contentID)
        queue.previous()
        XCTAssertEqual(session.videoID, items[0].contentID)
        queue.select(queue.entries[2].id)
        queue.didFinishCurrent()
        XCTAssertEqual(session.videoID, items[2].contentID)
        XCTAssertFalse(queue.canGoNext)
        queue.repeatMode = .all
        queue.didFinishCurrent()
        XCTAssertEqual(session.videoID, items[0].contentID)
        queue.repeatMode = .one
        queue.didFinishCurrent()
        XCTAssertEqual(session.videoID, items[0].contentID)
        queue.stop()
        XCTAssertTrue(queue.entries.isEmpty)
        XCTAssertNil(session.videoID)
    }

    func testMoveAndRemovePreserveStableCurrentIdentity() {
        let session = PlaybackSession(resolver: UnavailableResolver())
        let queue = PlaybackQueue(playback: session)
        queue.start(items)
        let current = queue.currentID
        queue.move(from: IndexSet(integer: 0), to: 3)
        XCTAssertEqual(queue.currentID, current)
        XCTAssertEqual(queue.currentIndex, 2)
        XCTAssertEqual(session.videoID, items[0].contentID)
        queue.remove(current!)
        XCTAssertEqual(queue.entries.count, 2)
        XCTAssertEqual(session.videoID, items[2].contentID)
    }

    func testShuffleIsFiniteAndPreviousRetracesOrder() {
        let session = PlaybackSession(resolver: UnavailableResolver())
        let queue = PlaybackQueue(playback: session)
        queue.start(items); queue.shuffled = true
        let first = queue.currentID
        queue.next(); let second = queue.currentID
        queue.previous()
        XCTAssertEqual(queue.currentID, first)
        queue.next()
        XCTAssertEqual(queue.currentID, second)
        queue.next()
        XCTAssertEqual(Set([first!, second!, queue.currentID!]).count, 3)
        XCTAssertFalse(queue.canGoNext)
        let last = queue.currentID
        queue.next()
        XCTAssertEqual(queue.currentID, last)
    }

    func testPlayNextAndDuplicateVideosHaveIndependentIdentities() {
        let session = PlaybackSession(resolver: UnavailableResolver())
        let queue = PlaybackQueue(playback: session)
        queue.start([items[0], items[2]])
        queue.enqueue(items[1], next: true)
        XCTAssertEqual(queue.entries.map { $0.item.contentID }, items.map(\.contentID))
        queue.enqueue(items[0])
        XCTAssertEqual(queue.entries.count, 4)
        XCTAssertEqual(Set(queue.entries.map(\.id)).count, 4)
        queue.enqueue(BrowseItem(contentID: "invalid", kind: .video, title: "Invalid"))
        XCTAssertEqual(queue.entries.count, 4)
        queue.stop()
    }
}

@MainActor
final class AppPreferencesTests: XCTestCase {
    func testHomeConfigurationAndSearchPrivacySurviveReload() {
        let suite = "DriftLoom.Tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.setHomeSections([.history, .subscriptions, .history])
        XCTAssertEqual(preferences.homeSections, [.history, .subscriptions])
        preferences.setHomeSections([])
        XCTAssertEqual(preferences.homeSections, [.history, .subscriptions])
        preferences.recordSearch(" one "); preferences.recordSearch("two"); preferences.recordSearch("one")
        XCTAssertEqual(preferences.searchHistory, ["one", "two"])
        preferences.setRecordsSearchHistory(false)
        preferences.recordSearch("private search")
        preferences.setAppearance("Dark")
        let loaded = AppPreferences(defaults: defaults)
        XCTAssertEqual(loaded.homeSections, [.history, .subscriptions])
        XCTAssertEqual(loaded.searchHistory, ["one", "two"])
        XCTAssertFalse(loaded.recordsSearchHistory)
        XCTAssertEqual(loaded.appearance, "Dark")
        loaded.clearSearchHistory()
        XCTAssertTrue(AppPreferences(defaults: defaults).searchHistory.isEmpty)
    }
}

final class SubscriptionFeedParserTests: XCTestCase {
    func testRSSKeepsDatesChannelAndDeduplicatesWithoutInventingData() throws {
        let entry = """
        <entry><yt:videoId>11-9ZaYiTPE</yt:videoId><title>A &amp; B</title>
        <author><name>Artist</name></author><published>2026-10-25T10:00:00+00:00</published>
        <media:group><media:thumbnail url="https://i.ytimg.com/vi/11-9ZaYiTPE/hqdefault.jpg"/></media:group></entry>
        """
        let xml = """
        <feed xmlns:yt="http://www.youtube.com/xml/schemas/2015" xmlns:media="http://search.yahoo.com/mrss/">
        \(entry)\(entry)<entry><yt:videoId>bad</yt:videoId><title>Invalid</title></entry></feed>
        """
        let result = try FeedXMLParser.parse(Data(xml.utf8), channelID: "UCabcdefghijklmnopqrstuv")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.item.title, "A & B")
        XCTAssertEqual(result.first?.item.subtitle, "Artist")
        XCTAssertEqual(result.first?.published, ISO8601DateFormatter().date(from: "2026-10-25T10:00:00Z"))
        XCTAssertEqual(result.first?.item.channelID, "UCabcdefghijklmnopqrstuv")
        XCTAssertNotNil(result.first?.item.thumbnail)
        XCTAssertThrowsError(try FeedXMLParser.parse(Data("<feed><broken>".utf8), channelID: "UCabcdefghijklmnopqrstuv"))
    }
}

private actor FakeFeed: FeedLoading {
    func videos(channelID: String) async throws -> [FeedVideo] {
        if channelID == "broken" { throw URLError(.badServerResponse) }
        return [FeedVideo(item: items[channelID == "old" ? 0 : 1], published: Date(timeIntervalSince1970: channelID == "old" ? 1 : 2))]
    }
}

@MainActor
final class SubscriptionFeedTests: XCTestCase {
    func testFeedSortsByPublicationDateDeduplicatesAndReportsPartialFailures() async {
        let feed = SubscriptionFeedStore(client: FakeFeed())
        await feed.load(channelIDs: ["old", "new", "new", "broken"])
        XCTAssertEqual(feed.items.map { $0.item.contentID }, [items[1].contentID, items[0].contentID])
        XCTAssertEqual(feed.failedChannels, 1)
        XCTAssertEqual(feed.completedChannels, 3)
        XCTAssertFalse(feed.loading)
    }
}

@MainActor
final class PlaylistStoreTests: XCTestCase {
    func testInvalidRenamePreservesNameAndReportsError() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PlaylistStore(fileURL: root.appendingPathComponent("playlists.json"))
        let id = try XCTUnwrap(store.create(name: "Original"))
        store.rename(id, name: String(repeating: "x", count: 101))
        XCTAssertEqual(store.playlists.first?.name, "Original")
        XCTAssertNotNil(store.lastError)
    }
    func testCreateAddReorderRenameBookmarkAndReload() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("playlists.json")
        let store = PlaylistStore(fileURL: url)
        let id = try XCTUnwrap(store.create(name: " Road trip ", item: items[0]))
        XCTAssertTrue(store.add(items[1], to: id))
        XCTAssertTrue(store.add(items[0], to: id))
        XCTAssertEqual(Set(store.playlists[0].entries.map(\.id)).count, 3)
        store.move(in: id, from: IndexSet(integer: 0), to: 3)
        store.rename(id, name: "Music")
        let remote = BrowseItem(contentID: "PLabcdefghijk", kind: .playlist, title: "Online")
        store.toggleBookmark(remote)
        let loaded = PlaylistStore(fileURL: url)
        XCTAssertEqual(loaded.playlists.first?.name, "Music")
        XCTAssertEqual(loaded.playlists[0].entries.map { $0.item.contentID }, [items[1].contentID, items[0].contentID, items[0].contentID])
        XCTAssertEqual(loaded.bookmarks, [remote])
        let entry = loaded.playlists[0].entries[0].id
        loaded.removeVideo(entry, from: id)
        XCTAssertEqual(loaded.playlists[0].entries.count, 2)
        loaded.remove(id)
        loaded.toggleBookmark(remote)
        XCTAssertTrue(PlaylistStore(fileURL: url).playlists.isEmpty)
        XCTAssertTrue(PlaylistStore(fileURL: url).bookmarks.isEmpty)
    }

    func testCorruptPlaylistDocumentAndExistingLibraryArePreserved() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let libraryURL = root.appendingPathComponent("library.json")
        let library = LibraryStore(fileURL: libraryURL)
        XCTAssertTrue(library.toggleSaved(items[0]))
        let originalLibrary = try Data(contentsOf: libraryURL)
        let url = root.appendingPathComponent("playlists.json")
        let corrupt = Data("corrupt".utf8)
        try corrupt.write(to: url)
        let store = PlaylistStore(fileURL: url)
        XCTAssertFalse(store.isWritable)
        XCTAssertNil(store.create(name: "New"))
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
        XCTAssertEqual(try Data(contentsOf: libraryURL), originalLibrary)
    }

    func testFailedPlaylistWriteDoesNotPublishNewCollection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PlaylistStore(fileURL: root.appendingPathComponent("playlists.json"))
        try Data("obstruction".utf8).write(to: root)
        XCTAssertNil(store.create(name: "New"))
        XCTAssertTrue(store.playlists.isEmpty)
        XCTAssertNotNil(store.lastError)
    }
}

@MainActor
final class PlaybackPositionTests: XCTestCase {
    func testProgressPersistsAndCompletedOrRemovedHistoryIsDiscarded() {
        let suite = "DriftLoom.ProgressTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PlaybackPositions(defaults: defaults)
        store.record(id: items[0].contentID, seconds: 60, duration: 180)
        XCTAssertEqual(PlaybackPositions(defaults: defaults).seconds(for: items[0].contentID), 60)
        store.record(id: items[0].contentID, seconds: 175, duration: 180)
        XCTAssertNil(store.seconds(for: items[0].contentID))
        store.record(id: items[1].contentID, seconds: 30, duration: 180)
        store.retainOnly([])
        XCTAssertNil(PlaybackPositions(defaults: defaults).seconds(for: items[1].contentID))
    }
    func testInvalidAndLivePositionsAreNotStored() {
        let suite = "DriftLoom.ProgressTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PlaybackPositions(defaults: defaults)
        store.record(id: "invalid", seconds: 30, duration: 180)
        store.record(id: items[0].contentID, seconds: .nan, duration: 180)
        store.record(id: items[0].contentID, seconds: 30, duration: .infinity)
        XCTAssertNil(store.seconds(for: items[0].contentID))
    }
}
