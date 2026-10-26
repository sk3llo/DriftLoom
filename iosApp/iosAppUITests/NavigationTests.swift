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
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 3))
        app.buttons["Settings"].tap()
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
        query.tap(); query.typeText("NDLS404 SENSOJI\n")
        let result = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "searchVideo-")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 45))
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

}
