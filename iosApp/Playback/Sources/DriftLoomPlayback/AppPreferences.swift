// SPDX-License-Identifier: GPL-3.0-or-later
import Combine
import Foundation

public enum HomeSection: String, CaseIterable, Identifiable, Codable, Sendable {
    case subscriptions = "Subscriptions", feed = "What's new", bookmarks = "Bookmarked", history = "History", trending = "Trending music"
    case live = "Live", gaming = "Gaming", podcasts = "Podcasts", trailers = "Movie trailers"
    case soundCloud = "SoundCloud trending"
    public var id: String { rawValue }
    /// Shown on a fresh install, Live first; the other kiosks are opt-in from the drawer or settings.
    public static let defaultSections: [HomeSection] = [.live, .subscriptions, .feed, .bookmarks, .history, .trending]
    /// The YouTube page behind a kiosk section.
    public var kiosk: YouTubeKiosk? {
        switch self {
        case .live: return .live
        case .gaming: return .gaming
        case .podcasts: return .podcasts
        case .trailers: return .trailers
        default: return nil
        }
    }
    public var symbol: String {
        switch self {
        case .subscriptions: return "person.crop.circle"
        case .feed: return "tray"
        case .bookmarks: return "bookmark"
        case .history: return "clock"
        case .trending: return "chart.line.uptrend.xyaxis"
        case .live: return "dot.radiowaves.left.and.right"
        case .gaming: return "gamecontroller"
        case .podcasts: return "mic"
        case .trailers: return "film"
        case .soundCloud: return "waveform"
        }
    }
}

