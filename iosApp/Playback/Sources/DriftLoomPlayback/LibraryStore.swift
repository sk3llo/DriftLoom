// SPDX-License-Identifier: GPL-3.0-or-later
import Combine
import Foundation

public struct LibraryRecord: Codable, Equatable, Identifiable, Sendable {
    public let item: BrowseItem
    public let date: Date
    public var id: String { item.id }
}

struct LibraryDocument: Codable {
    var version = 1
    var saved: [LibraryRecord] = []
    var subscriptions: [LibraryRecord] = []
    var history: [LibraryRecord] = []
    var historyEnabled = true
}

/// Writes are atomic and publish only after succeeding. Unreadable/newer documents are
/// preserved and block writes until they can be read, rather than being replaced with defaults.
@MainActor
public final class LibraryStore: ObservableObject {
    @Published public private(set) var saved: [LibraryRecord] = []
    @Published public private(set) var subscriptions: [LibraryRecord] = []
    @Published public private(set) var history: [LibraryRecord] = []
    @Published public private(set) var historyEnabled = true
    @Published public private(set) var lastError: String?
    @Published public private(set) var isWritable = false
    public let fileURL: URL
    private var document = LibraryDocument()
    public static let historyLimit = 500

    public static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DriftLoom", isDirectory: true)
            .appendingPathComponent("library.json")
    }

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        reload()
    }

    public func reload() {
        do {
            let data = try Data(contentsOf: fileURL)
            let loaded = try JSONDecoder().decode(LibraryDocument.self, from: data)
            guard loaded.version == 1,
                  Self.valid(loaded.saved, kind: .video), Self.valid(loaded.subscriptions, kind: .channel),
                  Self.valid(loaded.history, kind: .video) else { throw CocoaError(.fileReadCorruptFile) }
            publish(loaded); isWritable = true; lastError = nil
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            publish(LibraryDocument()); isWritable = true; lastError = nil
        } catch {
            isWritable = false
            lastError = "Your library couldn't be read. The saved file has been left untouched."
        }
    }

    public func dismissError() { lastError = nil }
    public func isSaved(_ id: String) -> Bool { saved.contains { $0.item.contentID == id } }
    public func isSubscribed(_ id: String) -> Bool { subscriptions.contains { $0.item.contentID == id } }

    @discardableResult
    public func toggleSaved(_ item: BrowseItem, date: Date = Date()) -> Bool {
        guard Self.validItem(item, kind: .video) else { return invalidItem() }
        var next = document
        if next.saved.contains(where: { $0.item.contentID == item.contentID }) {
            next.saved.removeAll { $0.item.contentID == item.contentID }
        } else { next.saved.insert(LibraryRecord(item: item, date: date), at: 0) }
        return persist(next)
    }

    @discardableResult
    public func toggleSubscription(_ item: BrowseItem, date: Date = Date()) -> Bool {
        guard Self.validItem(item, kind: .channel) else { return invalidItem() }
        var next = document
        if next.subscriptions.contains(where: { $0.item.contentID == item.contentID }) {
            next.subscriptions.removeAll { $0.item.contentID == item.contentID }
        } else { next.subscriptions.insert(LibraryRecord(item: item, date: date), at: 0) }
        return persist(next)
    }

    @discardableResult
    public func recordPlayback(_ item: BrowseItem, date: Date = Date()) -> Bool {
        guard document.historyEnabled else { return false }
        guard Self.validItem(item, kind: .video) else { return invalidItem() }
        var next = document
        next.history.removeAll { $0.item.contentID == item.contentID }
        next.history.insert(LibraryRecord(item: item, date: date), at: 0)
        next.history = Array(next.history.prefix(Self.historyLimit))
        return persist(next)
    }

    public func removeSaved(_ id: String) {
        var next = document; next.saved.removeAll { $0.item.contentID == id }; _ = persist(next)
    }
    public func unsubscribe(_ id: String) {
        var next = document; next.subscriptions.removeAll { $0.item.contentID == id }; _ = persist(next)
    }
    public func removeHistory(_ id: String) {
        var next = document; next.history.removeAll { $0.item.contentID == id }; _ = persist(next)
    }
    public func clearHistory() {
        var next = document; next.history = []; _ = persist(next)
    }
    public func setHistoryEnabled(_ enabled: Bool) {
        var next = document; next.historyEnabled = enabled; _ = persist(next)
    }

    private func persist(_ next: LibraryDocument) -> Bool {
        guard isWritable else {
            lastError = "Your saved library is unavailable. Try loading it again before making changes."
            return false
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(next)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            var options: Data.WritingOptions = .atomic
#if os(iOS)
            options.insert(.completeFileProtectionUntilFirstUserAuthentication)
#endif
            try data.write(to: fileURL, options: options)
            publish(next); lastError = nil
            return true
        } catch {
            lastError = "Your library couldn't be saved. Your previous saved data is unchanged."
            return false
        }
    }

    private func publish(_ next: LibraryDocument) {
        document = next
        saved = next.saved; subscriptions = next.subscriptions; history = next.history
        historyEnabled = next.historyEnabled
    }

    private func invalidItem() -> Bool {
        lastError = "This item can't be added to your library."
        return false
    }

    private static func valid(_ records: [LibraryRecord], kind: BrowseItem.Kind) -> Bool {
        Set(records.map(\.id)).count == records.count
            && records.allSatisfy { validItem($0.item, kind: kind) && $0.date.timeIntervalSince1970.isFinite }
    }
    private static func validItem(_ item: BrowseItem, kind: BrowseItem.Kind) -> Bool {
        guard item.kind == kind, !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if kind == .video {
            return (try? VideoRequest(input: item.contentID).videoID) == item.contentID
        }
        return item.contentID.range(of: "^UC[A-Za-z0-9_-]{22}$", options: .regularExpression) != nil
    }
}

/// Record real playback, once per open, rather than recording failed extraction or pause/resume.
@MainActor
public final class LibraryPlaybackRecorder {
    private var observations = Set<AnyCancellable>()
    private var recordedID: String?
    public init(playback: PlaybackSession, library: LibraryStore) {
        playback.$videoID.sink { [weak self] _ in self?.recordedID = nil }.store(in: &observations)
        playback.$phase.sink { [weak self, weak playback, weak library] phase in
            guard let self, phase == .playing, let playback, let library,
                  let item = playback.currentItemMetadata, self.recordedID != item.contentID else { return }
            self.recordedID = item.contentID
            library.recordPlayback(item)
        }.store(in: &observations)
    }
}
