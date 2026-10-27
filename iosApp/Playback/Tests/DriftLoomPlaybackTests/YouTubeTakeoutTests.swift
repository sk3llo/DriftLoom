// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
import zlib
@testable import DriftLoomPlayback

@MainActor
final class YouTubeTakeoutTests: XCTestCase {
    private let a = "UCUb-HI7Kd-Dr1fBvYjV1IYg", b = "UCSJ4gkVC6NrvII8umztf0Ow", own = "UC" + String(repeating: "x", count: 22)

    /// A stored (uncompressed) ZIP with the given members.
    private func zip(_ files: [(String, String)]) -> Data {
        var result = Data(), central = Data()
        func word(_ value: Int, _ count: Int, into data: inout Data) { for index in 0..<count { data.append(UInt8((value >> (index * 8)) & 255)) } }
        for (name, text) in files {
            let body = Data(text.utf8), offset = result.count
            let crc = body.withUnsafeBytes { Int(crc32(0, $0.bindMemory(to: UInt8.self).baseAddress, uInt(body.count))) }
            word(0x04034b50, 4, into: &result); word(20, 2, into: &result); word(0, 2, into: &result); word(0, 2, into: &result)
            word(0, 4, into: &result); word(crc, 4, into: &result); word(body.count, 4, into: &result); word(body.count, 4, into: &result)
            word(name.utf8.count, 2, into: &result); word(0, 2, into: &result); result.append(Data(name.utf8)); result.append(body)
            word(0x02014b50, 4, into: &central); word(20, 2, into: &central); word(20, 2, into: &central); word(0, 2, into: &central)
            word(0, 2, into: &central); word(0, 4, into: &central); word(crc, 4, into: &central); word(body.count, 4, into: &central)
            word(body.count, 4, into: &central); word(name.utf8.count, 2, into: &central); word(0, 2, into: &central); word(0, 2, into: &central)
            word(0, 2, into: &central); word(0, 2, into: &central); word(0, 4, into: &central); word(offset, 4, into: &central)
            central.append(Data(name.utf8))
        }
        let start = result.count
        result.append(central)
        word(0x06054b50, 4, into: &result); word(0, 2, into: &result); word(0, 2, into: &result); word(files.count, 2, into: &result)
        word(files.count, 2, into: &result); word(central.count, 4, into: &result); word(start, 4, into: &result); word(0, 2, into: &result)
        return result
    }

    func testCSVHandlesQuotesTranslatedHeadersAndOddRows() throws {
        let csv = "\u{FEFF}Kanal-ID,Kanal-URL,Kanaltitel\r\n\(a),http://www.youtube.com/channel/\(a),\"Rick, \"\"Never\"\" Gonna\"\r\n"
            + "\(b),http://www.youtube.com/channel/\(b),Lofi Girl\r\n\(b),http://www.youtube.com/channel/\(b),Duplicate\r\n"
            + "PL123,http://www.youtube.com/playlist?list=PL123,Not a channel\r\n\(own),http://www.youtube.com/channel/\(b),Mismatched\r\n\r\n"
        let plan = try LibraryTransfer.preview(Data(csv.utf8))
        XCTAssertEqual(plan.library.subscriptions.map(\.item.contentID), [a, b])
        XCTAssertEqual(plan.library.subscriptions.first?.item.title, "Rick, \"Never\" Gonna")
        XCTAssertTrue(plan.summary.contains("2 YouTube subscriptions"))
        XCTAssertTrue(plan.warnings.contains { $0.contains("3 rows") }, "\(plan.warnings)")
        XCTAssertThrowsError(try LibraryTransfer.preview(Data("Channel Id,Channel Url,Channel Title\n".utf8)))
    }

