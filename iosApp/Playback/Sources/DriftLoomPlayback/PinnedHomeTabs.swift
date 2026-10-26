// SPDX-License-Identifier: GPL-3.0-or-later
import Combine
import Foundation

public struct PinnedHomeTab: Identifiable, Equatable, Codable, Sendable {
    public let item: BrowseItem
    public var id: String { item.id }
    public init(item: BrowseItem) { self.item = item }
}

/// One home tab: a built-in section, a pinned channel/remote playlist, or a pinned local playlist.
public enum HomeTabKey: Hashable, Sendable {
    case section(HomeSection), pinned(String), local(UUID)
    public var rawValue: String {
        switch self {
        case let .section(section): return "section:" + section.rawValue
        case let .pinned(id): return "pinned:" + id
        case let .local(id): return "local:" + id.uuidString
        }
    }
    public init?(rawValue: String) {
        guard let colon = rawValue.firstIndex(of: ":") else { return nil }
        let kind = rawValue[..<colon], value = String(rawValue[rawValue.index(after: colon)...])
        switch kind {
        case "section": guard let section = HomeSection(rawValue: value) else { return nil }; self = .section(section)
        case "pinned": guard !value.isEmpty, value.count <= 200 else { return nil }; self = .pinned(value)
        case "local": guard let id = UUID(uuidString: value) else { return nil }; self = .local(id)
        default: return nil
        }
    }
}

