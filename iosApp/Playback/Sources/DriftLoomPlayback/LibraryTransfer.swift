// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public struct LibraryImportPlan {
    public let summary: String
    public let warnings: [String]
    let library: LibraryDocument
    let playlists: PlaylistDocument
}

@MainActor
public enum LibraryTransfer {
    private struct Backup: Codable {
        var format = "DriftLoom.library"
        var version = 1
        var created = Date()
        let library: LibraryDocument
        let playlists: PlaylistDocument
    }
    private struct Recovery: Codable {
        var version = 1
        let library: Data?
        let playlists: Data?
    }
    private struct SubscriptionExport: Decodable {
        struct Item: Decodable { let service_id: Int; let url: String; let name: String }
        let subscriptions: [Item]
    }
    public static func export(library: LibraryStore, playlists: PlaylistStore) throws -> Data {
        let libraryData = try JSONDecoder().decode(LibraryDocument.self, from: library.snapshotData())
        let playlistData = try JSONDecoder().decode(PlaylistDocument.self, from: playlists.snapshotData())
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(Backup(library: libraryData, playlists: playlistData))
        guard data.count <= 20_000_000 else { throw BrowseError.unavailable("This library exceeds the 20 MB backup limit.") }
        return data
    }
    public static func preview(_ data: Data) throws -> LibraryImportPlan {
        if data.starts(with: [0x50, 0x4b]) { return try NewPipeDatabase.read(NewPipeArchive.database(data)) }
        guard data.count <= 20_000_000 else { throw BrowseError.unavailable("This import exceeds the 20 MB limit.") }
        let decoder = JSONDecoder()
        if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], object["format"] != nil {
            let backup = try decoder.decode(Backup.self, from: data)
            guard backup.format == "DriftLoom.library", backup.version == 1,
                  backup.library.version == 1, backup.playlists.version == 1,
                  valid(backup.library), PlaylistStore.valid(backup.playlists) else { throw CocoaError(.fileReadCorruptFile) }
            return LibraryImportPlan(summary: "Merge \(backup.library.saved.count) saved videos, \(backup.library.subscriptions.count) subscriptions, \(backup.library.history.count) history entries and \(backup.playlists.playlists.count) playlists.", warnings: [], library: backup.library, playlists: backup.playlists)
        }
        let source = try decoder.decode(SubscriptionExport.self, from: data)
        guard source.subscriptions.count <= 50_000 else { throw CocoaError(.fileReadCorruptFile) }
        var records: [LibraryRecord] = [], skipped = 0, ids = Set<String>()
        for subscription in source.subscriptions {
            guard subscription.service_id == 0 else { skipped += 1; continue }
            guard let url = URLComponents(string: subscription.url), url.scheme == "https",
                  ["www.youtube.com", "youtube.com"].contains(url.host?.lowercased() ?? ""),
                  url.user == nil, url.password == nil, url.port == nil else { skipped += 1; continue }
            let path = url.path.split(separator: "/")
            guard path.count == 2, path[0] == "channel", String(path[1]).range(of: "^UC[A-Za-z0-9_-]{22}$", options: .regularExpression) != nil,
                  !subscription.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { skipped += 1; continue }
            let id = String(path[1]); guard ids.insert(id).inserted else { continue }
            records.append(LibraryRecord(item: BrowseItem(contentID: id, kind: .channel, title: subscription.name), date: Date()))
        }
        guard !records.isEmpty || source.subscriptions.isEmpty else { throw BrowseError.unavailable("No supported YouTube channel subscriptions were found. Export NewPipe subscriptions as JSON; ZIP database backups aren't supported yet.") }
        var document = LibraryDocument(); document.subscriptions = records
        return LibraryImportPlan(summary: "Merge \(records.count) YouTube subscriptions.", warnings: skipped == 0 ? [] : ["\(skipped) unsupported service or invalid channel entries will be skipped."], library: document, playlists: PlaylistDocument())
    }
    private static func valid(_ document: LibraryDocument) -> Bool {
        document.saved.count <= 50_000 && document.subscriptions.count <= 50_000 && document.history.count <= 50_000
            && LibraryStore.valid(document.saved, kind: .video) && LibraryStore.valid(document.subscriptions, kind: .channel)
            && LibraryStore.valid(document.history, kind: .video)
    }
    public static func apply(_ plan: LibraryImportPlan, library: LibraryStore, playlists: PlaylistStore) throws {
        guard library.isWritable, playlists.isWritable,
              library.fileURL.deletingLastPathComponent() == playlists.fileURL.deletingLastPathComponent() else { throw CocoaError(.fileWriteNoPermission) }
        var current = try JSONDecoder().decode(LibraryDocument.self, from: library.snapshotData())
        var currentPlaylists = try JSONDecoder().decode(PlaylistDocument.self, from: playlists.snapshotData())
        func merge(_ current: [LibraryRecord], _ incoming: [LibraryRecord]) -> [LibraryRecord] {
            var result = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
            for record in incoming where result[record.id] == nil || result[record.id]!.date < record.date { result[record.id] = record }
            return result.values.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
        }
        current.saved = merge(current.saved, plan.library.saved)
        current.subscriptions = merge(current.subscriptions, plan.library.subscriptions)
        current.history = Array(merge(current.history, plan.library.history).prefix(LibraryStore.historyLimit))
        for incoming in plan.playlists.playlists {
            if let index = currentPlaylists.playlists.firstIndex(where: { $0.id == incoming.id }) {
                var ids = Set(currentPlaylists.playlists[index].entries.map(\.id))
                currentPlaylists.playlists[index].entries += incoming.entries.filter { ids.insert($0.id).inserted }
            } else { currentPlaylists.playlists.append(incoming) }
        }
        var ids = Set(currentPlaylists.bookmarks.map(\.id))
        currentPlaylists.bookmarks += plan.playlists.bookmarks.filter { ids.insert($0.id).inserted }
        guard valid(current), PlaylistStore.valid(currentPlaylists) else { throw BrowseError.unavailable("The merged library exceeds supported limits. Existing data is unchanged.") }
        let directory = library.fileURL.deletingLastPathComponent()
        try transaction(directory: directory, library: JSONEncoder().encode(current), playlists: JSONEncoder().encode(currentPlaylists))
        library.reload(); playlists.reload()
    }
    static func transaction(directory: URL, library: Data, playlists: Data,
                            writer: (Data, URL) throws -> Void = atomicWrite) throws {
        try recover(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let recovery = Recovery(library: try existing(directory.appendingPathComponent("library.json")), playlists: try existing(directory.appendingPathComponent("playlists.json")))
        let data = try JSONEncoder().encode(recovery)
        guard data.count < 60_000_000 else { throw BrowseError.unavailable("This library is too large to create a safe import recovery copy.") }
        let backups = directory.appendingPathComponent("PreImportBackups")
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        try atomicWrite(data, backups.appendingPathComponent(UUID().uuidString + ".json"))
        let journal = directory.appendingPathComponent("transfer-recovery.json")
        try atomicWrite(data, journal)
        do {
            try writer(library, directory.appendingPathComponent("library.json"))
            try writer(playlists, directory.appendingPathComponent("playlists.json"))
            try FileManager.default.removeItem(at: journal)
        } catch {
            try recover(directory: directory)
            throw error
        }
    }
    private static func existing(_ url: URL) throws -> Data? {
        if !FileManager.default.fileExists(atPath: url.path) { return nil }
        return try Data(contentsOf: url)
    }
    public static func recover(directory: URL) throws {
        let journal = directory.appendingPathComponent("transfer-recovery.json")
        guard FileManager.default.fileExists(atPath: journal.path) else { return }
        let data = try Data(contentsOf: journal)
        guard data.count < 60_000_000 else { throw CocoaError(.fileReadCorruptFile) }
        let backup = try JSONDecoder().decode(Recovery.self, from: data)
        guard backup.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
        for (name, data) in [("library.json", backup.library), ("playlists.json", backup.playlists)] {
            let url = directory.appendingPathComponent(name)
            if let data { try atomicWrite(data, url) }
            else if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
        try FileManager.default.removeItem(at: journal)
    }
    private static func atomicWrite(_ data: Data, _ url: URL) throws {
        var options: Data.WritingOptions = .atomic
#if os(iOS)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
#endif
        try data.write(to: url, options: options)
    }
}
