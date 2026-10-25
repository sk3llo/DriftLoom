// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

final class NavigationTests: XCTestCase {
    private func application() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--library-smoke-run", "ui-" + UUID().uuidString, "--library-smoke-seed"]
        app.launch()
        return app
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
        XCTAssertTrue(app.switches["Record watch history"].exists)
        app.buttons["Done"].tap()
        app.buttons["mainMenu"].tap()
        app.buttons["Subscriptions"].firstMatch.tap()
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
        let result = app.buttons["searchVideo-11-9ZaYiTPE"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 45))
        let results = XCTAttachment(screenshot: app.screenshot())
        results.name = "Search results"; results.lifetime = .keepAlways; add(results)
        result.tap()
        let minimize = app.buttons["minimizePlayer"]
        XCTAssertTrue(minimize.waitForExistence(timeout: 15))
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
        minimize.tap()
        XCTAssertTrue(app.buttons["expandMiniPlayer"].waitForExistence(timeout: 5))
        XCTAssertEqual(query.value as? String, "NDLS404 SENSOJI")
        XCTAssertTrue(result.exists)
        app.buttons["expandMiniPlayer"].tap()
        XCTAssertTrue(minimize.waitForExistence(timeout: 5))
        minimize.tap()
        app.buttons["Back to home"].tap()
        XCTAssertTrue(app.buttons["mainMenu"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["expandMiniPlayer"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Home with mini player"; screenshot.lifetime = .keepAlways; add(screenshot)
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
    }
}