@MainActor
public final class PinnedHomeTabs: ObservableObject {
    @Published public private(set) var tabs: [PinnedHomeTab] = []
    /// Local playlists shown as home tabs, by playlist ID.
    @Published public private(set) var localPlaylists: [UUID] = []
    /// Combined order across sections, pinned and local tabs. Empty keeps the default grouping.
    @Published public private(set) var order: [HomeTabKey] = []
    @Published public private(set) var error: String?
    @Published public private(set) var isWritable = true
    private let fileURL: URL
    /// Version 2 adds local playlists and a combined order. Version 1 is still written while
    /// neither is used, so earlier builds keep reading files that only contain pinned tabs.
    private struct Document: Codable {
        var version = 1; let tabs: [PinnedHomeTab]; var localPlaylists: [UUID]? = nil; var order: [String]? = nil
    }
    public init(fileURL: URL) {
        self.fileURL = fileURL
        do {
            let data = try Data(contentsOf: fileURL)
            guard data.count < 2_000_000 else { throw CocoaError(.fileReadCorruptFile) }
            let document = try JSONDecoder().decode(Document.self, from: data)
            let local = document.localPlaylists ?? [], keys = document.order ?? []
            guard [1, 2].contains(document.version), document.tabs.count <= 50,
                  document.version == 2 || (document.localPlaylists == nil && document.order == nil),
                  Set(document.tabs.map(\.id)).count == document.tabs.count,
                  local.count <= 50, Set(local).count == local.count, keys.count <= 200,
                  document.tabs.allSatisfy({ Self.valid($0.item) }) else { throw CocoaError(.fileReadCorruptFile) }
            let order = keys.compactMap(HomeTabKey.init(rawValue:))
            guard order.count == keys.count, Set(order).count == order.count else { throw CocoaError(.fileReadCorruptFile) }
            tabs = document.tabs; localPlaylists = local; self.order = order
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile { }
        catch { isWritable = false; self.error = "Your pinned home tabs couldn't be read. The saved file has been left untouched." }
    }
    /// Visible tabs in display order. Saved positions win; anything new follows the default
    /// grouping (sections, then pinned channels/playlists, then local playlists).
    public func arrangement(sections: [HomeSection], localPlaylistIDs: Set<UUID>) -> [HomeTabKey] {
        let available = sections.map(HomeTabKey.section) + tabs.map { .pinned($0.id) }
            + localPlaylists.filter(localPlaylistIDs.contains).map(HomeTabKey.local)
        let present = Set(available)
        let ordered = order.filter(present.contains)
        let placed = Set(ordered)
        return ordered + available.filter { !placed.contains($0) }
    }
    public func setOrder(_ keys: [HomeTabKey]) {
        var seen = Set<HomeTabKey>()
        let unique = keys.filter { seen.insert($0).inserted }
        guard unique.count <= 200 else { return }
        _ = save(tabs, local: localPlaylists, order: unique)
    }
    /// Put a tab first in a saved combined order; without one, the section order already decides.
    public func moveToFront(_ key: HomeTabKey) {
        guard !order.isEmpty, order.first != key else { return }
        setOrder([key] + order.filter { $0 != key })
    }
    public func containsLocal(_ id: UUID) -> Bool { localPlaylists.contains(id) }
    public func toggleLocal(_ id: UUID) {
        if containsLocal(id) { removeLocal(id); return }
        guard localPlaylists.count < 50 else { error = "You can pin up to 50 local playlists."; return }
        _ = save(tabs, local: localPlaylists + [id], order: order)
    }
    public func removeLocal(_ id: UUID) {
        _ = save(tabs, local: localPlaylists.filter { $0 != id }, order: order.filter { $0 != .local(id) })
    }
    /// Drop pins of deleted local playlists.
    public func retainLocal(_ ids: Set<UUID>) {
        guard localPlaylists.contains(where: { !ids.contains($0) }) else { return }
        let kept = localPlaylists.filter(ids.contains)
        _ = save(tabs, local: kept, order: order.filter { if case let .local(id) = $0 { return ids.contains(id) }; return true })
    }
    public func contains(_ item: BrowseItem) -> Bool { tabs.contains { $0.id == item.id } }
    public func toggle(_ item: BrowseItem) {
        guard Self.valid(item) else { error = "Choose a supported channel or playlist to add to home."; return }
        if contains(item) { remove(item.id); return }
        guard tabs.count < 50 else { error = "You can pin up to 50 channel and playlist tabs."; return }
        _ = save(tabs + [PinnedHomeTab(item: item)])
    }
    public func remove(_ id: String) { _ = save(tabs.filter { $0.id != id }, local: localPlaylists, order: order.filter { $0 != .pinned(id) }) }
    public func move(from offsets: IndexSet, to destination: Int) {
        guard destination >= 0, destination <= tabs.count, offsets.allSatisfy({ tabs.indices.contains($0) }) else { return }
        let moved = offsets.sorted().map { tabs[$0] }
        var next = tabs.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        next.insert(contentsOf: moved, at: destination - offsets.filter { $0 < destination }.count)
        _ = save(next)
    }
    public func dismissError() { error = nil }
    private static func valid(_ item: BrowseItem) -> Bool {
        guard !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, item.title.count <= 5000 else { return false }
        if item.kind == .channel { return ChannelIDs.valid(item.contentID) }
        if item.kind == .playlist, SoundCloudID.playlistNumber(item.contentID) != nil { return true }
        guard item.kind == .playlist, item.contentID.range(of: "^[A-Za-z0-9_-]{2,150}$", options: .regularExpression) != nil else { return false }
        if item.contentID.hasPrefix("RD") { return item.playlistSeed.map { (try? VideoRequest(input: $0).videoID) == $0 } ?? false }
        return true
    }
    private func save(_ tabs: [PinnedHomeTab]) -> Bool { save(tabs, local: localPlaylists, order: order) }
    private func save(_ tabs: [PinnedHomeTab], local: [UUID], order: [HomeTabKey]) -> Bool {
        guard isWritable else { return false }
        do {
            let extended = !local.isEmpty || !order.isEmpty
            let document = extended ? Document(version: 2, tabs: tabs, localPlaylists: local, order: order.map(\.rawValue)) : Document(tabs: tabs)
            let data = try JSONEncoder().encode(document)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            var options: Data.WritingOptions = .atomic
#if os(iOS)
            options.insert(.completeFileProtectionUntilFirstUserAuthentication)
#endif
            try data.write(to: fileURL, options: options)
            self.tabs = tabs; localPlaylists = local; self.order = order; error = nil; return true
        } catch { self.error = "Your pinned home tabs couldn't be saved. Previous saved data is unchanged."; return false }
    }
}
