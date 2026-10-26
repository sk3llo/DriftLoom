// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import DriftLoomPlayback

@MainActor
final class SubscriptionGroupTests: XCTestCase {
    private let channel = "UCUb-HI7Kd-Dr1fBvYjV1IYg"
    private let other = "UC-lHJZR3Gqxm24_Vd_AJ5Yw"
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url
    }
    func testGroupEditsOrderAndRemovalSurviveRelaunch() throws {
        let url = try directory().appendingPathComponent("subscription-groups.json")
        let groups = SubscriptionGroups(fileURL: url)
        let first = UUID(), second = UUID()
        XCTAssertTrue(groups.upsert(id: first, name: " Music ", channelIDs: [channel, channel]))
        XCTAssertTrue(groups.upsert(id: second, name: "Science", channelIDs: [other]))
        groups.move(from: IndexSet(integer: 1), to: 0)
        let restored = SubscriptionGroups(fileURL: url)
        XCTAssertEqual(restored.groups.map(\.id), [second, first])
        XCTAssertEqual(restored.groups.last?.name, "Music")
        XCTAssertEqual(restored.groups.last?.channelIDs, [channel])
        XCTAssertTrue(restored.upsert(id: first, name: "Renamed", channelIDs: [other]))
        restored.remove(second)
        XCTAssertEqual(SubscriptionGroups(fileURL: url).groups, [SubscriptionGroup(id: first, name: "Renamed", channelIDs: [other])])
    }
    func testFilteringIgnoresUnsubscribedMembersWithoutLosingMembership() throws {
        let groups = SubscriptionGroups(fileURL: try directory().appendingPathComponent("groups.json"))
        let id = UUID(); groups.upsert(id: id, name: "Group", channelIDs: [channel, other])
        XCTAssertEqual(groups.channelIDs(for: id, subscribed: [channel]), [channel])
        XCTAssertEqual(groups.groups.first?.channelIDs.count, 2)
        XCTAssertEqual(groups.channelIDs(for: nil, subscribed: [other, channel]), [other, channel])
        XCTAssertEqual(groups.channelIDs(for: UUID(), subscribed: [channel]), [])
    }
    func testCorruptFutureAndDuplicateDocumentsArePreserved() throws {
        let url = try directory().appendingPathComponent("groups.json")
        let id = UUID()
        let invalid = [Data("{\"version\":99,\"groups\":[]}".utf8),
                       try JSONEncoder().encode(SubscriptionGroupDocument(groups: [SubscriptionGroup(id: id, name: "A"), SubscriptionGroup(id: id, name: "B")]))]
        for bytes in invalid {
            try bytes.write(to: url)
            let groups = SubscriptionGroups(fileURL: url)
            XCTAssertFalse(groups.isWritable)
            XCTAssertFalse(groups.upsert(name: "Replacement", channelIDs: []))
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
    }
    func testInvalidEditDoesNotReplaceValidGroup() throws {
        let url = try directory().appendingPathComponent("groups.json")
        let groups = SubscriptionGroups(fileURL: url)
        groups.upsert(name: "Valid", channelIDs: [channel])
        let bytes = try Data(contentsOf: url)
        XCTAssertFalse(groups.upsert(name: "Bad", channelIDs: ["not-a-channel"]))
        XCTAssertFalse(groups.upsert(name: "   ", channelIDs: []))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
    func testNativeBackupRoundTripMergesMembershipAndPreservesCurrentGroupName() throws {
        let source = try directory(), target = try directory()
        let library = LibraryStore(fileURL: source.appendingPathComponent("library.json"))
        let playlists = PlaylistStore(fileURL: source.appendingPathComponent("playlists.json"))
        let groups = SubscriptionGroups(fileURL: source.appendingPathComponent("subscription-groups.json"))
        let id = UUID(); groups.upsert(id: id, name: "Incoming", channelIDs: [channel])
        let backup = try LibraryTransfer.export(library: library, playlists: playlists, groups: groups)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: backup) as? [String: Any])?["version"] as? Int, 2)
        let plan = try LibraryTransfer.preview(backup)
        XCTAssertEqual(plan.groups?.groups.first?.channelIDs, [channel])
        let destination = SubscriptionGroups(fileURL: target.appendingPathComponent("subscription-groups.json"))
        destination.upsert(id: id, name: "My current name", channelIDs: [other])
        let targetLibrary = LibraryStore(fileURL: target.appendingPathComponent("library.json"))
        let targetPlaylists = PlaylistStore(fileURL: target.appendingPathComponent("playlists.json"))
        try LibraryTransfer.apply(plan, library: targetLibrary, playlists: targetPlaylists, groups: destination)
        try LibraryTransfer.apply(plan, library: targetLibrary, playlists: targetPlaylists, groups: destination)
        XCTAssertEqual(destination.groups.count, 1)
        XCTAssertEqual(destination.groups.first?.name, "My current name")
        XCTAssertEqual(Set(destination.groups.first!.channelIDs), Set([channel, other]))
    }
    func testGroupWriteFailureRollsBackAllThreeLibraryFiles() throws {
        let directory = try directory()
        let names = ["library.json", "playlists.json", "subscription-groups.json"]
        for name in names { try Data(("previous-" + name).utf8).write(to: directory.appendingPathComponent(name)) }
        XCTAssertThrowsError(try LibraryTransfer.transaction(directory: directory, library: Data("new library".utf8), playlists: Data("new playlists".utf8), groups: Data("new groups".utf8)) { bytes, url in
            if url.lastPathComponent == "subscription-groups.json" { throw CocoaError(.fileWriteOutOfSpace) }
            try bytes.write(to: url, options: .atomic)
        })
        for name in names { XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(name)), Data(("previous-" + name).utf8)) }
    }
    func testInterruptedImportRestoresGroupsAndLegacyJournalsLeaveThemUntouched() throws {
        let root = try directory()
        let groupURL = root.appendingPathComponent("subscription-groups.json")
        let journalURL = root.appendingPathComponent("transfer-recovery.json")
        let old = Data("old groups".utf8)
        try Data("partially replaced groups".utf8).write(to: groupURL)
        let journal: [String: Any] = ["version": 2, "groups": old.base64EncodedString(), "capturesGroups": true]
        try JSONSerialization.data(withJSONObject: journal).write(to: journalURL)
        try LibraryTransfer.recover(directory: root)
        XCTAssertEqual(try Data(contentsOf: groupURL), old)
        try JSONSerialization.data(withJSONObject: ["version": 1]).write(to: journalURL)
        try LibraryTransfer.recover(directory: root)
        XCTAssertEqual(try Data(contentsOf: groupURL), old)
    }
    func testLegacyBackupDoesNotEraseExistingGroups() throws {
        let root = try directory()
        let library = LibraryStore(fileURL: root.appendingPathComponent("library.json"))
        let playlists = PlaylistStore(fileURL: root.appendingPathComponent("playlists.json"))
        let groups = SubscriptionGroups(fileURL: root.appendingPathComponent("subscription-groups.json"))
        groups.upsert(name: "Existing", channelIDs: [channel])
        let prior = try Data(contentsOf: groups.fileURL)
        let plan = try LibraryTransfer.preview(LibraryTransfer.export(library: library, playlists: playlists))
        try LibraryTransfer.apply(plan, library: library, playlists: playlists, groups: groups)
        XCTAssertEqual(try Data(contentsOf: groups.fileURL), prior)
    }
    func testFeedFilterCombinesDateAndWatchedSettingsAndPersistsPreferences() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let items = [("11-9ZaYiTPE", 0.0), ("dQw4w9WgXcQ", -90000.0), ("jNQXAC9IVRw", -900000.0)].map { id, offset in
            FeedVideo(item: BrowseItem(contentID: id, kind: .video, title: id), published: now.addingTimeInterval(offset))
        }
        XCTAssertEqual(FeedFilter.apply(items, period: .week, hidingWatched: true, watchedIDs: ["11-9ZaYiTPE"], now: now).map(\.item.contentID), ["dQw4w9WgXcQ"])
        XCTAssertEqual(FeedFilter.apply(items, period: .today, hidingWatched: false, watchedIDs: [], now: now).count, 1)
        let suite = "DriftLoom.Tests." + UUID().uuidString, defaults: UserDefaults
        defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = AppPreferences(defaults: defaults)
        prefs.setFeedPeriod(.month); prefs.setHidesWatchedFeed(true)
        let restored = AppPreferences(defaults: defaults)
        XCTAssertEqual(restored.feedPeriod, .month); XCTAssertTrue(restored.hidesWatchedFeed)
    }
}

