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
    /// Download journeys need live extraction. The seeded fixture is sometimes refused by YouTube's
    /// bot check on test networks, so open a widely available video through the playback smoke path.
    private static let liveVideo = ["--playback-smoke-url", "https://www.youtube.com/watch?v=dQw4w9WgXcQ"]

    func testDownloadChooserAndDeviceOfflinePlayback() {
        let app = application(extraArguments: Self.liveVideo)
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

    func testQueuedDownloadNetworkPolicyAndRelaunchRecovery() {
        let app = application(extraArguments: ["--download-smoke-no-network"] + Self.liveVideo)
        XCTAssertTrue(app.buttons["Playback options"].waitForExistence(timeout: 15))
        app.buttons["Playback options"].tap(); app.buttons["Download"].tap()
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
        let tab = app.buttons["ROAD TRIP"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "Pinned local playlist must survive relaunch as a home tab")
        let subscriptions = app.buttons["SUBSCRIPTIONS"]
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
        XCTAssertTrue(app.buttons["ROAD TRIP"].waitForExistence(timeout: 10))
        XCTAssertLessThan(app.buttons["ROAD TRIP"].frame.minX, app.buttons["SUBSCRIPTIONS"].frame.minX, "The interleaved order survives relaunch")
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
        XCTAssertTrue(app.buttons["LIVE"].waitForExistence(timeout: 10), "Live is on home")
        XCTAssertLessThan(app.buttons["LIVE"].frame.minX, app.buttons["SUBSCRIPTIONS"].frame.minX, "Live is the first home tab")
    }

    func testSoundCloudSearchPlaysTracksAndOpensProfiles() {
        let app = application()
        XCTAssertTrue(app.buttons["openSearch"].waitForExistence(timeout: 10)); app.buttons["openSearch"].tap()
        app.segmentedControls["searchService"].buttons["SoundCloud"].tap()
        let query = app.textFields["searchQuery"]
        XCTAssertTrue(query.waitForExistence(timeout: 5)); query.tap(); query.typeText("lofi hip hop")
        app.buttons["submitSearch"].tap()
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