    func testZipReadsTranslatedFoldersAndIgnoresYourOwnChannelFile() throws {
        let subscriptions = "Channel Id,Channel Url,Channel Title\n\(a),http://www.youtube.com/channel/\(a),Rick\n\(b),https://www.youtube.com/channel/\(b),\n"
        let archive = zip([
            ("Takeout/YouTube und YouTube Music/Kanal/Kanal.csv", "Kanal-ID,Kanaltitel (Original),Sichtbarkeit\n\(own),Me,Public\n"),
            ("Takeout/YouTube und YouTube Music/Abos/Abos.csv", subscriptions),
            ("Takeout/YouTube und YouTube Music/Playlists/Mix.csv", "Video-ID,Zeitstempel\ndQw4w9WgXcQ,2024-01-01\n"),
            ("Takeout/archive_browser.html", "<html></html>")
        ])
        let plan = try LibraryTransfer.preview(archive)
        XCTAssertEqual(Set(plan.library.subscriptions.map(\.item.contentID)), [a, b])
        XCTAssertFalse(plan.library.subscriptions.contains { $0.item.contentID == own }, "Your own channel isn't a subscription")
        XCTAssertEqual(plan.library.subscriptions.first { $0.item.contentID == b }?.item.title, "YouTube channel", "Empty titles get a placeholder")
        XCTAssertNil(plan.settings)
        XCTAssertThrowsError(try LibraryTransfer.preview(zip([("Takeout/YouTube/history.csv", "a,b\n1,2\n")]))) { error in
            XCTAssertTrue(error.localizedDescription.contains("subscriptions"), error.localizedDescription)
        }
    }

    func testLegacyJSONExportAndNewPipeExportsStillImport() throws {
        let legacy = #"[{"snippet":{"title":"Rick","resourceId":{"kind":"youtube#channel","channelId":"\#(a)"},"thumbnails":{"default":{"url":"https://yt3.ggpht.com/x.jpg"}}}},{"snippet":{"title":"Bad","resourceId":{"channelId":"nope"}}}]"#
        let plan = try LibraryTransfer.preview(Data(legacy.utf8))
        XCTAssertEqual(plan.library.subscriptions.map(\.item.contentID), [a])
        XCTAssertEqual(plan.library.subscriptions.first?.item.thumbnail?.host, "yt3.ggpht.com")
        XCTAssertTrue(plan.warnings.contains { $0.contains("1 rows") })
        let newPipe = #"{"app_version":"0.29.1","app_version_int":1015,"subscriptions":[{"service_id":0,"url":"https://www.youtube.com/channel/\#(b)","name":"Lofi Girl"}]}"#
        XCTAssertEqual(try LibraryTransfer.preview(Data(newPipe.utf8)).library.subscriptions.map(\.item.contentID), [b])
    }

    func testTakeoutSubscriptionsMergeIntoTheLibrary() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = LibraryStore(fileURL: directory.appendingPathComponent("library.json"))
        let playlists = PlaylistStore(fileURL: directory.appendingPathComponent("playlists.json"))
        _ = library.toggleSubscription(BrowseItem(contentID: a, kind: .channel, title: "Already here"))
        let plan = try LibraryTransfer.preview(Data("Channel Id,Channel Url,Channel Title\n\(a),http://www.youtube.com/channel/\(a),Rick\n\(b),http://www.youtube.com/channel/\(b),Lofi\n".utf8))
        try LibraryTransfer.apply(plan, library: library, playlists: playlists)
        XCTAssertEqual(Set(library.subscriptions.map(\.item.contentID)), [a, b])
        XCTAssertEqual(library.subscriptions.first { $0.item.contentID == a }?.item.title, "Already here", "Existing subscriptions are kept")
    }

    func testCSVRowsFollowRFC4180() {
        XCTAssertEqual(YouTubeTakeout.csvRows("a,\"b\nc\",\"d\"\"e\"\r\nf"), [["a", "b\nc", "d\"e"], ["f"]])
        XCTAssertEqual(YouTubeTakeout.csvRows(""), [])
    }
}
