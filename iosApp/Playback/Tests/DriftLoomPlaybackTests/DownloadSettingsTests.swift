// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import DriftLoomPlayback

final class DownloadSettingsTests: XCTestCase {
    func testWifiPolicyRestrictsSessionAndWaitsForConnectivity() {
        let wifi = URLSessionConfiguration.background(withIdentifier: "DriftLoom.Tests.wifi")
        DownloadNetwork.wifiOnly.configure(wifi)
        XCTAssertFalse(wifi.allowsCellularAccess)
        XCTAssertTrue(wifi.waitsForConnectivity)
        XCTAssertTrue(wifi.sessionSendsLaunchEvents)
        XCTAssertFalse(wifi.isDiscretionary)
        XCTAssertFalse(DownloadNetwork.wifiOnly.permits(connected: true, cellular: true))
        XCTAssertTrue(DownloadNetwork.wifiOnly.permits(connected: true, cellular: false))
        let any = URLSessionConfiguration.background(withIdentifier: "DriftLoom.Tests.any")
        DownloadNetwork.any.configure(any)
        XCTAssertTrue(any.allowsCellularAccess)
        XCTAssertTrue(DownloadNetwork.any.permits(connected: true, cellular: true))
        XCTAssertFalse(DownloadNetwork.any.permits(connected: false, cellular: false))
        XCTAssertNotEqual(wifi.identifier, any.identifier)
    }
    func testOlderJobMetadataDecodesAndNewNetworkChoiceSurvivesRestart() throws {
        let record = DownloadRecord(item: BrowseItem(contentID: "11-9ZaYiTPE", kind: .video, title: "Video"), choice: DownloadChoice(id: "hls", name: "HLS", kind: .hls))
        let bytes = try JSONEncoder().encode(record)
        let old = try JSONDecoder().decode(DownloadRecord.self, from: bytes)
        XCTAssertNil(old.network); XCTAssertNil(old.waitingForNetwork)
        var waiting = old; waiting.network = .wifiOnly; waiting.waitingForNetwork = true
        let restored = try JSONDecoder().decode(DownloadRecord.self, from: JSONEncoder().encode(waiting))
        XCTAssertEqual(restored.network, .wifiOnly); XCTAssertEqual(restored.waitingForNetwork, true)
        XCTAssertNil(restored.localPath)
    }
    func testStorageScannerCountsOnlyMediaFilesAndSkipsLinksAndDuplicateRoots() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let media = root.appendingPathComponent("media"), package = media.appendingPathComponent("asset.movpkg")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let first = media.appendingPathComponent("first.mp4"), segment = package.appendingPathComponent("segment.mp4")
        try Data(repeating: 3, count: 65536).write(to: first)
        try Data(repeating: 4, count: 65536).write(to: segment)
        let unrelated = root.appendingPathComponent("unrelated.mp4")
        try Data(repeating: 5, count: 1_000_000).write(to: unrelated)
        try FileManager.default.createSymbolicLink(at: media.appendingPathComponent("outside-link"), withDestinationURL: unrelated)
        let usage = await DownloadStorage.measure([media, first, package])
        XCTAssertEqual(usage.files, 2); XCTAssertGreaterThan(usage.bytes, 0); XCTAssertFalse(usage.incomplete)
        let bounded = await DownloadStorage.measure([media], limit: 1)
        XCTAssertTrue(bounded.incomplete); XCTAssertLessThanOrEqual(bounded.files, 1)
        let missing = await DownloadStorage.measure([root.appendingPathComponent("missing")])
        XCTAssertTrue(missing.incomplete)
    }
}

@MainActor
final class DownloadPreferenceTests: XCTestCase {
    func testWifiDefaultAndNetworkPreferencePersistWithoutChangingAnExistingJob() {
        let name = "DriftLoom.Tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = AppPreferences(defaults: defaults)
        XCTAssertEqual(preferences.downloadNetwork, .wifiOnly)
        preferences.setDownloadNetwork(.any)
        XCTAssertEqual(AppPreferences(defaults: defaults).downloadNetwork, .any)
        defaults.set("unsupported", forKey: "downloadNetwork")
        XCTAssertEqual(AppPreferences(defaults: defaults).downloadNetwork, .wifiOnly)
    }
}
