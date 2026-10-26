// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

final class NavigationTests: XCTestCase {
    private func application() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--library-smoke-run", "ui-" + UUID().uuidString, "--library-smoke-seed"]
        app.launch()
        return app
    }
    private func captureDeviceState(_ name: String, app: XCUIApplication) {
#if !targetEnvironment(simulator)
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: directory.appendingPathComponent(name + ".png"))
        try? app.debugDescription.write(to: directory.appendingPathComponent(name + ".txt"), atomically: true, encoding: .utf8)
#endif
    }
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { XCUIDevice.shared.orientation = .portrait }

    func testDrawerSettingsAndExistingLibraryRemainAccessible() {
        let app = application()
        XCTAssertTrue(app.buttons["mainMenu"].waitForExistence(timeout: 10))
        app.buttons["mainMenu"].tap()
        let settings = app.descendants(matching: .any)["drawer-Settings"].firstMatch
        if !settings.isHittable { app.swipeUp() }
        XCTAssertTrue(settings.waitForExistence(timeout: 5)); settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        for _ in 0..<3 where !app.switches["Record watch history"].exists { app.swipeUp() }
        XCTAssertTrue(app.switches["Record watch history"].exists)
        for _ in 0..<3 where !app.buttons["Backup and import"].exists { app.swipeUp() }
        app.buttons["Backup and import"].tap()
        XCTAssertTrue(app.buttons["Export library backup"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.navigationBars["Settings"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        app.buttons["mainMenu"].tap()
        let subscriptions = app.descendants(matching: .any)["drawer-section-Subscriptions"].firstMatch
        XCTAssertTrue(subscriptions.waitForExistence(timeout: 5)); subscriptions.tap()
        XCTAssertTrue(app.staticTexts["ndls 404"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Subscriptions"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testSearchPlayerMinimizeAndReturnPreserveResults() {
        let app = application()
        XCTAssertTrue(app.buttons["openSearch"].waitForExistence(timeout: 10))
        app.buttons["openSearch"].tap()
        let query = app.textFields["searchQuery"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        query.tap(); query.typeText("NDLS404 SENSOJI")
        app.buttons["submitSearch"].tap()
        let result = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "searchVideo-")).firstMatch
        let hasResults = result.waitForExistence(timeout: 45)
        if !hasResults { captureDeviceState("search-no-results", app: app) }
        XCTAssertTrue(hasResults)
        let results = XCTAttachment(screenshot: app.screenshot())
        results.name = "Search results"; results.lifetime = .keepAlways; add(results)
        result.tap()
        let minimize = app.buttons["minimizePlayer"]
        XCTAssertTrue(minimize.waitForExistence(timeout: 15))
        minimize.tap()
        XCTAssertTrue(app.buttons["expandMiniPlayer"].waitForExistence(timeout: 5))
        XCTAssertEqual(query.value as? String, "NDLS404 SENSOJI")
        XCTAssertTrue(result.exists)
        app.buttons["expandMiniPlayer"].tap()
        XCTAssertTrue(minimize.waitForExistence(timeout: 5))
#if targetEnvironment(simulator)
        XCUIDevice.shared.orientation = .landscapeLeft
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.width > app.frame.height
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed)
        XCTAssertTrue(minimize.waitForExistence(timeout: 5))
        let landscape = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        landscape.name = "Landscape video detail"; landscape.lifetime = .keepAlways; add(landscape)
        XCUIDevice.shared.orientation = .portrait
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.height > app.frame.width
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed)
#endif
        minimize.tap()
        app.buttons["Back to home"].tap()
        XCTAssertTrue(app.buttons["mainMenu"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["expandMiniPlayer"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Home with mini player"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    func testKeyboardSearchSubmissionLoadsResults() {
        let app = application()
        app.buttons["openSearch"].tap()
        let query = app.textFields["searchQuery"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        query.tap(); query.typeText("NDLS404 SENSOJI\n")
        let result = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "searchVideo-")).firstMatch
        let hasResults = result.waitForExistence(timeout: 45)
        if !hasResults { captureDeviceState("keyboard-search-no-results", app: app) }
        XCTAssertTrue(hasResults)
        XCTAssertEqual(query.value as? String, "NDLS404 SENSOJI")
    }

    func testSubscriptionGroupsPersistAndFilterChannels() {
        let app = application()
        app.buttons["mainMenu"].tap()
        app.descendants(matching: .any)["drawer-section-Subscriptions"].firstMatch.tap()
        XCTAssertTrue(app.buttons["manageSubscriptionGroups"].waitForExistence(timeout: 5))
        app.buttons["manageSubscriptionGroups"].tap()
        app.buttons["createSubscriptionGroup"].tap()
        let name = app.textFields["subscriptionGroupName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Music group")
        let member = app.buttons["groupMember-UCUb-HI7Kd-Dr1fBvYjV1IYg"]
        member.tap(); XCTAssertEqual(member.value as? String, "Selected"); app.buttons["saveSubscriptionGroup"].tap()
        XCTAssertTrue(app.staticTexts["subscriptionGroupsTitle"].waitForExistence(timeout: 5))
        app.buttons["closeSubscriptionGroups"].tap()
        app.descendants(matching: .any)["subscriptionGroupFilter"].firstMatch.tap(); app.buttons["Music group"].tap()
        XCTAssertTrue(app.staticTexts["ndls 404"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        app.buttons["mainMenu"].tap()
        app.descendants(matching: .any)["drawer-section-Subscriptions"].firstMatch.tap()
        app.descendants(matching: .any)["subscriptionGroupFilter"].firstMatch.tap(); app.buttons["Music group"].tap()
        XCTAssertTrue(app.staticTexts["ndls 404"].waitForExistence(timeout: 5))
        app.buttons["manageSubscriptionGroups"].tap()
        let group = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "editGroup-")).firstMatch
        XCTAssertTrue(group.waitForExistence(timeout: 5)); group.tap()
        XCTAssertEqual(app.textFields["subscriptionGroupName"].value as? String, "Music group")
        app.buttons["groupMember-UCUb-HI7Kd-Dr1fBvYjV1IYg"].tap(); app.buttons["saveSubscriptionGroup"].tap()
        app.buttons["closeSubscriptionGroups"].tap()
        XCTAssertTrue(app.staticTexts["No channels in this group"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["subscriptionGroupFilter"].firstMatch.tap(); app.buttons["selectGroup-all"].tap()
        XCTAssertTrue(app.staticTexts["ndls 404"].waitForExistence(timeout: 5))
        app.buttons["mainMenu"].tap()
        app.descendants(matching: .any)["drawer-section-What's new"].firstMatch.tap()
        XCTAssertTrue(app.buttons["feedFilters"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["subscriptionGroupFilter"].firstMatch.tap(); app.buttons["Music group"].tap()
        XCTAssertTrue(app.staticTexts["No channels in this feed"].waitForExistence(timeout: 5))
        app.buttons["feedFilters"].tap()
        XCTAssertTrue(app.buttons["Last 7 days"].waitForExistence(timeout: 5)); app.buttons["Last 7 days"].tap()
    }

    func testCommentsLoadForKnownVideo() {
        let app = application()
        let video = app.buttons["browseVideo-11-9ZaYiTPE"].firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 10)); video.tap()
        let comments = app.buttons["COMMENTS"]
        XCTAssertTrue(comments.waitForExistence(timeout: 15)); comments.tap()
        XCTAssertTrue(app.staticTexts["commentText"].firstMatch.waitForExistence(timeout: 45))
    }

    func testCreatePlaylistFromSavedVideoSurvivesRelaunch() {
        let app = application()
        let actions = app.buttons["itemActions-video:11-9ZaYiTPE"].firstMatch
        XCTAssertTrue(actions.waitForExistence(timeout: 10))
        actions.tap()
        app.buttons["Add to playlist"].tap()
        let name = app.textFields["playlistName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Road trip")
        app.buttons["createPlaylist"].tap()
        XCTAssertTrue(app.staticTexts["Road trip"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["Road trip"].waitForExistence(timeout: 10))
        app.buttons.containing(.staticText, identifier: "Road trip").firstMatch.tap()
        XCTAssertTrue(app.buttons["Play all"].waitForExistence(timeout: 5))
        app.buttons["Play all"].tap()
        XCTAssertTrue(app.buttons["minimizePlayer"].waitForExistence(timeout: 10))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["expandMiniPlayer"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Play"].exists)
    }
    func testDownloadChooserAndDeviceOfflinePlayback() {
        let app = application()
        let actions = app.buttons["itemActions-video:11-9ZaYiTPE"].firstMatch
        XCTAssertTrue(actions.waitForExistence(timeout: 10))
        app.buttons["browseVideo-11-9ZaYiTPE"].firstMatch.tap()
        let options = app.buttons["Playback options"]
        XCTAssertTrue(options.waitForExistence(timeout: 15)); options.tap()
        app.buttons["Download"].tap()
        let choice = app.buttons["Video · automatic quality (HLS)"]
        XCTAssertTrue(choice.waitForExistence(timeout: 60)); choice.tap()
        let pickerDismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: choice)
        XCTAssertEqual(XCTWaiter.wait(for: [pickerDismissed], timeout: 10), .completed)
        captureDeviceState("download-choice-selected", app: app)
        let minimize = app.buttons["minimizePlayer"]
        XCTAssertTrue(minimize.waitForExistence(timeout: 10)); minimize.tap()
        captureDeviceState("download-minimized", app: app)
        XCTAssertTrue(app.buttons["expandMiniPlayer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["mainMenu"].waitForExistence(timeout: 10))
        app.buttons["mainMenu"].tap()
#if !targetEnvironment(simulator)
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: directory.appendingPathComponent("download-drawer.png"))
        try? app.debugDescription.write(to: directory.appendingPathComponent("download-drawer.txt"), atomically: true, encoding: .utf8)
#endif
        let downloads = app.descendants(matching: .any)["drawer-Downloads"].firstMatch
        if !downloads.isHittable { app.swipeUp() }
        XCTAssertTrue(downloads.waitForExistence(timeout: 5)); downloads.tap()
#if targetEnvironment(simulator)
        // Exercise the real chooser and persisted job UI here; HLS offline media is verified on hardware.
        XCTAssertTrue(app.staticTexts["Video · automatic quality (HLS)"].waitForExistence(timeout: 10))
#else
        let offline = app.buttons["Play offline"].firstMatch
        XCTAssertTrue(offline.waitForExistence(timeout: 180)); offline.tap()
        XCTAssertTrue(app.staticTexts["Offline playback"].waitForExistence(timeout: 15))
#endif
    }

    func testPinnedChannelSurvivesRelaunchAndCanBeRemoved() {
        let app = application()
        XCTAssertTrue(app.buttons["mainMenu"].waitForExistence(timeout: 10)); app.buttons["mainMenu"].tap()
        app.descendants(matching: .any)["drawer-section-Subscriptions"].firstMatch.tap()
        let actions = app.buttons["itemActions-channel:UCUb-HI7Kd-Dr1fBvYjV1IYg"].firstMatch
        XCTAssertTrue(actions.waitForExistence(timeout: 10)); actions.tap()
        app.buttons["Add to home"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["mainMenu"].waitForExistence(timeout: 10)); app.buttons["mainMenu"].tap()
        let pinned = app.descendants(matching: .any)["drawer-pinned-channel:UCUb-HI7Kd-Dr1fBvYjV1IYg"].firstMatch
        if !pinned.isHittable { app.swipeUp() }
        XCTAssertTrue(pinned.waitForExistence(timeout: 5)); pinned.tap()
        XCTAssertTrue(app.staticTexts["pinnedPageTitle"].waitForExistence(timeout: 10))
        app.buttons["Pinned tab options"].tap(); app.buttons["Remove from home"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["mainMenu"].waitForExistence(timeout: 10)); app.buttons["mainMenu"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["drawer-pinned-channel:UCUb-HI7Kd-Dr1fBvYjV1IYg"].firstMatch.exists)
    }

    func testSuggestionSelectionSubmitsTheSuggestedQuery() {
        let app = application()
        XCTAssertTrue(app.buttons["openSearch"].waitForExistence(timeout: 10)); app.buttons["openSearch"].tap()
        let query = app.textFields["searchQuery"]
        XCTAssertTrue(query.waitForExistence(timeout: 5)); query.tap(); query.typeText("newpipe")
        let suggestion = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "searchSuggestion-")).firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 20))
        let text = String(suggestion.identifier.dropFirst("searchSuggestion-".count))
        suggestion.tap()
        XCTAssertEqual(query.value as? String, text)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "searchVideo-")).firstMatch.waitForExistence(timeout: 45))
    }

    func testTrendingMusicUsesOfficialChart() {
        let app = application()
        XCTAssertTrue(app.buttons["mainMenu"].waitForExistence(timeout: 10)); app.buttons["mainMenu"].tap()
        let trending = app.descendants(matching: .any)["drawer-section-Trending music"].firstMatch
        if !trending.isHittable { app.swipeUp() }
        XCTAssertTrue(trending.waitForExistence(timeout: 5)); trending.tap()
        XCTAssertTrue(app.staticTexts["YouTube Charts · PT"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "browseVideo-")).firstMatch.waitForExistence(timeout: 35))
    }

}
