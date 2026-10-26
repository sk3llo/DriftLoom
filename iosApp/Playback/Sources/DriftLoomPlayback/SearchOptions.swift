// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public enum SearchOrder: String, CaseIterable, Sendable { case relevance = "Relevance", uploaded = "Upload date", views = "View count", rating = "Rating" }
public enum SearchDate: String, CaseIterable, Sendable { case any = "Any time", hour = "Last hour", today = "Today", week = "This week", month = "This month", year = "This year" }
public enum SearchDuration: String, CaseIterable, Sendable { case any = "Any duration", short = "Under 4 minutes", medium = "4–20 minutes", long = "Over 20 minutes" }
public struct SearchOptions: Hashable, Sendable {
    public let type: SearchFilter
    public let order: SearchOrder
    public let date: SearchDate
    public let duration: SearchDuration
    public init(type: SearchFilter = .all, order: SearchOrder = .relevance, date: SearchDate = .any, duration: SearchDuration = .any) {
        self.type = type; self.order = order; self.date = date; self.duration = duration
    }
    public var parameter: String? {
        let sort: UInt8 = order == .relevance ? 0 : order == .uploaded ? 2 : order == .views ? 3 : 1
        let upload = UInt8(SearchDate.allCases.firstIndex(of: date) ?? 0)
        let kind = UInt8(SearchFilter.allCases.firstIndex(of: type) ?? 0)
        let length: UInt8 = duration == .any ? 0 : duration == .short ? 1 : duration == .medium ? 3 : 2
        var filters: [UInt8] = [], result: [UInt8] = []
        if upload > 0 { filters += [0x08, upload] }
        if kind > 0 { filters += [0x10, kind] }
        // Video duration has no meaning for channel or playlist results.
        if length > 0, type == .videos || type == .all { filters += [0x18, length] }
        if sort > 0 { result += [0x08, sort] }
        if !filters.isEmpty { result += [0x12, UInt8(filters.count)] + filters }
        return result.isEmpty ? nil : Data(result).base64EncodedString()
    }
}

public struct ContentLocale: Equatable, Sendable {
    public let language: String
    public let country: String
    public init(language: String = "en", country: String = "PT") {
        self.language = Locale.isoLanguageCodes.contains(language) ? language : "en"
        self.country = Locale.isoRegionCodes.contains(country) ? country : "PT"
    }
    public static func current(defaults: UserDefaults = .standard) -> ContentLocale {
        ContentLocale(language: defaults.string(forKey: "contentLanguage") ?? "en", country: defaults.string(forKey: "contentCountry") ?? "PT")
    }
}