private actor GroupFeedFixture: FeedLoading {
    func videos(channelID: String) async throws -> [FeedVideo] {
        try await Task.sleep(nanoseconds: 100_000_000)
        return [FeedVideo(item: BrowseItem(contentID: channelID.hasSuffix("IYg") ? "11-9ZaYiTPE" : "jNQXAC9IVRw", kind: .video, title: channelID, channelID: channelID), published: Date())]
    }
}

@MainActor
final class GroupFeedTests: XCTestCase {
    func testSwitchingGroupsClearsThePreviousGroupsVideosWhileLoading() async {
        let store = SubscriptionFeedStore(client: GroupFeedFixture())
        await store.load(channelIDs: ["UCUb-HI7Kd-Dr1fBvYjV1IYg"])
        XCTAssertEqual(store.items.first?.item.contentID, "11-9ZaYiTPE")
        let load = Task { await store.load(channelIDs: ["UC-lHJZR3Gqxm24_Vd_AJ5Yw"]) }
        for _ in 0..<30 { await Task.yield(); if store.loading { break } }
        XCTAssertTrue(store.loading)
        XCTAssertTrue(store.items.isEmpty)
        await load.value
        XCTAssertEqual(store.items.first?.item.contentID, "jNQXAC9IVRw")
    }
}
