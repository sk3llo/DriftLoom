// SPDX-License-Identifier: GPL-3.0-or-later
import AVFoundation
import Combine
import Foundation

public struct QueueEntry: Identifiable, Equatable, Codable {
    public let id: UUID
    public let item: BrowseItem
    public init(item: BrowseItem) { id = UUID(); self.item = item }
}

public enum QueueRepeat: String, CaseIterable, Codable { case off = "Off", all = "All", one = "One" }

@MainActor
public final class PlaybackQueue: ObservableObject {
    @Published public private(set) var entries: [QueueEntry] = []
    @Published public private(set) var currentID: UUID?
    @Published public private(set) var storageError: String?
    @Published public var repeatMode = QueueRepeat.off { didSet { save() } }
    @Published public var shuffled = false {
        didSet { rebuildShuffleOrder(); save() }
    }
    public let playback: PlaybackSession
    private var endObserver: NSObjectProtocol?
    private var observations = Set<AnyCancellable>()
    private var shuffleOrder: [UUID] = []
    private let archiveURL: URL?
    private var restoring = false
    private var writable = true
    private struct Archive: Codable {
        var version = 1
        let entries: [QueueEntry]
        let currentID: UUID?
        let repeatMode: QueueRepeat
        let shuffled: Bool
        let order: [UUID]
        let rate: Float?
        let maximumHeight: Int?
    }
    public var currentIndex: Int? { entries.firstIndex { $0.id == currentID } }
    private var order: [UUID] { shuffled ? shuffleOrder : entries.map(\.id) }
    public var canGoNext: Bool { entries.count > 1 && (repeatMode == .all || (order.firstIndex(of: currentID ?? UUID()) ?? 0) < entries.count - 1) }
    public var canGoPrevious: Bool { (order.firstIndex(of: currentID ?? UUID()) ?? 0) > 0 || (repeatMode == .all && entries.count > 1) }

