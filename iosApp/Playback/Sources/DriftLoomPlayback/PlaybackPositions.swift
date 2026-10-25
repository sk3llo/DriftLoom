// SPDX-License-Identifier: GPL-3.0-or-later
import Combine
import Foundation

/// Bounded resume metadata only; media URLs are never stored.
@MainActor
public final class PlaybackPositions: ObservableObject {
    private struct Position: Codable {
        let seconds: Double
        let duration: Double
        let updated: Date
    }
    private let defaults: UserDefaults
    private var positions: [String: Position]
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let decoded = defaults.data(forKey: "playbackPositions").flatMap { try? JSONDecoder().decode([String: Position].self, from: $0) } ?? [:]
        positions = decoded.filter {
            (try? VideoRequest(input: $0.key).videoID) == $0.key && $0.value.seconds.isFinite
                && $0.value.duration.isFinite && $0.value.duration > 0
                && $0.value.seconds >= 5 && $0.value.seconds < $0.value.duration - 10
                && $0.value.updated.timeIntervalSince1970.isFinite
        }
        positions = Dictionary(uniqueKeysWithValues: positions.sorted { $0.value.updated > $1.value.updated }.prefix(500).map { ($0.key, $0.value) })
    }
    public func seconds(for id: String) -> Double? { positions[id]?.seconds }
    public func record(id: String, seconds: Double, duration: Double) {
        guard (try? VideoRequest(input: id).videoID) == id, seconds.isFinite, duration.isFinite, duration > 0 else { return }
        if seconds < 5 || seconds >= duration - 10 { positions.removeValue(forKey: id) }
        else { positions[id] = Position(seconds: seconds, duration: duration, updated: Date()) }
        positions = Dictionary(uniqueKeysWithValues: positions.sorted { $0.value.updated > $1.value.updated }.prefix(500).map { ($0.key, $0.value) })
        persist()
    }
    public func retainOnly(_ ids: Set<String>) {
        positions = positions.filter { ids.contains($0.key) }; persist()
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(positions) { defaults.set(data, forKey: "playbackPositions") }
    }
}
