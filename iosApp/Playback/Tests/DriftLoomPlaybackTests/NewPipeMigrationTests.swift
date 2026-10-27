// SPDX-License-Identifier: GPL-3.0-or-later
import SQLite3
import XCTest
import zlib
@testable import DriftLoomPlayback

@MainActor
final class NewPipeMigrationTests: XCTestCase {
    private func database(withGroups: Bool = false) throws -> Data {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(file.path, &db), SQLITE_OK)
        let sql = """
        PRAGMA user_version=9;
        CREATE TABLE subscriptions(service_id INTEGER,url TEXT,name TEXT,avatar_url TEXT);
        CREATE TABLE streams(uid INTEGER,service_id INTEGER,url TEXT,title TEXT,uploader TEXT,thumbnail_url TEXT);
        CREATE TABLE playlists(uid INTEGER,name TEXT);
        CREATE TABLE playlist_stream_join(playlist_id INTEGER,stream_id INTEGER,join_index INTEGER);
        CREATE TABLE stream_history(stream_id INTEGER,access_date INTEGER);
        CREATE TABLE remote_playlists(uid INTEGER,service_id INTEGER,url TEXT,name TEXT,uploader TEXT,thumbnail_url TEXT);
        INSERT INTO remote_playlists VALUES(1,0,'https://www.youtube.com/playlist?list=PL-example','Remote','Channel',NULL);
        INSERT INTO subscriptions VALUES(0,'https://www.youtube.com/channel/UCUb-HI7Kd-Dr1fBvYjV1IYg','Channel',NULL);
        INSERT INTO subscriptions VALUES(1,'https://soundcloud.com/other','Unsupported',NULL);
        INSERT INTO streams VALUES(1,0,'https://www.youtube.com/watch?v=11-9ZaYiTPE','Video','Channel',NULL);
        INSERT INTO playlists VALUES(1,'Imported');
        INSERT INTO playlist_stream_join VALUES(1,1,0),(1,1,1);
        INSERT INTO stream_history VALUES(1,1700000000000),(1,1700000001000);
        """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        if withGroups {
            let groupsSQL = """
            ALTER TABLE subscriptions ADD COLUMN uid INTEGER;
            UPDATE subscriptions SET uid=1 WHERE service_id=0;
            UPDATE subscriptions SET uid=2 WHERE service_id=1;
            CREATE TABLE feed_group(uid INTEGER,name TEXT,sort_order INTEGER);
            CREATE TABLE feed_group_subscription_join(group_id INTEGER,subscription_id INTEGER);
            INSERT INTO feed_group VALUES(1,'Music',1),(2,'Empty',0);
            INSERT INTO feed_group_subscription_join VALUES(1,1),(1,2);
            """
            XCTAssertEqual(sqlite3_exec(db, groupsSQL, nil, nil, nil), SQLITE_OK)
        }
        sqlite3_close(db)
        return try Data(contentsOf: file)
    }
    private func zip(_ data: Data, name: String = "newpipe.db", deflated: Bool = false) throws -> Data {
        var payload = data
        if deflated {
            var stream = z_stream()
            guard deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw CocoaError(.fileReadCorruptFile) }
            defer { deflateEnd(&stream) }
            var output = Data(count: data.count * 2 + 1024)
            let capacity = output.count
            let status = data.withUnsafeBytes { input in output.withUnsafeMutableBytes { destination -> Int32 in
                stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: UInt8.self).baseAddress); stream.avail_in = uInt(data.count)
                stream.next_out = destination.bindMemory(to: UInt8.self).baseAddress; stream.avail_out = uInt(capacity)
                return deflate(&stream, Z_FINISH)
            } }
            XCTAssertEqual(status, Z_STREAM_END); payload = Data(output.prefix(Int(stream.total_out)))
        }
        let crc = data.withUnsafeBytes { UInt32(crc32(0, $0.bindMemory(to: UInt8.self).baseAddress, uInt(data.count))) }
        var result = Data()
        func word(_ value: Int, _ count: Int) { for index in 0..<count { result.append(UInt8((value >> (index * 8)) & 255)) } }
        word(0x04034b50,4); word(20,2); word(0,2); word(deflated ? 8 : 0,2); word(0,2); word(0,2)
        word(Int(crc),4); word(payload.count,4); word(data.count,4); word(name.utf8.count,2); word(0,2)
        result.append(Data(name.utf8)); result.append(payload)
        let central = result.count
        word(0x02014b50,4); word(20,2); word(20,2); word(0,2); word(deflated ? 8 : 0,2); word(0,2); word(0,2)
        word(Int(crc),4); word(payload.count,4); word(data.count,4); word(name.utf8.count,2)
        word(0,2); word(0,2); word(0,2); word(0,2); word(0,4); word(0,4); result.append(Data(name.utf8))
        let size = result.count - central
        word(0x06054b50,4); word(0,2); word(0,2); word(1,2); word(1,2); word(size,4); word(central,4); word(0,2)
        return result
    }
    func testResumePositionsMigrateForHistoryWithoutReplacingLocalOnes() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try database().write(to: file)
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(file.path, &db), SQLITE_OK)
        let sql = """
        ALTER TABLE streams ADD COLUMN duration INTEGER;
        UPDATE streams SET duration=600 WHERE uid=1;
        INSERT INTO streams VALUES(2,0,'https://www.youtube.com/watch?v=dQw4w9WgXcQ','Not in history','Channel',NULL,212);
        INSERT INTO streams VALUES(3,0,'https://www.youtube.com/watch?v=jNQXAC9IVRw','Finished','Channel',NULL,19);
        INSERT INTO playlist_stream_join VALUES(1,2,2),(1,3,3);
        INSERT INTO stream_history VALUES(3,1700000002000);
        CREATE TABLE stream_state(stream_id INTEGER,progress_time INTEGER);
        INSERT INTO stream_state VALUES(1,123456),(2,60000),(3,15000);
        """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
        let plan = try LibraryTransfer.preview(try zip(Data(contentsOf: file)))
        // Only history entries count; the 19-second video at 15 s is too close to its end to resume.
        XCTAssertEqual(plan.positions, [ImportedPosition(videoID: "11-9ZaYiTPE", seconds: 123.456, duration: 600)])
        XCTAssertTrue(plan.summary.contains("1 resume positions"))

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let name = "DriftLoom.Tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let positions = PlaybackPositions(defaults: defaults)
        let library = LibraryStore(fileURL: directory.appendingPathComponent("library.json"))
        let playlists = PlaylistStore(fileURL: directory.appendingPathComponent("playlists.json"))
        library.setHistoryEnabled(false)
        try LibraryTransfer.apply(plan, library: library, playlists: playlists, positions: positions)
        XCTAssertNil(positions.seconds(for: "11-9ZaYiTPE"), "History recording off: positions are not imported")
        library.setHistoryEnabled(true)
        positions.record(id: "11-9ZaYiTPE", seconds: 42, duration: 600)
        try LibraryTransfer.apply(plan, library: library, playlists: playlists, positions: positions)
        XCTAssertEqual(positions.seconds(for: "11-9ZaYiTPE"), 42, "A position saved on this device wins")
        positions.retainOnly([])
        try LibraryTransfer.apply(plan, library: library, playlists: playlists, positions: positions)
        XCTAssertEqual(positions.seconds(for: "11-9ZaYiTPE"), 123.456)
    }

    func testStoredAndDeflatedNewPipeBackupsMigrateAndMergeIdempotently() throws {
        let database = try database()
        for compressed in [false, true] {
            let archive = try zip(database, deflated: compressed)
            XCTAssertEqual(try NewPipeArchive.database(archive), database)
            let plan = try LibraryTransfer.preview(archive)
            XCTAssertFalse(plan.warnings.isEmpty)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let library = LibraryStore(fileURL: directory.appendingPathComponent("library.json"))
            let playlists = PlaylistStore(fileURL: directory.appendingPathComponent("playlists.json"))
            try LibraryTransfer.apply(plan, library: library, playlists: playlists)
            try LibraryTransfer.apply(plan, library: library, playlists: playlists)
            XCTAssertEqual(library.subscriptions.count, 1)
            XCTAssertEqual(library.history.count, 1)
            XCTAssertEqual(library.history.first?.date.timeIntervalSince1970 ?? 0, 1700000001, accuracy: 0.001)
            XCTAssertEqual(playlists.bookmarks.count, 1)
            XCTAssertEqual(playlists.playlists.count, 1)
            XCTAssertEqual(playlists.playlists.first?.entries.count, 2)
            XCTAssertEqual(Set(playlists.playlists.first!.entries.map(\.id)).count, 2)
        }
    }
    func testAndroidGroupsPreserveOrderAndSupportedMembershipWithStableIDs() throws {
        let data = try database(withGroups: true)
        let plan = try LibraryTransfer.preview(zip(data, deflated: true))
        XCTAssertEqual(plan.groups?.groups.map(\.name), ["Empty", "Music"])
        XCTAssertEqual(plan.groups?.groups.last?.channelIDs, ["UCUb-HI7Kd-Dr1fBvYjV1IYg"])
        let again = try LibraryTransfer.preview(zip(data))
        XCTAssertEqual(again.groups?.groups, plan.groups?.groups)
    }
    func testArchiveCorruptionAndPathMembersAreRejected() throws {
        let data = try database()
        XCTAssertThrowsError(try NewPipeArchive.database(zip(data, name: "../newpipe.db")))
        let archive = try zip(data)
        XCTAssertThrowsError(try NewPipeArchive.database(Data(archive.dropLast())))
        var corrupt = archive; corrupt[50] ^= 0xff
        XCTAssertThrowsError(try NewPipeArchive.database(corrupt))
        XCTAssertThrowsError(try NewPipeDatabase.read(Data("not a database".utf8)))
    }
}
