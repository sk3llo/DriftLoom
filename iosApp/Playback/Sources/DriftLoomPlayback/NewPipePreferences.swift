// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Settings read from NewPipe's `preferences.json`. Every field is optional: only values that
/// have a DriftLoom equivalent and pass validation are carried, and the user applies them explicitly.
public struct MigratedSettings: Equatable, Sendable {
    public var appearance: String?
    public var contentLanguage: String?
    public var contentCountry: String?
    public var recordsSearchHistory: Bool?
    public var recordsWatchHistory: Bool?
    public var resumesPlayback: Bool?
    public var usesSearchSuggestions: Bool?
    public var downloadNetwork: DownloadNetwork?
    /// NewPipe's main tabs in order: built-in sections and pinned channels/online playlists.
    public var homeTabs: [MigratedHomeTab] = []
    public var skippedTabs = 0
    public init() {}
    public var isEmpty: Bool { changes.isEmpty }

    /// Human-readable lines for the import preview.
    public var changes: [String] {
        var lines: [String] = []
        if let appearance { lines.append("Theme: \(appearance)") }
        if let contentLanguage { lines.append("Content language: " + (Locale.current.localizedString(forLanguageCode: contentLanguage) ?? contentLanguage)) }
        if let contentCountry { lines.append("Content region: " + (Locale.current.localizedString(forRegionCode: contentCountry) ?? contentCountry)) }
        if let recordsWatchHistory { lines.append("Record watch history: " + (recordsWatchHistory ? "on" : "off")) }
        if let recordsSearchHistory { lines.append("Record search history: " + (recordsSearchHistory ? "on" : "off")) }
        if let resumesPlayback { lines.append("Resume playback position: " + (resumesPlayback ? "on" : "off")) }
        if let usesSearchSuggestions { lines.append("Search suggestions: " + (usesSearchSuggestions ? "on" : "off")) }
        if let downloadNetwork { lines.append("Download network: " + downloadNetwork.rawValue) }
        if !homeTabs.isEmpty { lines.append("Home tabs: " + homeTabs.map(\.title).joined(separator: ", ")) }
        return lines
    }
}

public enum MigratedHomeTab: Equatable, Sendable {
    case section(HomeSection), pinned(BrowseItem)
    var title: String {
        switch self {
        case let .section(section): return section.rawValue
        case let .pinned(item): return item.title
        }
    }
}

enum NewPipePreferences {
    typealias Object = [String: Any]
    /// NewPipe tab type IDs (`Tab.java`).
    private enum TabID: Int { case blank = 0, subscriptions, feed, bookmarks, history, kiosk, channel, defaultKiosk, playlist, feedGroup }

    static func parse(_ data: Data) throws -> MigratedSettings {
        guard data.count <= 2_000_000, let root = try JSONSerialization.jsonObject(with: data) as? Object else { throw CocoaError(.fileReadCorruptFile) }
        var settings = MigratedSettings()
        switch root["theme"] as? String {
        case "light_theme": settings.appearance = "Light"
        case "dark_theme", "black_theme": settings.appearance = "Dark"
        case "auto_device_theme": settings.appearance = "System"
        default: break
        }
        if let language = root["content_language"] as? String, language != "system" {
            let base = SubtitleSelection.baseLanguage(language.replacingOccurrences(of: "_", with: "-"))
            if Locale.isoLanguageCodes.contains(base) { settings.contentLanguage = base }
        }
        if let country = (root["content_country"] as? String)?.uppercased(), Locale.isoRegionCodes.contains(country) {
            settings.contentCountry = country
        }
        settings.recordsSearchHistory = root["enable_search_history"] as? Bool
        settings.recordsWatchHistory = root["enable_watch_history"] as? Bool
        settings.resumesPlayback = root["enable_playback_resume"] as? Bool
        if let sources = root["show_search_suggestions"] as? [String], sources.count <= 10 {
            settings.usesSearchSuggestions = sources.contains("show_remote_search_suggestions")
        }
        if let cross = root["cross_network_downloads"] as? Bool { settings.downloadNetwork = cross ? .any : .wifiOnly }
        if let raw = root["saved_tabs_key"] as? String, raw.utf8.count <= 200_000 { (settings.homeTabs, settings.skippedTabs) = tabs(raw) }
        return settings
    }

    static func tabs(_ raw: String) -> ([MigratedHomeTab], Int) {
        guard let root = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? Object, let list = root["tabs"] as? [Object], list.count <= 100 else { return ([], 0) }
        var tabs: [MigratedHomeTab] = [], skipped = 0, seen = Set<String>()
        func add(_ tab: MigratedHomeTab) {
            let key: String
            switch tab { case let .section(section): key = section.rawValue; case let .pinned(item): key = item.id }
            if seen.insert(key).inserted { tabs.append(tab) }
        }
        for entry in list {
            switch (entry["tab_id"] as? Int).flatMap(TabID.init(rawValue:)) {
            case .subscriptions: add(.section(.subscriptions))
            case .feed: add(.section(.feed))
            case .bookmarks: add(.section(.bookmarks))
            case .history: add(.section(.history))
            case .defaultKiosk: add(.section(.trending))
            case .kiosk:
                guard entry["service_id"] as? Int == 0, let section = kioskSection(entry["kiosk_id"] as? String) else { skipped += 1; continue }
                add(.section(section))
            case .channel:
                guard entry["channel_service_id"] as? Int == 0, let id = channelID(entry["channel_url"] as? String),
                      let name = entry["channel_name"] as? String, !name.isEmpty, name.count <= 500 else { skipped += 1; continue }
                add(.pinned(BrowseItem(contentID: id, kind: .channel, title: name)))
            case .playlist:
                // Local playlists are keyed by Android database IDs; only online playlists carry over.
                guard entry["playlist_service_id"] as? Int == 0, let id = playlistID(entry["playlist_url"] as? String), !id.hasPrefix("RD"),
                      let name = entry["playlist_name"] as? String, !name.isEmpty, name.count <= 500 else { skipped += 1; continue }
                add(.pinned(BrowseItem(contentID: id, kind: .playlist, title: name)))
            case .blank: continue
            case .feedGroup, .none: skipped += 1
            }
        }
        return (tabs, skipped)
    }

    static func kioskSection(_ id: String?) -> HomeSection? {
        switch id {
        case "Trending", "trending_music": return .trending
        case "live": return .live
        case "trending_gaming": return .gaming
        case "trending_podcasts_episodes": return .podcasts
        case "trending_movies_and_shows": return .trailers
        default: return nil
        }
    }
    private static func channelID(_ value: String?) -> String? {
        guard let value, let url = URLComponents(string: value), url.scheme == "https", ["www.youtube.com", "youtube.com", "m.youtube.com"].contains(url.host ?? "") else { return nil }
        let parts = url.path.split(separator: "/")
        guard parts.count == 2, parts[0] == "channel", String(parts[1]).range(of: "^UC[A-Za-z0-9_-]{22}$", options: .regularExpression) != nil else { return nil }
        return String(parts[1])
    }
    private static func playlistID(_ value: String?) -> String? {
        guard let value, let url = URLComponents(string: value), url.scheme == "https", ["www.youtube.com", "youtube.com", "m.youtube.com"].contains(url.host ?? ""),
              let id = url.queryItems?.first(where: { $0.name == "list" })?.value,
              id.range(of: "^[A-Za-z0-9_-]{2,150}$", options: .regularExpression) != nil else { return nil }
        return id
    }
}
