// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import DriftLoomPlayback

@MainActor
final class NewPipePreferencesTests: XCTestCase {
    private let channel = "UCUb-HI7Kd-Dr1fBvYjV1IYg"
    private func json(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object) }
    private var tabs: String {
        let list: [[String: Any]] = [
            ["tab_id": 0], ["tab_id": 2], ["tab_id": 5, "service_id": 0, "kiosk_id": "live"],
            ["tab_id": 6, "channel_service_id": 0, "channel_url": "https://www.youtube.com/channel/\(channel)", "channel_name": "Pinned channel"],
            ["tab_id": 1], ["tab_id": 8, "playlist_service_id": 0, "playlist_url": "https://www.youtube.com/playlist?list=PL-example", "playlist_name": "Online list", "playlist_type": "REMOTE"],
            ["tab_id": 8, "playlist_service_id": -1, "playlist_id": 4, "playlist_name": "Local", "playlist_type": "LOCAL"],
            ["tab_id": 9, "feed_group_id": 1, "feed_group_name": "Music"], ["tab_id": 5, "service_id": 1, "kiosk_id": "Top 50"],
            ["tab_id": 5, "service_id": 0, "kiosk_id": "trending_gaming"], ["tab_id": 2], ["tab_id": 7]
        ]
        return String(data: try! JSONSerialization.data(withJSONObject: ["tabs": list]), encoding: .utf8)!
    }

    func testMapsSupportedSettingsAndTabsAndIgnoresTheRest() throws {
        let settings = try NewPipePreferences.parse(json([
            "theme": "black_theme", "content_language": "pt-BR", "content_country": "br", "enable_search_history": false,
            "enable_watch_history": true, "enable_playback_resume": false, "cross_network_downloads": true,
            "show_search_suggestions": ["show_local_search_suggestions"], "saved_tabs_key": tabs,
            "unrelated": 3, "peertube_instance_list": ["x"]
        ]))
        XCTAssertEqual(settings.appearance, "Dark"); XCTAssertEqual(settings.contentLanguage, "pt"); XCTAssertEqual(settings.contentCountry, "BR")
        XCTAssertEqual(settings.recordsSearchHistory, false); XCTAssertEqual(settings.recordsWatchHistory, true)
        XCTAssertEqual(settings.resumesPlayback, false); XCTAssertEqual(settings.usesSearchSuggestions, false)
        XCTAssertEqual(settings.downloadNetwork, .any)
        XCTAssertEqual(settings.homeTabs, [
            .section(.feed), .section(.live), .pinned(BrowseItem(contentID: channel, kind: .channel, title: "Pinned channel")),
            .section(.subscriptions), .pinned(BrowseItem(contentID: "PL-example", kind: .playlist, title: "Online list")),
            .section(.gaming), .section(.trending)
        ])
        XCTAssertEqual(settings.skippedTabs, 3, "Local playlist, feed group and another service's kiosk")
        XCTAssertTrue(settings.changes.contains("Theme: Dark"))
    }

    func testSystemDefaultsAndInvalidValuesAreLeftAlone() throws {
        let settings = try NewPipePreferences.parse(json([
            "theme": "purple_theme", "content_language": "system", "content_country": "system", "enable_watch_history": "yes",
            "show_search_suggestions": "show_remote_search_suggestions", "saved_tabs_key": "{not json"
        ]))
        XCTAssertTrue(settings.isEmpty)
        XCTAssertThrowsError(try NewPipePreferences.parse(Data("[1,2]".utf8)))
        XCTAssertThrowsError(try NewPipePreferences.parse(Data(repeating: 32, count: 2_000_001)))
    }

    func testRealNewPipeBackupCarriesItsSettingsIntoThePreview() throws {
        let zip = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("app/src/test/resources/settings/db_ser_json.zip")
        let plan = try LibraryTransfer.preview(Data(contentsOf: zip))
        let settings = try XCTUnwrap(plan.settings)
        XCTAssertEqual(settings.appearance, "Light")
        XCTAssertNil(settings.contentLanguage, "\"system\" keeps DriftLoom's own language")
        XCTAssertEqual(settings.recordsWatchHistory, true); XCTAssertEqual(settings.downloadNetwork, .wifiOnly)
        XCTAssertEqual(settings.homeTabs, [.section(.bookmarks), .section(.trending)])
        let noJSON = zip.deletingLastPathComponent().appendingPathComponent("db_ser_nojson.zip")
        XCTAssertNil(try LibraryTransfer.preview(Data(contentsOf: noJSON)).settings, "Java-serialized settings are never read")
    }

    func testEveryRealAndroidBackupWithADatabaseImports() throws {
        // These are real NewPipe exports: Android stores the database in WAL mode.
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("app/src/test/resources/settings")
        let zips = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("db_") && $0.pathExtension == "zip" }
        XCTAssertEqual(zips.count, 6)
        for zip in zips {
            let data = try Data(contentsOf: zip)
            XCTAssertEqual(try NewPipeArchive.database(data)[18], 2, "Fixture should be WAL: \(zip.lastPathComponent)")
            let plan = try LibraryTransfer.preview(data)
            XCTAssertFalse(plan.summary.isEmpty, zip.lastPathComponent)
            XCTAssertEqual(plan.settings != nil, zip.lastPathComponent.hasSuffix("_json.zip") && !zip.lastPathComponent.hasSuffix("nojson.zip"), zip.lastPathComponent)
        }
    }

    func testApplyingSettingsKeepsNewPipeTabOrderWithPinnedTabs() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let name = "DriftLoom.Tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = AppPreferences(defaults: defaults)
        let library = LibraryStore(fileURL: directory.appendingPathComponent("library.json"))
        let pinned = PinnedHomeTabs(fileURL: directory.appendingPathComponent("home-tabs.json"))
        let settings = try NewPipePreferences.parse(json(["theme": "light_theme", "enable_watch_history": false, "content_country": "DE", "saved_tabs_key": tabs]))
        LibraryTransfer.applySettings(settings, preferences: preferences, library: library, pinnedTabs: pinned)
        XCTAssertEqual(preferences.appearance, "Light"); XCTAssertFalse(library.historyEnabled)
        XCTAssertEqual(preferences.contentLocale.country, "DE"); XCTAssertEqual(preferences.contentLocale.language, "en")
        XCTAssertEqual(preferences.homeSections, [.feed, .live, .subscriptions, .gaming, .trending])
        XCTAssertEqual(pinned.tabs.map(\.item.contentID), [channel, "PL-example"])
        XCTAssertEqual(pinned.arrangement(sections: preferences.homeSections, localPlaylistIDs: []), [
            .section(.feed), .section(.live), .pinned("channel:" + channel), .section(.subscriptions),
            .pinned("playlist:PL-example"), .section(.gaming), .section(.trending)
        ])
        // Applying twice doesn't duplicate or remove pins.
        LibraryTransfer.applySettings(settings, preferences: preferences, library: library, pinnedTabs: pinned)
        XCTAssertEqual(pinned.tabs.count, 2)
    }
}
