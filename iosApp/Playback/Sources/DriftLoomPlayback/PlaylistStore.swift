// SPDX-License-Identifier: GPL-3.0-or-later
import Combine
import Foundation

public struct PlaylistVideo: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let item: BrowseItem
    public init(item: BrowseItem) { id = UUID(); self.item = item }
    init(id: UUID, item: BrowseItem) { self.id = id; self.item = item }
}

public struct LocalPlaylist: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var entries: [PlaylistVideo]
    public init(name: String, entries: [PlaylistVideo] = []) { id = UUID(); self.name = name; self.entries = entries }
    init(id: UUID, name: String, entries: [PlaylistVideo]) { self.id = id; self.name = name; self.entries = entries }
}

struct PlaylistDocument: Codable {
    var version = 1
    var playlists: [LocalPlaylist] = []
    var bookmarks: [BrowseItem] = []
}

/// Separate versioned storage lets existing library documents remain readable and unchanged.
@MainActor
public final class PlaylistStore: ObservableObject {
    @Published public private(set) var playlists: [LocalPlaylist] = []
    @Published public private(set) var bookmarks: [BrowseItem] = []
    @Published public private(set) var isWritable = false
    @Published public private(set) var lastError: String?
    public let fileURL: URL
    private var document = PlaylistDocument()
    public init(fileURL: URL) { self.fileURL = fileURL; reload() }
    public func reload() {
        do {
            let data = try Data(contentsOf: fileURL)
            let loaded = try JSONDecoder().decode(PlaylistDocument.self, from: data)
            guard loaded.version == 1, Self.valid(loaded) else { throw CocoaError(.fileReadCorruptFile) }
            publish(loaded); isWritable = true; lastError = nil
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            publish(PlaylistDocument()); isWritable = true; lastError = nil
        } catch {
            isWritable = false; lastError = "Your playlists couldn't be read. Their saved file has been left untouched."
        }
    }
    public func blockForRecovery(_ message: String) { isWritable = false; lastError = message }
    func snapshotData() throws -> Data {
        guard isWritable else { throw CocoaError(.fileReadCorruptFile) }
        return try JSONEncoder().encode(document)
    }
    public func dismissError() { lastError = nil }
    @discardableResult public func create(name: String, item: BrowseItem? = nil) -> UUID? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 100 else { lastError = "Choose a playlist name between 1 and 100 characters."; return nil }
        if let item, !Self.video(item) { return nil }
        let playlist = LocalPlaylist(name: name, entries: item.map { [PlaylistVideo(item: $0)] } ?? [])
        var next = document; next.playlists.append(playlist)
        return persist(next) ? playlist.id : nil
    }
    @discardableResult public func add(_ item: BrowseItem, to id: UUID) -> Bool {
        guard Self.video(item), let index = document.playlists.firstIndex(where: { $0.id == id }) else { return false }
        guard document.playlists[index].entries.count < 5000 else { lastError = "This playlist already has 5,000 videos."; return false }
        var next = document; next.playlists[index].entries.append(PlaylistVideo(item: item)); return persist(next)
    }
    public func rename(_ id: UUID, name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 100 else { lastError = "Choose a playlist name between 1 and 100 characters."; return }
        guard let index = document.playlists.firstIndex(where: { $0.id == id }) else { return }
        var next = document; next.playlists[index].name = name; _ = persist(next)
    }
    public func remove(_ id: UUID) {
        var next = document; next.playlists.removeAll { $0.id == id }; _ = persist(next)
    }
    public func removeVideo(_ videoID: UUID, from playlistID: UUID) {
        guard let index = document.playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        var next = document; next.playlists[index].entries.removeAll { $0.id == videoID }; _ = persist(next)
    }
    public func move(in id: UUID, from offsets: IndexSet, to destination: Int) {
        guard let index = document.playlists.firstIndex(where: { $0.id == id }) else { return }
        let entries = document.playlists[index].entries
        guard destination >= 0, destination <= entries.count, offsets.allSatisfy({ entries.indices.contains($0) }) else { return }
        let moving = offsets.sorted().map { entries[$0] }
        var remaining = entries.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        remaining.insert(contentsOf: moving, at: destination - offsets.filter { $0 < destination }.count)
        var next = document; next.playlists[index].entries = remaining; _ = persist(next)
    }
    public func isBookmarked(_ id: String) -> Bool { bookmarks.contains { $0.contentID == id } }
    public func toggleBookmark(_ item: BrowseItem) {
        guard Self.bookmark(item) else { return }
        var next = document
        if next.bookmarks.contains(where: { $0.contentID == item.contentID }) { next.bookmarks.removeAll { $0.contentID == item.contentID } }
        else { next.bookmarks.insert(item, at: 0) }
        _ = persist(next)
    }
    private func persist(_ next: PlaylistDocument) -> Bool {
        guard isWritable else { lastError = "Your playlist file is unavailable. Try loading it again before editing."; return false }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(next)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            var options: Data.WritingOptions = .atomic
#if os(iOS)
            options.insert(.completeFileProtectionUntilFirstUserAuthentication)
#endif
            try data.write(to: fileURL, options: options)
            publish(next); lastError = nil; return true
        } catch { lastError = "Your playlists couldn't be saved. Previous saved data is unchanged."; return false }
    }
    private func publish(_ value: PlaylistDocument) { document = value; playlists = value.playlists; bookmarks = value.bookmarks }
    private static func video(_ item: BrowseItem) -> Bool {
        item.kind == .video && !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (try? VideoRequest(input: item.contentID).videoID) == item.contentID
    }
    private static func bookmark(_ item: BrowseItem) -> Bool {
        guard item.kind == .playlist, !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if SoundCloudID.playlistNumber(item.contentID) != nil { return true }
        guard item.contentID.range(of: "^[A-Za-z0-9_-]{2,150}$", options: .regularExpression) != nil else { return false }
        if item.contentID.hasPrefix("RD") { return item.playlistSeed.map { (try? VideoRequest(input: $0).videoID) == $0 } ?? false }
        return true
    }
    static func valid(_ value: PlaylistDocument) -> Bool {
        Set(value.playlists.map(\.id)).count == value.playlists.count
            && Set(value.bookmarks.map(\.id)).count == value.bookmarks.count
            && value.bookmarks.allSatisfy(bookmark)
            && value.playlists.allSatisfy {
                !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 100
                    && $0.entries.count <= 5000 && Set($0.entries.map(\.id)).count == $0.entries.count
                    && $0.entries.allSatisfy { video($0.item) }
            }
    }
}
