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
    private func closeSheet() {
        let close = app.buttons["closeSheet"].firstMatch
        if close.waitForExistence(timeout: 3) { close.tap() } else { app.swipeDown(velocity: .fast) }
        sleep(1)
    }
    /// Closes a menu with a tap on the navigation bar's title, which does nothing on its own.
    private func dismissOverlay() { app.navigationBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap(); sleep(1) }
    private func back() { app.navigationBars.buttons.element(boundBy: 0).tap(); sleep(1) }
    private func tab(_ title: String) { app.tabBars.buttons[title].firstMatch.tap(); sleep(1) }
    /// Opens the Home title menu and picks a tab from it.
    private func homeTab(_ title: String) {
        openHomeMenu()
        let item = app.buttons[title].firstMatch
        if item.waitForExistence(timeout: 5) { item.tap() } else { XCTFail("Missing home tab \(title)") }
        sleep(1)
    }
    private func openHomeMenu() {
        app.navigationBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        if !app.buttons["Customize tabs"].waitForExistence(timeout: 5) { XCTFail("The home menu didn't open") }
        sleep(1)
    }
    /// Picks an item in an open menu, which also closes it.
    private func pick(_ title: String) {
        let item = app.buttons[title].firstMatch
        if item.waitForExistence(timeout: 5) { item.tap() } else { XCTFail("Missing \(title)") }
        sleep(1)
    }
    /// Taps segment `index` of the visible segmented control with this identifier.
    private func segment(_ id: String, _ index: Int) {
        _ = app.segmentedControls[id].firstMatch.waitForExistence(timeout: 10)
        if let control = app.segmentedControls.matching(identifier: id).allElementsBoundByIndex.first(where: { $0.isHittable }) {
            control.buttons.element(boundBy: index).tap()
        } else { XCTFail("No visible \(id)") }
    }
    private func scrollShots(_ name: String, pages: Int) {
        shot(name)
        for page in 2...max(2, pages) where pages > 1 { app.swipeUp(); shot(name + "-\(page)") }
    }

    func testTour() {
        app.launchArguments += ["--library-smoke-section", "Home"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 15))
        sleep(4); shot("home-live")
        openHomeMenu(); shot("home-menu")
        pick("Trending music"); sleep(4); shot("trending")

        tab("Subscriptions"); sleep(2); shot("feed")
        tap("feedFilters"); shot("feed-filters"); pick("All recent uploads")
        app.segmentedControls.buttons["Channels"].firstMatch.tap(); sleep(1); shot("subscriptions")
        tap("subscriptionGroupFilter"); shot("group-filter")
        app.buttons["Manage subscription groups"].firstMatch.tap(); sleep(1); shot("groups"); tap("createSubscriptionGroup"); shot("group-editor")
        tap("cancelGroupEdit"); tap("closeSubscriptionGroups")

        tab("Library"); shot("library")
        tap("library-bookmarks"); shot("bookmarks")
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "itemActions-")).firstMatch
        if saved.waitForExistence(timeout: 3) { saved.tap(); shot("item-actions"); dismissOverlay() }
        let create = app.buttons["newPlaylist"].firstMatch
        if create.waitForExistence(timeout: 3), create.isHittable { create.tap(); shot("new-playlist"); closeSheet() }
        back()
        tap("library-history"); shot("history"); back()
        tap("library-downloads"); shot("downloads"); tap("openDownloadSettings"); sleep(2); shot("download-settings"); back(); back()

        tab("Search"); shot("search-empty")
        let query = app.searchFields.firstMatch
        if query.waitForExistence(timeout: 5) { query.tap(); query.typeText("lofi"); sleep(2); shot("search-suggestions"); query.typeText("\n") }
        sleep(6); shot("search-results")
        tap("searchFilters"); shot("search-filters"); pick("Reset filters")
        segment("searchService", 1); sleep(4); shot("search-soundcloud")

        tab("Home"); tap("openLink"); shot("open-link"); closeSheet()
        tab("Settings"); scrollShots("settings", pages: 4)
        app.swipeDown(); app.swipeDown(); app.swipeDown(); app.swipeDown()
        tap("openHomeTabs"); scrollShots("home-tabs", pages: 2); back()
        for _ in 0..<4 where !element("openBackup").isHittable { app.swipeUp() }
        tap("openBackup"); scrollShots("backup", pages: 3); back()
        for _ in 0..<4 where !element("openAbout").isHittable { app.swipeUp() }
        tap("openAbout"); shot("about"); back()

        // The player with a live video: controls, options, tabs and sheets.
        app.terminate()
        app.launchArguments += ["--playback-smoke-url", "https://www.youtube.com/watch?v=dQw4w9WgXcQ", "--player-smoke", "hud", "--chapters-smoke"]
        app.launch()
        XCTAssertTrue(element("videoPlayer").waitForExistence(timeout: 30))
        sleep(6); shot("player")
        tap("playbackSpeed"); shot("speed"); dismissOverlay()
        tap("playbackOptions"); shot("player-options"); dismissOverlay()
        segment("sectionPicker", 1); sleep(6); shot("comments")
        segment("sectionPicker", 2); shot("description")
        segment("sectionPicker", 3); shot("queue")
        tap("detailDownload"); sleep(8); shot("download-sheet"); closeSheet()
        tap("minimizePlayer"); sleep(1); shot("mini-player")

        // Scrubbing: the preview frame, chapter and time over the video.
        app.terminate()
        app.launchArguments = app.launchArguments.filter { $0 != "hud" && $0 != "--player-smoke" } + ["--seek-preview-smoke", "0.45"]
        app.launch()
        XCTAssertTrue(element("videoPlayer").waitForExistence(timeout: 30))
        sleep(8); shot("player-scrub")
    }
}
