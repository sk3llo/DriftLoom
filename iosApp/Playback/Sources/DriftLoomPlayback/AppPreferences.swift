// SPDX-License-Identifier: GPL-3.0-or-later
import Combine
import Foundation

public enum HomeSection: String, CaseIterable, Identifiable, Codable {
    case subscriptions = "Subscriptions", feed = "What's new", bookmarks = "Bookmarked", history = "History"
    public var id: String { rawValue }
    public var symbol: String {
        switch self {
        case .subscriptions: return "person.crop.circle"
        case .feed: return "tray"
        case .bookmarks: return "bookmark"
        case .history: return "clock"
        }
    }
}

@MainActor
public final class AppPreferences: ObservableObject {
    @Published public private(set) var homeSections: [HomeSection]
    @Published public private(set) var searchHistory: [String]
    @Published public private(set) var recordsSearchHistory: Bool
    @Published public private(set) var appearance: String
    @Published public private(set) var resumesPlayback: Bool
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.stringArray(forKey: "homeSections")?.compactMap(HomeSection.init(rawValue:)) ?? HomeSection.allCases
        var seen = Set<HomeSection>()
        let valid = saved.filter { seen.insert($0).inserted }
        homeSections = valid.isEmpty ? HomeSection.allCases : valid
        var queries = Set<String>()
        searchHistory = Array((defaults.stringArray(forKey: "searchHistory") ?? []).filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 500 && queries.insert($0).inserted
        }.prefix(50))
        recordsSearchHistory = defaults.object(forKey: "recordsSearchHistory") as? Bool ?? true
        resumesPlayback = defaults.object(forKey: "resumesPlayback") as? Bool ?? true
        let savedAppearance = defaults.string(forKey: "appearance") ?? "System"
        appearance = ["System", "Light", "Dark"].contains(savedAppearance) ? savedAppearance : "System"
    }
    public func setHomeSections(_ sections: [HomeSection]) {
        var seen = Set<HomeSection>()
        let valid = sections.filter { seen.insert($0).inserted }
        guard !valid.isEmpty else { return }
        homeSections = valid; defaults.set(valid.map(\.rawValue), forKey: "homeSections")
    }
    public func recordSearch(_ input: String) {
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard recordsSearchHistory, !query.isEmpty, query.count <= 500 else { return }
        searchHistory.removeAll { $0 == query }; searchHistory.insert(query, at: 0)
        searchHistory = Array(searchHistory.prefix(50)); defaults.set(searchHistory, forKey: "searchHistory")
    }
    public func removeSearch(_ query: String) {
        searchHistory.removeAll { $0 == query }; defaults.set(searchHistory, forKey: "searchHistory")
    }
    public func clearSearchHistory() { searchHistory = []; defaults.set([], forKey: "searchHistory") }
    public func setRecordsSearchHistory(_ enabled: Bool) {
        recordsSearchHistory = enabled; defaults.set(enabled, forKey: "recordsSearchHistory")
    }
    public func setAppearance(_ value: String) {
        guard ["System", "Light", "Dark"].contains(value) else { return }
        appearance = value; defaults.set(value, forKey: "appearance")
    }
    public func setResumesPlayback(_ enabled: Bool) {
        resumesPlayback = enabled; defaults.set(enabled, forKey: "resumesPlayback")
    }
}
