// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Decides which subscription videos are new since the last background check.
/// The first check only records what exists, so enabling notifications never floods the user.
public struct FeedCheckState: Codable, Equatable, Sendable {
    public var lastCheck: Date?
    /// Recently seen video IDs, newest last, bounded so the state stays small.
    public var seen: [String] = []
    public init() {}
    static let seenLimit = 3000
    /// Only videos this recent can be "new", so a channel's back catalogue never notifies.
    static let window: TimeInterval = 3 * 24 * 3600
}

public enum FeedCheck {
    public struct Result: Equatable, Sendable {
        public let newVideos: [FeedVideo]
        public let state: FeedCheckState
    }
    public static func evaluate(_ videos: [FeedVideo], state: FeedCheckState, now: Date = Date()) -> Result {
        var next = state
        let known = Set(state.seen)
        var unique = Set<String>()
        let fresh = videos.filter { unique.insert($0.item.contentID).inserted }.sorted { $0.published > $1.published }
        let new = state.lastCheck == nil ? [] : fresh.filter {
            !known.contains($0.item.contentID) && $0.published > now.addingTimeInterval(-FeedCheckState.window) && $0.published <= now.addingTimeInterval(3600)
        }
        next.seen = Array((state.seen.filter { !unique.contains($0) } + fresh.reversed().map(\.item.contentID)).suffix(FeedCheckState.seenLimit))
        next.lastCheck = now
        return Result(newVideos: new, state: next)
    }

    /// Notification text: one per video for a few, otherwise a summary.
    public static func messages(for videos: [FeedVideo]) -> [(title: String, body: String, videoID: String?)] {
        guard !videos.isEmpty else { return [] }
        if videos.count <= 3 {
            return videos.map { (title: $0.item.subtitle.isEmpty ? L("New video") : $0.item.subtitle, body: $0.item.title, videoID: $0.item.contentID) }
        }
        let channels = Set(videos.map(\.item.subtitle)).filter { !$0.isEmpty }.sorted()
        let shown = Array(channels.prefix(3)) + (channels.count > 3 ? [L("\(channels.count - 3) more channels")] : [])
        let names = ListFormatter.localizedString(byJoining: shown)
        return [(title: L("\(videos.count) new videos"), body: names.isEmpty ? L("From your subscriptions") : L("From \(names)"), videoID: nil)]
    }

    /// Fetch the latest uploads of up to `limit` subscriptions, a few channels at a time.
    public static func fetch(channelIDs: [String], client: any FeedLoading = YouTubeFeedClient(), limit: Int = 150) async -> (videos: [FeedVideo], failed: Int) {
        var seen = Set<String>(), videos: [FeedVideo] = [], failed = 0
        let ids = Array(channelIDs.filter { seen.insert($0).inserted }.prefix(limit))
        for offset in stride(from: 0, to: ids.count, by: 4) {
            if Task.isCancelled { break }
            let batch = ids[offset..<min(offset + 4, ids.count)]
            let results = await withTaskGroup(of: [FeedVideo]?.self, returning: [[FeedVideo]?].self) { group in
                for id in batch { group.addTask { try? await client.videos(channelID: id) } }
                var all: [[FeedVideo]?] = []
                for await result in group { all.append(result) }
                return all
            }
            failed += results.filter { $0 == nil }.count
            videos += results.compactMap { $0 }.flatMap { $0 }
        }
        return (videos, failed)
    }
}
