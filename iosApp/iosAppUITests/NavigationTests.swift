// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

final class NavigationTests: XCTestCase {
    private func application(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--library-smoke-run", "ui-" + UUID().uuidString, "--library-smoke-seed"] + extraArguments
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
        app.textFields["searchQuery"].typeText("\n")
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
    /// Download journeys need live extraction. The seeded fixture is sometimes refused by YouTube's
    /// bot check on test networks, so open a widely available video through the playback smoke path.
    private static let liveVideo = ["--playback-smoke-url", "https://www.youtube.com/watch?v=dQw4w9WgXcQ"]

    func testDownloadChooserAndDeviceOfflinePlayback() {
        let app = application(extraArguments: Self.liveVideo)
        let download = app.buttons["Download"]
        XCTAssertTrue(download.waitForExistence(timeout: 15)); download.tap()
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

    func testQueuedDownloadNetworkPolicyAndRelaunchRecovery() {
        let app = application(extraArguments: ["--download-smoke-no-network"] + Self.liveVideo)
        XCTAssertTrue(app.buttons["Download"].waitForExistence(timeout: 15))
        app.buttons["Download"].tap()
        let hls = app.buttons["Video · automatic quality (HLS)"]
        XCTAssertTrue(hls.waitForExistence(timeout: 45)); hls.tap()
        app.buttons["minimizePlayer"].tap()
        func openDownloads() {
            // Relaunching with the smoke URL reopens the expanded player over the home screen.
            if app.buttons["minimizePlayer"].waitForExistence(timeout: 5) { app.buttons["minimizePlayer"].tap() }
            app.buttons["mainMenu"].tap()
            let downloads = app.descendants(matching: .any)["drawer-Downloads"].firstMatch
            if !downloads.isHittable { app.swipeUp() }
            downloads.tap()
        }
        openDownloads()
        XCTAssertTrue(app.staticTexts["Waiting for Wi-Fi…"].waitForExistence(timeout: 10))
        app.buttons["Downloads and storage"].tap()
        XCTAssertTrue(app.staticTexts["downloadStorageUsage"].waitForExistence(timeout: 10))
        let any = app.buttons["downloadNetwork-Wi-Fi and mobile data"]
        any.tap(); XCTAssertEqual(any.value as? String, "Selected")
        app.terminate(); app.launch(); openDownloads()
        // The existing transfer retains Wi-Fi-only policy even after preferences change.
        XCTAssertTrue(app.staticTexts["Waiting for Wi-Fi…"].waitForExistence(timeout: 10))
        app.buttons["Cancel download"].tap()
        XCTAssertTrue(app.buttons["Retry download"].waitForExistence(timeout: 5)); app.buttons["Retry download"].tap()
        XCTAssertTrue(app.staticTexts["Waiting for a connection…"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Wi-Fi and mobile data"].exists)
#if targetEnvironment(simulator)
        app.buttons["Cancel download"].tap()
#else
        // Restore real connectivity input without changing the phone's network settings.
        app.terminate(); app.launchArguments.removeAll { $0 == "--download-smoke-no-network" }; app.launch()
        openDownloads()
        let offline = app.buttons["Play offline"].firstMatch
        XCTAssertTrue(offline.waitForExistence(timeout: 180)); offline.tap()
        XCTAssertTrue(app.staticTexts["Offline playback"].waitForExistence(timeout: 15))
#endif
    }

    func testSubtitlesChosenInPlayerShowAndTurnOnAfterRelaunch() {
        let app = application(extraArguments: ["--playback-smoke-url", "https://www.youtube.com/watch?v=dQw4w9WgXcQ"])
        let options = app.buttons["Playback options"]
        XCTAssertTrue(options.waitForExistence(timeout: 20))
        let subtitles = app.buttons["Subtitles"]
        for _ in 0..<30 where !subtitles.exists {
            options.tap()
            if subtitles.waitForExistence(timeout: 2) { break }
            app.tap() // close the menu while tracks are still loading
        }
        subtitles.tap()
        let english = app.buttons["English"]
        XCTAssertTrue(english.waitForExistence(timeout: 5)); english.tap()
        // The smoke check seeks to 60 seconds, where this video has lyrics.
        XCTAssertTrue(app.staticTexts["subtitleText"].waitForExistence(timeout: 90))
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["subtitleText"].waitForExistence(timeout: 90), "The chosen language must apply to the next playback")
        app.buttons["Playback options"].tap(); app.buttons["Subtitles"].tap()
        XCTAssertTrue(app.buttons["English ✓"].waitForExistence(timeout: 5))
        app.buttons["Off"].tap()
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.staticTexts["subtitleText"])
        wait(for: [gone], timeout: 5)
    }

    func testLocalPlaylistPinsToHomeAndReordersAmongSections() {
        let app = application()
        let actions = app.buttons["itemActions-video:11-9ZaYiTPE"].firstMatch
        XCTAssertTrue(actions.waitForExistence(timeout: 10)); actions.tap()
        app.buttons["Add to playlist"].tap()
        let name = app.textFields["playlistName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Road trip")
        app.buttons["createPlaylist"].tap()
        XCTAssertTrue(app.staticTexts["Road trip"].waitForExistence(timeout: 5))
        app.buttons.containing(.staticText, identifier: "Road trip").firstMatch.tap()
        XCTAssertTrue(app.buttons["localPlaylistOptions"].waitForExistence(timeout: 5)); app.buttons["localPlaylistOptions"].tap()
        app.buttons["Add to home"].tap()
        app.terminate(); app.launch()
        let tab = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "tabBar-local:")).firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "Pinned local playlist must survive relaunch as a home tab")
        let subscriptions = app.buttons["tabBar-section:Subscriptions"]
        XCTAssertGreaterThan(tab.frame.minX, subscriptions.frame.minX, "New pins follow the sections by default")
        app.buttons["mainMenu"].tap()
        let drawerEntry = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'drawer-local-'")).firstMatch
        if drawerEntry.exists, !drawerEntry.isHittable { app.swipeUp() }
        XCTAssertTrue(drawerEntry.waitForExistence(timeout: 5)); drawerEntry.tap()
        XCTAssertTrue(app.buttons["Play all"].waitForExistence(timeout: 5))
        XCTAssertTrue(tab.isSelected)

