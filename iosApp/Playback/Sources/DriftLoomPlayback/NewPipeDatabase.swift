// SPDX-License-Identifier: GPL-3.0-or-later
import CryptoKit
import Foundation
import SQLite3

/// Reads a temporary copy with fixed SQL, a read-only connection, and a bounded VM budget.
/// Android preferences, credentials, and downloads are deliberately not deserialized or imported.
@MainActor
enum NewPipeDatabase {
    static func read(_ data: Data) throws -> LibraryImportPlan {
        guard data.count <= 100_000_000, data.starts(with: Data("SQLite format 3\0".utf8)) else { throw CocoaError(.fileReadCorruptFile) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DriftLoomMigration-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("database.sqlite")
        try data.write(to: file, options: .atomic)
        var handle: OpaquePointer?
        guard sqlite3_open_v2(file.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK, let db = handle else {
            if let handle { sqlite3_close(handle) }; throw CocoaError(.fileReadCorruptFile)
        }
        defer { sqlite3_close(db) }
        _ = sqlite3_limit(db, SQLITE_LIMIT_LENGTH, 1_000_000)
        sqlite3_exec(db, "PRAGMA query_only=ON; PRAGMA trusted_schema=OFF;", nil, nil, nil)
        let budget = UnsafeMutablePointer<Int>.allocate(capacity: 1); budget.initialize(to: 20_000)
        defer { sqlite3_progress_handler(db, 0, nil, nil); budget.deinitialize(count: 1); budget.deallocate() }
        sqlite3_progress_handler(db, 1000, { context in
            guard let context else { return 1 }
            let counter = context.assumingMemoryBound(to: Int.self); counter.pointee -= 1
            return counter.pointee <= 0 ? 1 : 0
        }, budget)
        var textBudget = 20_000_000
        func rows(_ sql: String, limit: Int = 50_000) throws -> [[String: String]] {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw CocoaError(.fileReadCorruptFile) }
            defer { sqlite3_finalize(statement) }
            var result: [[String: String]] = [], status = sqlite3_step(statement)
            while status == SQLITE_ROW {
                guard result.count < limit else { throw BrowseError.unavailable("This backup exceeds supported migration limits.") }
                var row: [String: String] = [:]
                for column in 0..<sqlite3_column_count(statement) {
                    let bytes = Int(sqlite3_column_bytes(statement, column))
                    textBudget -= bytes
                    guard bytes <= 100_000, textBudget >= 0 else { throw BrowseError.unavailable("This backup exceeds supported text limits.") }
                    if let name = sqlite3_column_name(statement, column), let value = sqlite3_column_text(statement, column) {
                        row[String(cString: name)] = String(cString: value)
                    }
                }
                result.append(row); status = sqlite3_step(statement)
            }
            guard status == SQLITE_DONE else { throw CocoaError(.fileReadCorruptFile) }
            return result
        }
        let tables = Set(try rows("SELECT name FROM sqlite_master WHERE type='table'", limit: 1000).compactMap { $0["name"] })
        guard Set(["subscriptions", "streams", "playlists", "playlist_stream_join", "stream_history"]).isSubset(of: tables),
              let version = try rows("PRAGMA user_version").first?["user_version"].flatMap(Int.init), (1...9).contains(version) else {
            throw BrowseError.unavailable("This NewPipe database version isn't supported. Existing data is unchanged.")
        }
        func channelID(_ value: String?) -> String? {
            guard let value, let url = URLComponents(string: value), url.scheme == "https", ["www.youtube.com", "youtube.com"].contains(url.host ?? "") else { return nil }
            let parts = url.path.split(separator: "/")
            guard parts.count == 2, parts[0] == "channel", String(parts[1]).range(of: "^UC[A-Za-z0-9_-]{22}$", options: .regularExpression) != nil else { return nil }
            return String(parts[1])
        }
        func thumbnail(_ value: String?) -> URL? { value.flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil } }
        func stableID(_ key: String) -> UUID {
            var bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16)); bytes[6] = (bytes[6] & 15) | 0x50; bytes[8] = (bytes[8] & 63) | 0x80
            return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
        }
        var library = LibraryDocument(), playlists = PlaylistDocument(), skipped = 0
        var subscriptionIDs = Set<String>()
        for row in try rows("SELECT service_id,url,name,avatar_url FROM subscriptions") {
            guard row["service_id"] == "0", let id = channelID(row["url"]), let name = row["name"], !name.isEmpty else { skipped += 1; continue }
            if subscriptionIDs.insert(id).inserted { library.subscriptions.append(LibraryRecord(item: BrowseItem(contentID: id, kind: .channel, title: name, thumbnail: thumbnail(row["avatar_url"])), date: Date(timeIntervalSince1970: 0))) }
        }
        var streams: [String: BrowseItem] = [:]
        for row in try rows("SELECT uid,service_id,url,title,uploader,thumbnail_url FROM streams WHERE uid IN (SELECT stream_id FROM playlist_stream_join UNION SELECT stream_id FROM stream_history)") {
            guard row["service_id"] == "0", let uid = row["uid"], let input = row["url"], let request = try? VideoRequest(input: input),
                  let title = row["title"], !title.isEmpty else { skipped += 1; continue }
            streams[uid] = BrowseItem(contentID: request.videoID, kind: .video, title: title, subtitle: row["uploader"] ?? "", thumbnail: thumbnail(row["thumbnail_url"]))
        }
        var historyIDs = Set<String>()
        for row in try rows("SELECT stream_id,MAX(access_date) AS latest FROM stream_history GROUP BY stream_id ORDER BY latest DESC") {
            guard let id = row["stream_id"], let item = streams[id], let timestamp = row["latest"].flatMap(Double.init), timestamp.isFinite else { continue }
            if historyIDs.insert(item.contentID).inserted { library.history.append(LibraryRecord(item: item, date: Date(timeIntervalSince1970: timestamp / 1000))) }
        }
        library.history = Array(library.history.prefix(LibraryStore.historyLimit))
        let joins = try rows("SELECT playlist_id,stream_id,join_index FROM playlist_stream_join ORDER BY playlist_id,join_index")
        let grouped = Dictionary(grouping: joins, by: { $0["playlist_id"] ?? "" })
        for row in try rows("SELECT uid,name FROM playlists ORDER BY uid") {
            guard let uid = row["uid"], let name = row["name"], !name.isEmpty, name.count <= 100 else { throw CocoaError(.fileReadCorruptFile) }
            let namespace = "NewPipe.playlist." + uid + "." + name
            let entries = (grouped[uid] ?? []).compactMap { join -> PlaylistVideo? in
                guard let item = streams[join["stream_id"] ?? ""] else { return nil }
                return PlaylistVideo(id: stableID(namespace + "." + (join["join_index"] ?? "") + "." + item.contentID), item: item)
            }
            guard entries.count <= 5000 else { throw BrowseError.unavailable("An imported playlist exceeds 5,000 videos.") }
            playlists.playlists.append(LocalPlaylist(id: stableID(namespace), name: name, entries: entries))
        }
        if tables.contains("remote_playlists") {
            var ids = Set<String>()
            for row in try rows("SELECT service_id,url,name,uploader,thumbnail_url FROM remote_playlists ORDER BY uid") {
                guard row["service_id"] == "0", let raw = row["url"], let url = URLComponents(string: raw), url.scheme == "https",
                      ["youtube.com", "www.youtube.com"].contains(url.host ?? ""), let name = row["name"], !name.isEmpty,
                      let id = url.queryItems?.first(where: { $0.name == "list" })?.value,
                      id.range(of: "^[A-Za-z0-9_-]{2,150}$", options: .regularExpression) != nil else { skipped += 1; continue }
                let seed = url.queryItems?.first(where: { $0.name == "v" })?.value
                if id.hasPrefix("RD"), seed.flatMap({ try? VideoRequest(input: $0).videoID }) != seed || seed == nil { skipped += 1; continue }
                if ids.insert(id).inserted {
                    playlists.bookmarks.append(BrowseItem(contentID: id, kind: .playlist, title: name, subtitle: row["uploader"] ?? "", thumbnail: thumbnail(row["thumbnail_url"]), playlistSeed: seed))
                }
            }
        }
        guard PlaylistStore.valid(playlists) else { throw CocoaError(.fileReadCorruptFile) }
        return LibraryImportPlan(summary: "Merge \(library.subscriptions.count) YouTube subscriptions, \(library.history.count) history entries and \(playlists.playlists.count) local playlists and \(playlists.bookmarks.count) playlist bookmarks from NewPipe.", warnings: ["Android preferences, stream positions, and downloaded media aren't migrated."] + (skipped == 0 ? [] : ["\(skipped) unsupported or invalid entries were skipped."]), library: library, playlists: playlists)
    }
}
