// SPDX-License-Identifier: GPL-3.0-or-later
import Combine
import Foundation

public struct PinnedHomeTab: Identifiable, Equatable, Codable, Sendable {
    public let item: BrowseItem
    public var id: String { item.id }
    public init(item: BrowseItem) { self.item = item }
}

@MainActor
public final class PinnedHomeTabs: ObservableObject {
    @Published public private(set) var tabs: [PinnedHomeTab] = []
    @Published public private(set) var error: String?
    @Published public private(set) var isWritable = true
    private let fileURL: URL
    private struct Document: Codable { var version = 1; let tabs: [PinnedHomeTab] }
    public init(fileURL: URL) {
        self.fileURL = fileURL
        do {
            let data = try Data(contentsOf: fileURL)
            guard data.count < 2_000_000 else { throw CocoaError(.fileReadCorruptFile) }
            let document = try JSONDecoder().decode(Document.self, from: data)
            guard document.version == 1, document.tabs.count <= 50,
                  Set(document.tabs.map(\.id)).count == document.tabs.count,
                  document.tabs.allSatisfy({ Self.valid($0.item) }) else { throw CocoaError(.fileReadCorruptFile) }
            tabs = document.tabs
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile { }
        catch { isWritable = false; self.error = "Your pinned home tabs couldn't be read. The saved file has been left untouched." }
    }
    public func contains(_ item: BrowseItem) -> Bool { tabs.contains { $0.id == item.id } }
    public func toggle(_ item: BrowseItem) {
        guard Self.valid(item) else { error = "Choose a supported channel or playlist to add to home."; return }
        if contains(item) { remove(item.id); return }
        guard tabs.count < 50 else { error = "You can pin up to 50 channel and playlist tabs."; return }
        _ = save(tabs + [PinnedHomeTab(item: item)])
    }
    public func remove(_ id: String) { _ = save(tabs.filter { $0.id != id }) }
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
        if item.kind == .channel { return item.contentID.range(of: "^UC[A-Za-z0-9_-]{22}$", options: .regularExpression) != nil }
        guard item.kind == .playlist, item.contentID.range(of: "^[A-Za-z0-9_-]{2,150}$", options: .regularExpression) != nil else { return false }
        if item.contentID.hasPrefix("RD") { return item.playlistSeed.map { (try? VideoRequest(input: $0).videoID) == $0 } ?? false }
        return true
    }
    private func save(_ tabs: [PinnedHomeTab]) -> Bool {
        guard isWritable else { return false }
        do {
            let data = try JSONEncoder().encode(Document(tabs: tabs))
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            var options: Data.WritingOptions = .atomic
#if os(iOS)
            options.insert(.completeFileProtectionUntilFirstUserAuthentication)
#endif
            try data.write(to: fileURL, options: options)
            self.tabs = tabs; error = nil; return true
        } catch { self.error = "Your pinned home tabs couldn't be saved. Previous saved data is unchanged."; return false }
    }
}
