// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

/// Walks the main screens and saves a screenshot of each, for reviewing translations and text fitting.
/// Runs only when TEST_RUNNER_TOUR_DIR is set; TEST_RUNNER_TOUR_LANG picks the app language (en, uk, pt).
final class ScreenshotTour: XCTestCase {
    private var directory: URL!
    private var app: XCUIApplication!
    private var count = 0

    override func setUpWithError() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["TOUR_DIR"] else { throw XCTSkip("Set TEST_RUNNER_TOUR_DIR to take the screenshot tour") }
        let language = environment["TOUR_LANG"] ?? "en"
        directory = URL(fileURLWithPath: path).appendingPathComponent(language)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["--library-smoke-run", "tour-" + UUID().uuidString, "--library-smoke-seed",
                               "-AppleLanguages", "(\(language))", "-AppleLocale", language == "uk" ? "uk_UA" : language == "pt" ? "pt_BR" : "en_US"]
    }

    private func shot(_ name: String) {
        count += 1
        sleep(1)
        let file = directory.appendingPathComponent(String(format: "%02d-", count) + name + ".png")
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: file)
    }
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    private func tap(_ id: String, timeout: TimeInterval = 10) {
        let target = element(id)
        if target.waitForExistence(timeout: timeout) { target.tap() } else { XCTFail("Missing \(id)") }
    }
    /// The visible one of several elements sharing an identifier (the home tab strip stays behind the player).
    private func tapVisible(_ id: String) {
        _ = app.buttons[id].firstMatch.waitForExistence(timeout: 10)
        if let target = app.buttons.matching(identifier: id).allElementsBoundByIndex.first(where: { $0.isHittable }) { target.tap() }
        else { XCTFail("No visible \(id)") }
    }
    private func closeSheet() {
        let close = app.buttons["closeSheet"].firstMatch
        if close.waitForExistence(timeout: 3) { close.tap() } else { app.swipeDown(velocity: .fast) }
        sleep(1)
    }
    /// Taps the status bar area, outside menus and action sheets.
    private func dismissOverlay() { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)).tap(); sleep(1) }
    private func back() { app.navigationBars.buttons.element(boundBy: 0).tap(); sleep(1) }
    private func drawer(_ id: String) {
        tap("mainMenu")
        let target = element(id)
        if target.waitForExistence(timeout: 5), !target.isHittable { element("navigationDrawer").swipeUp() }
        tap(id)
    }
    private func scrollShots(_ name: String, pages: Int) {
        shot(name)
        for page in 2...max(2, pages) where pages > 1 { app.swipeUp(); shot(name + "-\(page)") }
    }

    func testTour() {
        app.launch()
        XCTAssertTrue(app.buttons["mainMenu"].waitForExistence(timeout: 15))
        sleep(3); shot("home-live")
        tap("mainMenu"); shot("drawer"); element("navigationDrawer").swipeUp(); shot("drawer-2")
        tap("drawer-section-Subscriptions"); shot("subscriptions")
        tap("subscriptionGroupFilter"); shot("group-filter"); app.buttons["selectGroup-all"].firstMatch.tap()
        tap("manageSubscriptionGroups"); shot("groups"); tap("createSubscriptionGroup"); shot("group-editor")
        tap("cancelGroupEdit"); tap("closeSubscriptionGroups")
        drawer("drawer-section-What's new"); sleep(2); shot("feed")
        tap("feedFilters"); shot("feed-filters"); dismissOverlay()
        drawer("drawer-section-Bookmarked"); shot("bookmarks")
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "itemActions-")).firstMatch
        if saved.waitForExistence(timeout: 3) { saved.tap(); shot("item-actions"); dismissOverlay() }
        let create = app.buttons["createPlaylist"].firstMatch
        if create.waitForExistence(timeout: 3), create.isHittable { create.tap(); shot("new-playlist"); closeSheet() }
        drawer("drawer-section-History"); shot("history")
        drawer("drawer-section-Trending music"); sleep(4); shot("trending")

        tap("openSearch"); shot("search-empty")
        let query = app.textFields["searchQuery"]
        if query.waitForExistence(timeout: 5) { query.tap(); query.typeText("lofi"); sleep(2); shot("search-suggestions"); query.typeText("\n") }
        sleep(6); shot("search-results")
        tap("searchFilters"); shot("search-filters"); dismissOverlay()
        tap("searchService"); app.segmentedControls.buttons.element(boundBy: 1).tap(); sleep(1); shot("search-soundcloud")
        tap("closeSearch")

        drawer("drawer-Open a link"); shot("open-link"); closeSheet()
        drawer("drawer-Downloads"); shot("downloads"); tap("openDownloadSettings"); sleep(2); shot("download-settings"); back(); closeSheet()
        drawer("drawer-About"); shot("about"); closeSheet()
        drawer("drawer-Settings"); scrollShots("settings", pages: 4)
        app.swipeDown(); app.swipeDown(); app.swipeDown(); app.swipeDown()
        tap("openHomeTabs"); scrollShots("home-tabs", pages: 2); back()
        for _ in 0..<4 where !element("openBackup").isHittable { app.swipeUp() }
        tap("openBackup"); scrollShots("backup", pages: 3); back()
        closeSheet()

        // The player with a live video: controls, options, tabs and sheets.
        app.terminate()
        app.launchArguments += ["--playback-smoke-url", "https://www.youtube.com/watch?v=dQw4w9WgXcQ", "--player-smoke", "hud"]
        app.launch()
        XCTAssertTrue(element("videoPlayer").waitForExistence(timeout: 30))
        sleep(6); shot("player")
        tap("playbackSpeed"); shot("speed"); dismissOverlay()
        tap("playbackOptions"); shot("player-options"); dismissOverlay()
        tapVisible("sectionTab-1"); sleep(6); shot("comments")
        tapVisible("sectionTab-2"); shot("description")
        tapVisible("sectionTab-3"); shot("queue")
        tap("detailDownload"); sleep(8); shot("download-sheet"); closeSheet()
        tap("minimizePlayer"); sleep(1); shot("mini-player")
    }
}