        app.buttons["More options"].tap(); app.buttons["Settings"].tap()
        app.buttons["Home tabs"].tap()
        let local = app.descendants(matching: .any)["homeTab-local"].firstMatch
        XCTAssertTrue(local.waitForExistence(timeout: 5))
        let first = app.cells.containing(.any, identifier: "homeTab-section:Subscriptions").buttons["Reorder"].firstMatch
        let handle = app.cells.containing(.any, identifier: "homeTab-local").buttons["Reorder"].firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        handle.press(forDuration: 0.6, thenDragTo: first)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        XCTAssertLessThan(tab.frame.minX, subscriptions.frame.minX, "The playlist tab moved ahead of Subscriptions")
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "tabBar-local:")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertLessThan(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "tabBar-local:")).firstMatch.frame.minX, app.buttons["tabBar-section:Subscriptions"].frame.minX, "The interleaved order survives relaunch")
    }

    func testHomeToolbarShowsTheTabNameAndTabsCanBeCustomized() {
        let app = application()
        let live = app.buttons["tabBar-section:Live"]
        XCTAssertTrue(live.waitForExistence(timeout: 10))
        XCTAssertEqual(live.label, "Live", "Icon tabs are named for VoiceOver")
        app.buttons["tabBar-section:History"].tap()
        XCTAssertEqual(app.staticTexts["homeTitle"].label, "History", "The toolbar names the open tab")
        XCTAssertTrue(app.buttons["tabBar-section:History"].isSelected)
        app.buttons["moreOptions"].tap()
        app.buttons["Customize tabs"].tap()
        XCTAssertTrue(app.navigationBars["Home tabs"].waitForExistence(timeout: 5), "Customize opens the home tab settings")
        let gaming = app.switches["Gaming"]
        for _ in 0..<3 where !gaming.isHittable { app.swipeUp() }
        gaming.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(gaming.value as? String, "1")
        app.buttons["closeSheet"].tap()
        XCTAssertTrue(app.buttons["tabBar-section:Gaming"].waitForExistence(timeout: 5), "A tab turned on in Customize appears in the bar")
    }

    func testDrawerOpensFromTheLeftEdgeAndClosesByDragging() {
        let app = application()
        XCTAssertTrue(app.buttons["mainMenu"].waitForExistence(timeout: 10))
        let drawer = app.descendants(matching: .any)["navigationDrawer"].firstMatch
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        // A short pull springs back; a long one opens the drawer.
        edge.press(forDuration: 0.05, thenDragTo: edge.withOffset(CGVector(dx: 40, dy: 0)))
        sleep(1)
        XCTAssertFalse(drawer.exists, "A short pull from the edge springs back")
        edge.press(forDuration: 0.05, thenDragTo: edge.withOffset(CGVector(dx: 260, dy: 0)))
        XCTAssertTrue(drawer.waitForExistence(timeout: 3), "Dragging from the left edge opens the main menu")
        sleep(1)
        XCTAssertEqual(drawer.frame.minX, 0, accuracy: 1, "The drawer settles fully open")
        XCTAssertTrue(app.descendants(matching: .any)["drawer-section-Subscriptions"].firstMatch.exists)
        // Drag it back to close.
        let inside = drawer.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.6))
        inside.press(forDuration: 0.05, thenDragTo: inside.withOffset(CGVector(dx: -250, dy: 0)))
        let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: drawer)
        wait(for: [closed], timeout: 3)
        // The dimmed area beside the drawer drags it closed too, and the menu button still works.
        app.buttons["mainMenu"].tap()
        XCTAssertTrue(drawer.waitForExistence(timeout: 3))
        let scrim = app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        scrim.press(forDuration: 0.05, thenDragTo: scrim.withOffset(CGVector(dx: -250, dy: 0)))
        wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: drawer)], timeout: 3)
    }

    func testKioskFromDrawerLoadsYouTubeLiveAndStaysOnHome() {
        let app = application()
        XCTAssertTrue(app.buttons["mainMenu"].waitForExistence(timeout: 10)); app.buttons["mainMenu"].tap()
        let live = app.descendants(matching: .any)["drawer-section-Live"].firstMatch
        if live.exists, !live.isHittable { app.swipeUp() }
        XCTAssertTrue(live.waitForExistence(timeout: 5)); live.tap()
        XCTAssertTrue(app.staticTexts["kioskSource"].waitForExistence(timeout: 10))
        let video = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'browseVideo-'")).firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 45), "The Live kiosk should list videos")
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["tabBar-section:Live"].waitForExistence(timeout: 10), "Live is on home")
        XCTAssertLessThan(app.buttons["tabBar-section:Live"].frame.minX, app.buttons["tabBar-section:Subscriptions"].frame.minX, "Live is the first home tab")
    }

    func testSoundCloudSearchPlaysTracksAndOpensProfiles() {
        let app = application()
        XCTAssertTrue(app.buttons["openSearch"].waitForExistence(timeout: 10)); app.buttons["openSearch"].tap()
        app.segmentedControls["searchService"].buttons["SoundCloud"].tap()
        let query = app.textFields["searchQuery"]
        XCTAssertTrue(query.waitForExistence(timeout: 5)); query.tap(); query.typeText("lofi hip hop")
        app.textFields["searchQuery"].typeText("\n")
        let track = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'searchVideo-sc:'")).firstMatch
        XCTAssertTrue(track.waitForExistence(timeout: 45), "SoundCloud search should list tracks")
        track.tap()
        XCTAssertTrue(app.staticTexts["SoundCloud"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["audioArtwork"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["playbackError"].waitForExistence(timeout: 8), "The track should play")
        app.buttons["minimizePlayer"].tap()
        XCTAssertTrue(app.buttons["expandMiniPlayer"].waitForExistence(timeout: 5))
        app.buttons["USERS"].tap()
        let profile = app.buttons.matching(NSPredicate(format: "label CONTAINS 'SoundCloud · Channel'")).firstMatch
        XCTAssertTrue(profile.waitForExistence(timeout: 45)); profile.tap()
        let subscribe = app.buttons["SUBSCRIBE"]
        XCTAssertTrue(subscribe.waitForExistence(timeout: 30)); subscribe.tap()
        XCTAssertTrue(app.buttons["SUBSCRIBED"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["mainMenu"].waitForExistence(timeout: 10)); app.buttons["mainMenu"].tap()
        app.descendants(matching: .any)["drawer-section-Subscriptions"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'SoundCloud'")).firstMatch.waitForExistence(timeout: 10),
                      "The SoundCloud subscription survives relaunch")
    }

    func testDownloadShowsProgressStripAndNotificationOpensDownloads() {
        let app = application(extraArguments: ["--download-notifications", "--download-smoke", "--download-smoke-video", "sc:1992908699"])
        XCTAssertTrue(app.buttons["downloadStrip"].waitForExistence(timeout: 30), "Progress strip while downloading")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
        let banner = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'ready to watch offline'")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 120), "A notification when the download finishes")
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["downloadStrip"])
        wait(for: [gone], timeout: 10)
        banner.tap()
        XCTAssertTrue(app.buttons["Downloads and storage"].waitForExistence(timeout: 10), "Tapping the notification opens Downloads")
    }

    func testFailedDownloadNotifiesWithRetry() {
        // A DRM-only SoundCloud track can't be saved, so the job fails right after it starts.
        let app = application(extraArguments: ["--download-notifications", "--download-smoke", "--download-smoke-video", "sc:1889775891"])
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
        let banner = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Download failed' AND label CONTAINS 'DRM'")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 60), "A failure notification that says why")
        banner.press(forDuration: 1.2)
        XCTAssertTrue(springboard.buttons["Retry"].waitForExistence(timeout: 5), "Failures offer Retry")
        _ = app.wait(for: .runningForeground, timeout: 1)
    }

    private func openLink(_ app: XCUIApplication, _ link: String) throws {
        guard #available(iOS 16.4, *) else { throw XCTSkip("Opening URLs from UI tests needs iOS 16.4") }
        var components = URLComponents(); components.scheme = "driftloom"; components.host = "open"
        components.queryItems = [URLQueryItem(name: "url", value: link)]
        app.open(components.url!)
    }

    func testAppLinksPlayVideosAndOpenChannelAndProfilePages() throws {
        let app = application()
        XCTAssertTrue(app.buttons["mainMenu"].waitForExistence(timeout: 10))
        try openLink(app, "https://youtu.be/dQw4w9WgXcQ?si=shared")
        XCTAssertTrue(app.buttons["minimizePlayer"].waitForExistence(timeout: 15), "A shared video opens the player")
        app.buttons["minimizePlayer"].tap()
        try openLink(app, "https://www.youtube.com/channel/UCUb-HI7Kd-Dr1fBvYjV1IYg")
        let subscribe = app.buttons.matching(NSPredicate(format: "label IN {'SUBSCRIBE', 'SUBSCRIBED'}")).firstMatch
        if !subscribe.waitForExistence(timeout: 30) { print("TREEDUMP-A\n" + app.debugDescription + "\nTREEDUMP-END") }
        XCTAssertTrue(subscribe.exists, "A shared channel opens its page")
        app.buttons["Done"].tap()
        try openLink(app, "https://soundcloud.com/lofi_girl")
        XCTAssertTrue(app.navigationBars["Lofi Girl"].waitForExistence(timeout: 30), "A shared SoundCloud profile opens its page")
        app.buttons["Done"].tap()
        try openLink(app, "https://example.com/not-supported")
        XCTAssertTrue(app.alerts["Couldn't open link"].waitForExistence(timeout: 10))
    }

    func testSharingFromSafariOpensTheVideoInDriftLoom() throws {
        let app = application()
        XCTAssertTrue(app.buttons["mainMenu"].waitForExistence(timeout: 10))
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        let video = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        if #available(iOS 16.4, *) {
            // Safari's address bar label depends on its leftover state (e.g. "Reader Available"), so open the URL directly.
            XCUIDevice.shared.system.open(URL(string: video)!)
            XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 10))
        } else {
            safari.launch()
            let address = safari.textFields["TabBarItemTitle"].exists ? safari.textFields["TabBarItemTitle"] : safari.buttons["Address"]
            if address.waitForExistence(timeout: 10) { address.tap() }
            let field = safari.textFields["URL"]
            XCTAssertTrue(field.waitForExistence(timeout: 10)); field.typeText(video + "\n")
        }
        let share = safari.buttons["ShareButton"]
        XCTAssertTrue(share.waitForExistence(timeout: 30)); share.tap()
        var target = safari.cells["DriftLoom"].firstMatch
        if !target.waitForExistence(timeout: 10) {
            // Not among the first share targets: find it under "More".
            safari.cells["More"].firstMatch.tap()
            target = safari.cells["DriftLoom"].firstMatch
        }
        XCTAssertTrue(target.waitForExistence(timeout: 10), "DriftLoom is in the share sheet"); target.tap()
        // iOS confirms opening another app from Safari.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let open = [safari.buttons["Open"], springboard.buttons["Open"]]
        for _ in 0..<20 where !app.wait(for: .runningForeground, timeout: 0.5) {
            if let button = open.first(where: { $0.exists }) { button.tap(); break }
        }
        if !app.wait(for: .runningForeground, timeout: 15) {
            print("TREEDUMP-SAFARI\n" + safari.debugDescription + "\nTREEDUMP-SB\n" + springboard.debugDescription + "\nTREEDUMP-END")
        }
        XCTAssertTrue(app.state == .runningForeground, "DriftLoom comes to the front")
        XCTAssertTrue(app.buttons["minimizePlayer"].waitForExistence(timeout: 15), "and plays the shared video")
    }

    func testBackupScreenExplainsGoogleTakeoutImport() {
        let app = application()
        XCTAssertTrue(app.buttons["More options"].waitForExistence(timeout: 10)); app.buttons["More options"].tap()
        app.buttons["Settings"].tap()
        let backup = app.buttons["Backup and import"]
        for _ in 0..<4 where !backup.isHittable { app.swipeUp() }
        backup.tap()
        let takeout = app.descendants(matching: .any)["openTakeout"].firstMatch
        for _ in 0..<4 where !takeout.exists { app.swipeUp() }
        XCTAssertTrue(takeout.waitForExistence(timeout: 5), "The Takeout section links to Google Takeout")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'subscriptions.csv'")).firstMatch.exists)
    }

    func testNewVideoNotificationOpensTheVideo() {
        let app = application(extraArguments: ["--download-notifications", "--feed-notifications-on", "--feed-check-channel", "UCupvZG-5ko_eiXAupbDfxWw", "--feed-check-smoke"])
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.buttons["Allow"].waitForExistence(timeout: 5) { springboard.alerts.buttons["Allow"].tap() }
        XCTAssertTrue(app.buttons["mainMenu"].waitForExistence(timeout: 10))
        sleep(8) // the first check only records the current feed
        app.terminate()
        app.launchArguments += ["--feed-check-forget", "2"]
        app.launch()
        let banner = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'CNN'")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 45), "Recent uploads that weren't seen before are announced")
        banner.tap()
        let played = app.buttons["minimizePlayer"].waitForExistence(timeout: 15)
        XCTAssertTrue(played || app.buttons["WHAT'S NEW"].isSelected, "Tapping plays the video (or opens What's new for a summary)")
    }

    func testSeekBarShowsYouTubePreviewFrames() {
        let app = application(extraArguments: ["--playback-smoke-url", "https://www.youtube.com/watch?v=dQw4w9WgXcQ", "--seek-preview-smoke", "0.3"])
        XCTAssertTrue(app.descendants(matching: .any)["seekBar"].waitForExistence(timeout: 30), "A seek bar under the video")
        XCTAssertTrue(app.images["seekPreviewImage"].waitForExistence(timeout: 20), "A storyboard frame while scrubbing")
    }

    func testInlineControlsReplaceAVKitAndFullscreenUsesAppleControls() {
        let app = application(extraArguments: ["--playback-smoke-url", "https://www.youtube.com/watch?v=dQw4w9WgXcQ"])
        let player = app.descendants(matching: .any)["videoPlayer"].firstMatch
        let seek = app.descendants(matching: .any)["seekBar"].firstMatch
        XCTAssertTrue(seek.waitForExistence(timeout: 30))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "seekBar").count, 1, "One seek bar")
        func showControls() { if !app.buttons["playPause"].exists { player.tap() }; XCTAssertTrue(app.buttons["playPause"].waitForExistence(timeout: 3)) }
        sleep(5)
        XCTAssertFalse(app.buttons["playPause"].exists, "Controls hide while playing")
        showControls()
        XCTAssertTrue(app.buttons["skipBack"].exists); XCTAssertTrue(app.buttons["fullscreen"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["airPlay"].exists)
        app.buttons["playPause"].tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5), "Pausing shows Play")
        let before = seek.value as? String ?? ""
        app.buttons["skipForward"].tap()
        let moved = expectation(for: NSPredicate(format: "value != %@", before), evaluatedWith: seek)
        wait(for: [moved], timeout: 5)
        app.buttons["Play"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Download"].exists, "Download sits in the action row")
        showControls()
        let speed = app.buttons["playbackSpeed"]
        XCTAssertEqual(app.buttons.matching(identifier: "playbackSpeed").count, 1, "Speed lives only in the HUD")
        speed.tap()
        let rate = app.buttons["1.5×"]
        XCTAssertTrue(rate.waitForExistence(timeout: 5)); rate.tap()
        showControls()
        XCTAssertEqual(speed.value as? String, "1.5×")
        speed.tap(); app.buttons["1×"].tap()
        showControls()
        app.buttons["fullscreen"].tap()
        let close = app.buttons.matching(NSPredicate(format: "label IN {'Close', 'Done', 'Dismiss'}")).firstMatch
        if !close.waitForExistence(timeout: 5) { app.otherElements.firstMatch.tap() }
        XCTAssertTrue(close.waitForExistence(timeout: 10), "Apple's full-screen player with its own controls")
        close.tap()
        XCTAssertTrue(seek.waitForExistence(timeout: 10), "Closing full screen returns to DriftLoom's player")
        XCTAssertFalse(close.exists)

        // Turning the phone sideways opens fullscreen; turning it upright closes it again.
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(close.waitForExistence(timeout: 10), "Landscape opens the full-screen player")
        XCUIDevice.shared.orientation = .portrait
        let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: close)
        wait(for: [closed], timeout: 10)
        XCTAssertTrue(seek.waitForExistence(timeout: 5), "Portrait returns to DriftLoom's player")
    }

    func testChaptersAndDoubleTapSeek() {
        // Sample chapters: YouTube refuses most videos that have real ones from test networks.
        let app = application(extraArguments: ["--playback-smoke-url", "https://www.youtube.com/watch?v=dQw4w9WgXcQ", "--chapters-smoke"])
        let player = app.descendants(matching: .any)["videoPlayer"].firstMatch
        let seek = app.descendants(matching: .any)["seekBar"].firstMatch
        XCTAssertTrue(seek.waitForExistence(timeout: 30))
        let chapter = app.staticTexts["currentChapter"]
        XCTAssertTrue(chapter.waitForExistence(timeout: 30), "The playing chapter is named under the seek bar")
        sleep(6) // the playback check jumps to 60 s first
        // "1:05 of 3:33, Chorus" -> 65
        func position() -> Int {
            let time = (seek.value as? String ?? "").components(separatedBy: " ").first ?? ""
            return time.split(separator: ":").reduce(0) { $0 * 60 + (Int($1) ?? 0) }
        }
        let before = position()
        player.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.5)).doubleTap()
        sleep(1)
        XCTAssertTrue((before + 8...before + 14).contains(position()), "Double tap on the right skips 10 s (\(before) -> \(position()))")
        player.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5)).doubleTap()
        sleep(1)
        XCTAssertTrue((before - 2...before + 4).contains(position()), "Double tap on the left goes back 10 s (\(before) -> \(position()))")

        app.buttons["DESCRIPTION"].tap()
        let third = app.buttons["chapter-3"]
        XCTAssertTrue(third.waitForExistence(timeout: 10), "Description lists the chapters")
        let title = chapter.label
        third.tap()
        let changed = expectation(for: NSPredicate(format: "label != %@", title), evaluatedWith: chapter)
        wait(for: [changed], timeout: 10)
        XCTAssertTrue(third.label.contains(chapter.label), "Tapping a chapter jumps to it")
    }

    func testIPadShowsThePlayerBesideTheTabsInLandscape() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad layout") }
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = application(extraArguments: ["--playback-smoke-url", "https://www.youtube.com/watch?v=dQw4w9WgXcQ", "--player-smoke", "hud"])
        let side = app.descendants(matching: .any)["sideBySideDetail"].firstMatch
        XCTAssertTrue(side.waitForExistence(timeout: 30), "Landscape iPad puts the tabs beside the player")
        let player = app.descendants(matching: .any)["videoPlayer"].firstMatch
        XCTAssertTrue(player.waitForExistence(timeout: 30))
        let related = app.buttons.matching(identifier: "sectionTab-0").allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(related)
        if let related { XCTAssertGreaterThan(related.frame.minX, player.frame.maxX - 1, "Tabs sit to the right of the player") }
        sleep(4)
        let close = app.buttons.matching(NSPredicate(format: "label IN {'Close', 'Done', 'Dismiss'}")).firstMatch
        XCTAssertFalse(close.exists, "Turning an iPad doesn't force full screen")
        saveScreenshot("ipad-landscape")
        app.buttons.matching(identifier: "sectionTab-1").allElementsBoundByIndex.first { $0.isHittable }?.tap()
        XCTAssertTrue(app.descendants(matching: .any)["commentSort"].firstMatch.waitForExistence(timeout: 30), "Comments offer a sort order")
        saveScreenshot("ipad-comments")
        XCUIDevice.shared.orientation = .portrait
        let stacked = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: side)
        wait(for: [stacked], timeout: 10)
        saveScreenshot("ipad-portrait")
    }
    /// Screenshots for review when TEST_RUNNER_TOUR_DIR is set.
    private func saveScreenshot(_ name: String) {
        guard let path = ProcessInfo.processInfo.environment["TOUR_DIR"] else { return }
        sleep(1)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: path).appendingPathComponent(name + ".png"))
    }

    func testCommentsCanBeSortedByNewest() {
        let app = application(extraArguments: ["--playback-smoke-url", "https://www.youtube.com/watch?v=dQw4w9WgXcQ"])
        let comments = app.buttons["COMMENTS"]
        XCTAssertTrue(comments.waitForExistence(timeout: 20)); comments.tap()
        let sort = app.descendants(matching: .any)["commentSort"].firstMatch
        XCTAssertTrue(sort.waitForExistence(timeout: 45), "The sort menu appears with the first page")
        XCTAssertEqual(sort.value as? String, "Top comments")
        let first = app.staticTexts["commentText"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 30))
        let topText = first.label
        sort.tap()
        // Menu entries are buttons on iPhone and menu items on iPad.
        let newest = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND (elementType == %d OR elementType == %d)",
            "Newest first", XCUIElement.ElementType.button.rawValue, XCUIElement.ElementType.menuItem.rawValue)).firstMatch
        XCTAssertTrue(newest.waitForExistence(timeout: 5)); newest.tap()
        let reordered = expectation(for: NSPredicate(format: "value == %@", "Newest first"), evaluatedWith: sort)
        wait(for: [reordered], timeout: 10)
        XCTAssertTrue(first.waitForExistence(timeout: 45), "Newest comments load")
        let changed = expectation(for: NSPredicate(format: "label != %@", topText), evaluatedWith: first)
        wait(for: [changed], timeout: 30)
    }

    func testDraggingThePlayerDownMinimizesIt() {
        let app = application(extraArguments: ["--playback-smoke-url", "https://www.youtube.com/watch?v=dQw4w9WgXcQ"])
        let player = app.descendants(matching: .any)["videoPlayer"].firstMatch
        XCTAssertTrue(player.waitForExistence(timeout: 30))
        // A short drag springs back.
        // The middle third drags the player; the sides are brightness and volume swipes.
        let start = player.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 60)))
        sleep(1)
        XCTAssertTrue(player.isHittable, "A short drag keeps the player open")
        XCTAssertFalse(app.buttons["expandMiniPlayer"].exists)
        // A long drag shrinks it into the mini-player, which keeps playing and expands again.
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 420)))
        let mini = app.buttons["expandMiniPlayer"]
        XCTAssertTrue(mini.waitForExistence(timeout: 5), "Dragging down minimizes the player")
        XCTAssertFalse(app.descendants(matching: .any)["videoPlayer"].firstMatch.exists)
        mini.tap()
        XCTAssertTrue(app.descendants(matching: .any)["videoPlayer"].firstMatch.waitForExistence(timeout: 5), "Tapping the bar opens the player again")
        // The header is a handle too.
        let header = app.buttons["minimizePlayer"].coordinate(withNormalizedOffset: CGVector(dx: 3, dy: 0.5))
        header.press(forDuration: 0.05, thenDragTo: header.withOffset(CGVector(dx: 0, dy: 420)))
        XCTAssertTrue(mini.waitForExistence(timeout: 5), "Dragging the header down minimizes too")
    }

    func testAudioOnlyResizeAndBrightnessVolumeSwipes() {
        let app = application(extraArguments: ["--playback-smoke-url", "https://www.youtube.com/watch?v=dQw4w9WgXcQ"])
        let player = app.descendants(matching: .any)["videoPlayer"].firstMatch
        XCTAssertTrue(player.waitForExistence(timeout: 30))
        func showControls() { if !app.buttons["playPause"].exists { player.tap() }; XCTAssertTrue(app.buttons["playPause"].waitForExistence(timeout: 3)) }
        showControls()
        // Resize cycles fit -> zoom -> fill and says which.
        let resize = app.buttons["resizeMode"]
        XCTAssertEqual(resize.value as? String, "Fit")
        resize.tap()
        XCTAssertTrue(app.staticTexts["playerToast"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.buttons["resizeMode"].value as? String, "Zoom")
        // Audio only switches the stream and shows the thumbnail.
        showControls()
        app.buttons["audioOnly"].tap()
        // The stream reloads at the same position, then the thumbnail stands in for the picture.
        XCTAssertTrue(app.descendants(matching: .any)["audioArtwork"].firstMatch.waitForExistence(timeout: 30), "Audio only shows the video's thumbnail")
        showControls()
        XCTAssertEqual(app.buttons["audioOnly"].value as? String, "On")
        // A swipe on the left third is brightness, on the right third volume; neither minimizes the player.
        let left = player.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.75))
        left.press(forDuration: 0.05, thenDragTo: left.withOffset(CGVector(dx: 0, dy: -80)))
        let level = app.descendants(matching: .any)["gestureLevel"].firstMatch
        XCTAssertTrue(level.waitForExistence(timeout: 1), "The swipe shows the brightness level")
        XCTAssertEqual(level.label, "Brightness")
        XCTAssertTrue(player.exists && !app.buttons["expandMiniPlayer"].exists, "Side swipes don't minimize")
        let right = player.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.25))
        right.press(forDuration: 0.05, thenDragTo: right.withOffset(CGVector(dx: 0, dy: 90)))
        XCTAssertTrue(level.waitForExistence(timeout: 1)); XCTAssertEqual(level.label, "Volume")
        XCTAssertTrue(player.exists && !app.buttons["expandMiniPlayer"].exists, "Side swipes don't minimize")
        // Audio only back off; resize back to fit for other tests.
        showControls()
        app.buttons["audioOnly"].tap()
        let video = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.descendants(matching: .any)["audioArtwork"].firstMatch)
        wait(for: [video], timeout: 30)
        XCTAssertTrue(player.waitForExistence(timeout: 30))
        showControls()
        XCTAssertEqual(app.buttons["audioOnly"].value as? String, "Off")
        showControls(); app.buttons["resizeMode"].tap(); showControls(); app.buttons["resizeMode"].tap()
        XCTAssertEqual(app.buttons["resizeMode"].value as? String, "Fit")
    }

    func testPlaybackSettingsOfferAutoplayAndDefaultResolutions() {
        let app = application()
        XCTAssertTrue(app.buttons["mainMenu"].waitForExistence(timeout: 10)); app.buttons["mainMenu"].tap()
        let settings = app.descendants(matching: .any)["drawer-Settings"].firstMatch
        if !settings.isHittable { app.swipeUp() }
        XCTAssertTrue(settings.waitForExistence(timeout: 5)); settings.tap()
        let autoplay = app.switches["autoplayRelated"]
        for _ in 0..<4 where !autoplay.isHittable { app.swipeUp() }
        XCTAssertTrue(autoplay.exists)
        XCTAssertEqual(autoplay.value as? String, "1", "Autoplay is on by default")
        let wifi = app.buttons["wifiResolution"].firstMatch
        XCTAssertTrue(wifi.exists); wifi.tap()
        let choice = app.buttons["Up to 720p"].firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5)); choice.tap()
        XCTAssertTrue(app.buttons["wifiResolution"].firstMatch.label.contains("720"))
        XCTAssertTrue(app.buttons["mobileResolution"].firstMatch.exists)
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
