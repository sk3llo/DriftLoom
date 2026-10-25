// SPDX-License-Identifier: GPL-3.0-or-later
import AVFoundation
import Combine
import Foundation

public struct QueueEntry: Identifiable, Equatable {
    public let id: UUID
    public let item: BrowseItem
    public init(item: BrowseItem) { id = UUID(); self.item = item }
}

public enum QueueRepeat: String, CaseIterable { case off = "Off", all = "All", one = "One" }

@MainActor
public final class PlaybackQueue: ObservableObject {
    @Published public private(set) var entries: [QueueEntry] = []
    @Published public private(set) var currentID: UUID?
    @Published public var repeatMode = QueueRepeat.off
    @Published public var shuffled = false {
        didSet { rebuildShuffleOrder() }
    }
    public let playback: PlaybackSession
    private var endObserver: NSObjectProtocol?
    private var shuffleOrder: [UUID] = []
    public var currentIndex: Int? { entries.firstIndex { $0.id == currentID } }
    private var order: [UUID] { shuffled ? shuffleOrder : entries.map(\.id) }
    public var canGoNext: Bool { entries.count > 1 && (repeatMode == .all || (order.firstIndex(of: currentID ?? UUID()) ?? 0) < entries.count - 1) }
    public var canGoPrevious: Bool { (order.firstIndex(of: currentID ?? UUID()) ?? 0) > 0 || (repeatMode == .all && entries.count > 1) }

    public init(playback: PlaybackSession) {
        self.playback = playback
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
        guard videos.indices.contains(index) else { return }
        entries = videos.map(QueueEntry.init)
        select(entries[index].id)
        rebuildShuffleOrder()
    }
    public func enqueue(_ item: BrowseItem, next: Bool = false) {
        guard item.kind == .video, (try? VideoRequest(input: item.contentID).videoID) == item.contentID else { return }
        if entries.isEmpty { start([item]); return }
        let entry = QueueEntry(item: item)
        if next, let index = currentIndex { entries.insert(entry, at: index + 1) }
        else { entries.append(entry) }
        if shuffled {
            if next, let currentID, let index = shuffleOrder.firstIndex(of: currentID) { shuffleOrder.insert(entry.id, at: index + 1) }
            else { shuffleOrder.append(entry.id) }
        }
    }
    public func select(_ id: UUID) {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        currentID = id
        playback.open(entry.item)
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
    }
    public func move(from offsets: IndexSet, to destination: Int) {
        guard destination >= 0, destination <= entries.count, offsets.allSatisfy({ entries.indices.contains($0) }) else { return }
        let moving = offsets.sorted().map { entries[$0] }
        var remaining = entries.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        remaining.insert(contentsOf: moving, at: destination - offsets.filter { $0 < destination }.count)
        entries = remaining
    }
    public func didFinishCurrent() {
        guard currentID != nil else { return }
        if repeatMode == .one { playback.retry() }
        else { next() }
    }
    public func stop() { playback.stop(); entries = []; currentID = nil; shuffleOrder = [] }
    private func rebuildShuffleOrder() {
        guard shuffled else { shuffleOrder = []; return }
        shuffleOrder = currentID.map { [$0] } ?? []
        shuffleOrder.append(contentsOf: entries.map(\.id).filter { $0 != currentID }.shuffled())
    }
}