    public init(playback: PlaybackSession, archiveURL: URL? = nil) {
        self.playback = playback
        self.archiveURL = archiveURL
        restore()
        playback.$playbackRate.combineLatest(playback.$maximumHeight).dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.save() }.store(in: &observations)
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] notification in
            // Capture a stable identity, rather than retaining an AVPlayerItem across actor hops.
            let ended = (notification.object as? AVPlayerItem).map(ObjectIdentifier.init)
            Task { @MainActor [weak self] in
                guard let self, let ended, let current = self.playback.player.currentItem,
                      ObjectIdentifier(current) == ended else { return }
                self.didFinishCurrent()
            }
        }
    }
    deinit { if let endObserver { NotificationCenter.default.removeObserver(endObserver) } }

    public func start(_ items: [BrowseItem], at index: Int = 0) {
        let videos = items.filter { $0.kind == .video && (try? VideoRequest(input: $0.contentID).videoID) == $0.contentID }
        guard videos.count <= 5000 else { storageError = "A queue can contain up to 5,000 videos."; return }
        guard videos.indices.contains(index) else { return }
        entries = videos.map(QueueEntry.init)
        select(entries[index].id)
        rebuildShuffleOrder()
        save()
    }
    public func enqueue(_ item: BrowseItem, next: Bool = false) {
        guard item.kind == .video, (try? VideoRequest(input: item.contentID).videoID) == item.contentID else { return }
        guard entries.count < 5000 else { storageError = "A queue can contain up to 5,000 videos."; return }
        if entries.isEmpty { start([item]); return }
        let entry = QueueEntry(item: item)
        if next, let index = currentIndex { entries.insert(entry, at: index + 1) }
        else { entries.append(entry) }
        if shuffled {
            if next, let currentID, let index = shuffleOrder.firstIndex(of: currentID) { shuffleOrder.insert(entry.id, at: index + 1) }
            else { shuffleOrder.append(entry.id) }
        }
        save()
    }
    public func select(_ id: UUID) {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        currentID = id
        playback.open(entry.item)
        save()
    }
    public func next() {
        guard let currentID, let index = order.firstIndex(of: currentID) else { return }
        if index + 1 < order.count { select(order[index + 1]) }
        else if repeatMode == .all, let first = order.first { select(first) }
    }
    public func previous() {
        guard let currentID, let index = order.firstIndex(of: currentID) else { return }
        if index > 0 { select(order[index - 1]) }
        else if repeatMode == .all, let last = order.last { select(last) }
    }
    public func remove(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let wasCurrent = currentID == id
        let playbackIndex = order.firstIndex(of: id) ?? 0
        entries.remove(at: index)
        shuffleOrder.removeAll { $0 == id }
        if entries.isEmpty { stop() }
        else if wasCurrent { select(order[min(playbackIndex, order.count - 1)]) }
        save()
    }
    public func move(from offsets: IndexSet, to destination: Int) {
        guard destination >= 0, destination <= entries.count, offsets.allSatisfy({ entries.indices.contains($0) }) else { return }
        let moving = offsets.sorted().map { entries[$0] }
        var remaining = entries.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        remaining.insert(contentsOf: moving, at: destination - offsets.filter { $0 < destination }.count)
        entries = remaining
        save()
    }
    public func didFinishCurrent() {
        guard currentID != nil else { return }
        if repeatMode == .one { playback.retry() }
        else { next() }
    }
    public func stop() { playback.stop(); entries = []; currentID = nil; shuffleOrder = []; save() }
    public func dismissStorageError() { storageError = nil }
    private func restore() {
        guard let archiveURL, FileManager.default.fileExists(atPath: archiveURL.path) else { return }
        restoring = true
        defer { restoring = false }
        do {
            let data = try Data(contentsOf: archiveURL)
            guard data.count < 8_000_000 else { throw CocoaError(.fileReadCorruptFile) }
            let value = try JSONDecoder().decode(Archive.self, from: data)
            let ids = Set(value.entries.map(\.id))
            guard value.version == 1, value.entries.count <= 5000, ids.count == value.entries.count,
                  value.entries.allSatisfy({ $0.item.kind == .video && (try? VideoRequest(input: $0.item.contentID).videoID) == $0.item.contentID }),
                  (value.entries.isEmpty && value.currentID == nil) || value.currentID.map(ids.contains) == true,
                  Set(value.order) == ids, value.order.count == ids.count else { throw CocoaError(.fileReadCorruptFile) }
            playback.setPlaybackRate(value.rate ?? 1); playback.setMaximumHeight(value.maximumHeight ?? 0)
            entries = value.entries; currentID = value.currentID; repeatMode = value.repeatMode
            shuffled = value.shuffled; shuffleOrder = value.order
            if let item = entries.first(where: { $0.id == currentID })?.item { playback.prepare(item) }
        } catch { writable = false; storageError = "Your saved queue couldn't be read and has been left untouched. The current queue will not be saved." }
    }
    private func save() {
        guard !restoring, writable, let archiveURL else { return }
        do {
            guard entries.count <= 5000 else { throw CocoaError(.fileWriteOutOfSpace) }
            let value = Archive(entries: entries, currentID: currentID, repeatMode: repeatMode, shuffled: shuffled, order: order, rate: playback.playbackRate, maximumHeight: playback.maximumHeight)
            let data = try JSONEncoder().encode(value)
            try FileManager.default.createDirectory(at: archiveURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            var options: Data.WritingOptions = .atomic
#if os(iOS)
            options.insert(.completeFileProtectionUntilFirstUserAuthentication)
#endif
            try data.write(to: archiveURL, options: options)
        } catch { storageError = "Your current queue couldn't be saved. The previously saved queue is unchanged." }
    }
    private func rebuildShuffleOrder() {
        guard shuffled else { shuffleOrder = []; return }
        shuffleOrder = currentID.map { [$0] } ?? []
        shuffleOrder.append(contentsOf: entries.map(\.id).filter { $0 != currentID }.shuffled())
    }
}