@MainActor
public final class AppPreferences: ObservableObject {
    @Published public private(set) var homeSections: [HomeSection]
    /// True when this launch moved Live to the front of an existing saved layout (done once).
    public private(set) var movedLiveFirst = false
    @Published public private(set) var searchHistory: [String]
    @Published public private(set) var usesSearchSuggestions: Bool
    @Published public private(set) var recordsSearchHistory: Bool
    @Published public private(set) var appearance: String
    @Published public private(set) var contentLocale: ContentLocale
    @Published public private(set) var resumesPlayback: Bool
    @Published public private(set) var feedPeriod: FeedPeriod
    @Published public private(set) var hidesWatchedFeed: Bool
    @Published public private(set) var downloadNetwork: DownloadNetwork
    /// Base language for automatic subtitles; nil means subtitles start off.
    @Published public private(set) var subtitleLanguage: String?
    @Published public private(set) var subtitleSize: SubtitleSize
    /// Fall back to YouTube's machine translation when no subtitles exist in the chosen language.
    @Published public private(set) var translatesSubtitles: Bool
    /// Check subscriptions in the background and notify about new uploads.
    @Published public private(set) var notifiesNewVideos: Bool
    /// Play a related video when the queue ends.
    @Published public private(set) var autoplaysRelated: Bool
    /// Default resolution caps (0 = automatic); a choice in the player overrides them for one video.
    @Published public private(set) var wifiMaximumHeight: Int
    @Published public private(set) var mobileMaximumHeight: Int
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        downloadNetwork = defaults.string(forKey: "downloadNetwork").flatMap(DownloadNetwork.init(rawValue:)) ?? .wifiOnly
        subtitleLanguage = defaults.string(forKey: "subtitleLanguage").flatMap(Self.validLanguage)
        subtitleSize = defaults.string(forKey: "subtitleSize").flatMap(SubtitleSize.init(rawValue:)) ?? .medium
        translatesSubtitles = defaults.bool(forKey: "translatesSubtitles")
        notifiesNewVideos = defaults.bool(forKey: "notifiesNewVideos")
        autoplaysRelated = defaults.object(forKey: "autoplaysRelated") as? Bool ?? true
        wifiMaximumHeight = PlaybackSession.resolutionChoices.contains(defaults.integer(forKey: "wifiMaximumHeight")) ? defaults.integer(forKey: "wifiMaximumHeight") : 0
        mobileMaximumHeight = PlaybackSession.resolutionChoices.contains(defaults.integer(forKey: "mobileMaximumHeight")) ? defaults.integer(forKey: "mobileMaximumHeight") : 0
        feedPeriod = defaults.string(forKey: "feedPeriod").flatMap(FeedPeriod.init(rawValue:)) ?? .all
        hidesWatchedFeed = defaults.bool(forKey: "hidesWatchedFeed")
        contentLocale = .current(defaults: defaults)
        let saved = defaults.stringArray(forKey: "homeSections")?.compactMap(HomeSection.init(rawValue:)) ?? HomeSection.defaultSections
        var seen = Set<HomeSection>()
        let valid = saved.filter { seen.insert($0).inserted }
        var sections = valid.isEmpty ? HomeSection.defaultSections : valid
        // One-time update: Live becomes the first tab in layouts saved before it was the default.
        var moved = false
        if !defaults.bool(forKey: "liveFirst.v1") {
            defaults.set(true, forKey: "liveFirst.v1")
            if defaults.stringArray(forKey: "homeSections") != nil, sections.first != .live {
                sections = [.live] + sections.filter { $0 != .live }
                defaults.set(sections.map(\.rawValue), forKey: "homeSections")
                moved = true
            }
        }
        homeSections = sections
        movedLiveFirst = moved
        var queries = Set<String>()
        searchHistory = Array((defaults.stringArray(forKey: "searchHistory") ?? []).filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 500 && queries.insert($0).inserted
        }.prefix(50))
        usesSearchSuggestions = defaults.object(forKey: "usesSearchSuggestions") as? Bool ?? true
        recordsSearchHistory = defaults.object(forKey: "recordsSearchHistory") as? Bool ?? true
        resumesPlayback = defaults.object(forKey: "resumesPlayback") as? Bool ?? true
        let savedAppearance = defaults.string(forKey: "appearance") ?? "System"
        appearance = ["System", "Light", "Dark"].contains(savedAppearance) ? savedAppearance : "System"
    }
    public func setDownloadNetwork(_ network: DownloadNetwork) {
        downloadNetwork = network; defaults.set(network.rawValue, forKey: "downloadNetwork")
    }
    public func setSubtitleLanguage(_ language: String?) {
        subtitleLanguage = language.flatMap(Self.validLanguage)
        defaults.set(subtitleLanguage ?? "", forKey: "subtitleLanguage")
    }
    public func setAutoplaysRelated(_ enabled: Bool) {
        autoplaysRelated = enabled; defaults.set(enabled, forKey: "autoplaysRelated")
    }
    public func setMaximumHeight(_ height: Int, mobile: Bool) {
        guard PlaybackSession.resolutionChoices.contains(height) else { return }
        if mobile { mobileMaximumHeight = height } else { wifiMaximumHeight = height }
        defaults.set(height, forKey: mobile ? "mobileMaximumHeight" : "wifiMaximumHeight")
    }
    public func setNotifiesNewVideos(_ enabled: Bool) {
        notifiesNewVideos = enabled; defaults.set(enabled, forKey: "notifiesNewVideos")
    }
    public func setTranslatesSubtitles(_ enabled: Bool) {
        translatesSubtitles = enabled; defaults.set(enabled, forKey: "translatesSubtitles")
    }
    public func setSubtitleSize(_ size: SubtitleSize) {
        subtitleSize = size; defaults.set(size.rawValue, forKey: "subtitleSize")
    }
    private static func validLanguage(_ code: String) -> String? {
        let base = SubtitleSelection.baseLanguage(code)
        return Locale.isoLanguageCodes.contains(base) ? base : nil
    }
    public func setFeedPeriod(_ value: FeedPeriod) {
        feedPeriod = value; defaults.set(value.rawValue, forKey: "feedPeriod")
    }
    public func setHidesWatchedFeed(_ value: Bool) {
        hidesWatchedFeed = value; defaults.set(value, forKey: "hidesWatchedFeed")
    }
    public func setContentLocale(language: String, country: String) {
        let locale = ContentLocale(language: language, country: country)
        contentLocale = locale
        defaults.set(locale.language, forKey: "contentLanguage"); defaults.set(locale.country, forKey: "contentCountry")
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
    public func setUsesSearchSuggestions(_ enabled: Bool) {
        usesSearchSuggestions = enabled; defaults.set(enabled, forKey: "usesSearchSuggestions")
    }
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
