// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import DriftLoomPlayback

final class SearchOptionsTests: XCTestCase {
    func testTypeFiltersMatchExistingWireValuesAndCombinedFieldsEncode() {
        XCTAssertNil(SearchOptions().parameter)
        for filter in SearchFilter.allCases { XCTAssertEqual(SearchOptions(type: filter).parameter, filter.parameter) }
        let parameter = SearchOptions(type: .videos, order: .views, date: .year, duration: .short).parameter!
        XCTAssertEqual(Array(Data(base64Encoded: parameter)!), [8, 3, 18, 6, 8, 5, 16, 1, 24, 1])
        XCTAssertEqual(SearchOptions(type: .channels, duration: .long).parameter, SearchFilter.channels.parameter)
    }
    func testInvalidLocaleFallsBackWithoutPassingArbitraryQueryValues() {
        XCTAssertEqual(ContentLocale(language: "bad&hl=xxx", country: "bad"), ContentLocale(language: "en", country: "PT"))
        XCTAssertEqual(ContentLocale(language: "pt", country: "BR").country, "BR")
    }
}

@MainActor
final class ContentPreferencesTests: XCTestCase {
    func testLocalePersistsInTheProvidedDefaults() {
        let suite = "DriftLoom.Tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.setContentLocale(language: "pt", country: "PT")
        XCTAssertEqual(AppPreferences(defaults: defaults).contentLocale, ContentLocale(language: "pt", country: "PT"))
    }
}
