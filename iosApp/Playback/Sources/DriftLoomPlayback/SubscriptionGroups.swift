// SPDX-License-Identifier: GPL-3.0-or-later
import Combine
import Foundation

public struct SubscriptionGroup: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var channelIDs: [String]
    public init(id: UUID = UUID(), name: String, channelIDs: [String] = []) {
        self.id = id; self.name = name; self.channelIDs = channelIDs
    }
}
struct SubscriptionGroupDocument: Codable {
    var version = 1
    var groups: [SubscriptionGroup] = []
}

@MainActor
public final class SubscriptionGroups: ObservableObject {
    @Published public private(set) var groups: [SubscriptionGroup] = []
    @Published public private(set) var error: String?
    @Published public private(set) var isWritable = false
    public let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL; reload() }
    public func reload() {
        do {
            let bytes = try Data(contentsOf: fileURL)
            guard bytes.count <= 2_000_000 else { throw CocoaError(.fileReadCorruptFile) }
            let document = try JSONDecoder().decode(SubscriptionGroupDocument.self, from: bytes)
            guard Self.valid(document) else { throw CocoaError(.fileReadCorruptFile) }
            groups = document.groups; isWritable = true; error = nil
        } catch let issue as CocoaError where issue.code == .fileReadNoSuchFile {
            groups = []; isWritable = true; error = nil
        } catch { isWritable = false; self.error = "Your subscription groups couldn't be read. The saved file has been left untouched." }
    }
    @discardableResult
    public func upsert(id: UUID = UUID(), name: String, channelIDs: [String]) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let group = SubscriptionGroup(id: id, name: name, channelIDs: Array(Set(channelIDs)).sorted())
        var next = groups
        if let index = next.firstIndex(where: { $0.id == id }) { next[index] = group }
        else { next.append(group) }
        return save(next)
    }
    public func remove(_ id: UUID) { _ = save(groups.filter { $0.id != id }) }
    public func move(from offsets: IndexSet, to destination: Int) {
        guard (0...groups.count).contains(destination), offsets.allSatisfy({ groups.indices.contains($0) }) else { return }
        let moving = offsets.sorted().map { groups[$0] }
        var next = groups.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        next.insert(contentsOf: moving, at: destination - offsets.filter { $0 < destination }.count)
        _ = save(next)
    }
    /// Unsubscribed members are ignored without destroying their saved membership.
    public func channelIDs(for id: UUID?, subscribed: [String]) -> [String] {
        guard let id else { return subscribed }
        guard let group = groups.first(where: { $0.id == id }) else { return [] }
        let members = Set(group.channelIDs)
        return subscribed.filter { members.contains($0) }
    }
    public func blockForRecovery(_ message: String) { isWritable = false; error = message }
    public func dismissError() { error = nil }
    func snapshot() throws -> SubscriptionGroupDocument {
        guard isWritable else { throw CocoaError(.fileReadCorruptFile) }
        return SubscriptionGroupDocument(groups: groups)
    }
    static func valid(_ document: SubscriptionGroupDocument) -> Bool {
        document.version == 1 && document.groups.count <= 100
            && Set(document.groups.map(\.id)).count == document.groups.count
            && document.groups.allSatisfy { group in
                !group.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && group.name.count <= 100
                    && group.channelIDs.count <= 5000 && Set(group.channelIDs).count == group.channelIDs.count
                    && group.channelIDs.allSatisfy { $0.range(of: "^UC[A-Za-z0-9_-]{22}$", options: .regularExpression) != nil }
            }
    }
    private func save(_ next: [SubscriptionGroup]) -> Bool {
        guard isWritable else { return false }
        let document = SubscriptionGroupDocument(groups: next)
        guard Self.valid(document) else { error = "Use a name of 1–100 characters, up to 100 groups and up to 5,000 channels per group."; return false }
        do {
            let bytes = try JSONEncoder().encode(document)
            guard bytes.count <= 2_000_000 else { throw CocoaError(.fileWriteOutOfSpace) }
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            var options: Data.WritingOptions = .atomic
#if os(iOS)
            options.insert(.completeFileProtectionUntilFirstUserAuthentication)
#endif
            try bytes.write(to: fileURL, options: options)
            groups = next; error = nil; return true
        } catch { self.error = "Your subscription groups couldn't be saved. Previous data is unchanged."; return false }
    }
}

public enum FeedPeriod: String, CaseIterable, Identifiable {
    case all = "All recent uploads", today = "Last 24 hours", week = "Last 7 days", month = "Last 30 days"
    public var id: String { rawValue }
    public var interval: TimeInterval? {
        switch self { case .all: return nil; case .today: return 86400; case .week: return 7 * 86400; case .month: return 30 * 86400 }
    }
}

public enum FeedFilter {
    public static func apply(_ items: [FeedVideo], period: FeedPeriod, hidingWatched: Bool, watchedIDs: Set<String>, now: Date = Date()) -> [FeedVideo] {
        items.filter { entry in
            (!hidingWatched || !watchedIDs.contains(entry.item.contentID))
                && (period.interval.map { entry.published >= now.addingTimeInterval(-$0) } ?? true)
        }
    }
}
