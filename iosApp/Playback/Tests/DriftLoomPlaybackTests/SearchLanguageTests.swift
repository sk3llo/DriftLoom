// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import DriftLoomPlayback

final class SearchLanguageTests: XCTestCase {
    func testTitlesAreAskedForInTheQuerysLanguage() {
        XCTAssertEqual(YouTubeBrowsingClient.queryLanguage("receita de bolo de chocolate", preferring: "en"), "pt")
        XCTAssertEqual(YouTubeBrowsingClient.queryLanguage("борщ", preferring: "uk-UA"), "uk", "Ambiguous Cyrillic follows a Ukrainian interface")
        XCTAssertEqual(YouTubeBrowsingClient.queryLanguage("рецепт борщу", preferring: "pt-BR"), "uk")
        XCTAssertNil(YouTubeBrowsingClient.queryLanguage("lofi music", preferring: "en"), "English queries change nothing for an English interface")
        XCTAssertEqual(YouTubeBrowsingClient.queryLanguage("рецепт шоколадного торта"), YouTubeBrowsingClient.queryLanguage("рецепт шоколадного торта"))
        XCTAssertNotNil(YouTubeBrowsingClient.queryLanguage("смачний борщ з пампушками"))
        let english = ContentLocale(language: "en", country: "PT")
        XCTAssertEqual(YouTubeBrowsingClient.acceptLanguage(english), "en-PT,en;q=0.9")
        XCTAssertEqual(YouTubeBrowsingClient.acceptLanguage(english.titles(in: "pt")), "pt,en-PT;q=0.8,en;q=0.7")
        XCTAssertEqual(YouTubeBrowsingClient.acceptLanguage(english.titles(in: "en")), "en-PT,en;q=0.9", "Same language adds nothing")
        XCTAssertNil(english.titles(in: "not-a-language").titleLanguage)
    }
}
