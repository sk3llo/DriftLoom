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

    /// A tab, once one is on screen. On iPhone it's in the tab bar. iPadOS 18 and later float the tab bar at the top,
    /// where XCTest sees plain buttons labelled with the tab's name and carrying its icon name as identifier.
    private func tabButton(_ app: XCUIApplication, _ title: String, timeout: TimeInterval = 10) -> XCUIElement? {
        let symbol = ["Home": "house", "Subscriptions": "play.rectangle.on.rectangle", "Library": "books.vertical",
                      "Search": "magnifyingglass", "Settings": "gearshape"][title] ?? title
        let inTabBar = app.tabBars.buttons[title]
        let floating = app.buttons.matching(NSPredicate(format: "label == %@ AND (identifier == %@ OR identifier BEGINSWITH %@)",
                                                        title, symbol, symbol + ".")).firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if inTabBar.exists { return inTabBar }
            if floating.exists { return floating }
            usleep(250_000)
        } while Date() < deadline
        return nil
    }
    /// The tab bar is on screen, so launch has finished.
    private func tabsAppear(_ app: XCUIApplication, timeout: TimeInterval = 10) -> Bool { tabButton(app, "Home", timeout: timeout) != nil }
    private func tab(_ app: XCUIApplication, _ title: String) {
        guard let button = tabButton(app, title) else { XCTFail("The \(title) tab"); return }
        button.tap()
    }
    /// Opens a Library page, going back to the Library list first if another page is open.
    private func libraryPage(_ app: XCUIApplication, _ id: String) {
        tab(app, "Library")
        let row = app.buttons[id].firstMatch
        for _ in 0..<3 where !(row.exists && row.isHittable) { app.navigationBars.buttons.element(boundBy: 0).tap(); sleep(1) }
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
    }
    /// The Home title menu, which switches home tabs.
    private func openHomeMenu(_ app: XCUIApplication) {
        let bar = app.navigationBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 10))
        // The title is a button named after the open tab ("Live", or "Live, Actions Menu" on iPhone Duo); on iPad it
        // sits below the floating tab bar, off the bar's middle.
        let title = bar.buttons.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", bar.identifier, bar.identifier + ",")).firstMatch
        if title.exists { title.tap() } else { bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        XCTAssertTrue(app.buttons["Customize tabs"].waitForExistence(timeout: 5), "The title opens the home tab menu")
    }
    private func homeTab(_ app: XCUIApplication, _ title: String) {
        openHomeMenu(app)
        let item = app.buttons[title].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "\(title) is in the home tab menu"); item.tap()
    }
    /// Taps a segment of the visible segmented control that has it.
    private func segment(_ app: XCUIApplication, _ title: String) {
        let button = app.segmentedControls.buttons.matching(NSPredicate(format: "label == %@", title)).allElementsBoundByIndex
        let target = button.first { $0.isHittable } ?? app.segmentedControls.buttons[title].firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 15), "The \(title) segment"); target.tap()
    }
    /// Leaves the search field: "Cancel" up to iOS 18, a round "Close" button from iOS 26 on iPhone. iPadOS has
    /// neither, so there the field is cleared instead.
    private func endSearch(_ app: XCUIApplication) {
        for name in ["Cancel", "Close"] where app.buttons[name].firstMatch.exists { app.buttons[name].firstMatch.tap(); return }
        app.searchFields.firstMatch.buttons["Clear text"].tap()
    }
    private func subscriptionGroup(_ app: XCUIApplication, _ name: String) {
        app.buttons["subscriptionGroupFilter"].firstMatch.tap()
        let item = app.buttons[name].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5)); item.tap()
    }

    func testSettingsTabAndExistingLibraryRemainAccessible() {
        let app = application()
        tab(app, "Settings")
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        for _ in 0..<3 where !app.switches["Record watch history"].exists { app.swipeUp() }
        XCTAssertTrue(app.switches["Record watch history"].exists)
        for _ in 0..<3 where !app.buttons["Backup and import"].exists { app.swipeUp() }
        app.buttons["Backup and import"].tap()
        XCTAssertTrue(app.buttons["Export library backup"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        tab(app, "Subscriptions")
        segment(app, "Channels")
        XCTAssertTrue(app.staticTexts["ndls 404"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Subscriptions"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testSearchPlayerMinimizeAndReturnPreserveResults() {
        let app = application()
        tab(app, "Search")
        let query = app.searchFields.firstMatch
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        query.tap(); query.typeText("NDLS404 SENSOJI\n")
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
        tab(app, "Home")
        XCTAssertTrue(app.buttons["expandMiniPlayer"].waitForExistence(timeout: 5), "The mini-player stays above the tab bar on other tabs")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Home with mini player"; screenshot.lifetime = .keepAlways; add(screenshot)
        tab(app, "Search")
        XCTAssertTrue(result.waitForExistence(timeout: 5), "Search keeps its results across tabs")
    }

    func testKeyboardSearchSubmissionLoadsResults() {
        let app = application()
        tab(app, "Search")
        let query = app.searchFields.firstMatch
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
        tab(app, "Subscriptions"); segment(app, "Channels")
        app.buttons["subscriptionGroupFilter"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Manage subscription groups"].waitForExistence(timeout: 5))
        app.buttons["Manage subscription groups"].tap()
        XCTAssertTrue(app.buttons["createSubscriptionGroup"].waitForExistence(timeout: 5)); app.buttons["createSubscriptionGroup"].tap()
        let name = app.textFields["subscriptionGroupName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Music group")
        let member = app.buttons["groupMember-UCUb-HI7Kd-Dr1fBvYjV1IYg"]
        member.tap(); XCTAssertEqual(member.value as? String, "Selected"); app.buttons["saveSubscriptionGroup"].tap()
        XCTAssertTrue(app.navigationBars["Subscription groups"].waitForExistence(timeout: 5))
        app.buttons["closeSubscriptionGroups"].tap()
        subscriptionGroup(app, "Music group")
        XCTAssertTrue(app.staticTexts["ndls 404"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        tab(app, "Subscriptions"); segment(app, "Channels")
        subscriptionGroup(app, "Music group")
        XCTAssertTrue(app.staticTexts["ndls 404"].waitForExistence(timeout: 5))
        subscriptionGroup(app, "Manage subscription groups")
        let group = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "editGroup-")).firstMatch
        XCTAssertTrue(group.waitForExistence(timeout: 5)); group.tap()
        XCTAssertTrue(app.textFields["subscriptionGroupName"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["subscriptionGroupName"].value as? String, "Music group")
        app.buttons["groupMember-UCUb-HI7Kd-Dr1fBvYjV1IYg"].tap(); app.buttons["saveSubscriptionGroup"].tap()
        XCTAssertTrue(app.buttons["closeSubscriptionGroups"].waitForExistence(timeout: 5)); app.buttons["closeSubscriptionGroups"].tap()
        XCTAssertTrue(app.staticTexts["No channels in this group"].waitForExistence(timeout: 5))
        subscriptionGroup(app, "All subscriptions")
        XCTAssertTrue(app.staticTexts["ndls 404"].waitForExistence(timeout: 5))
        segment(app, "What's new")
        XCTAssertTrue(app.buttons["feedFilters"].waitForExistence(timeout: 5))
        subscriptionGroup(app, "Music group")
        XCTAssertTrue(app.staticTexts["No channels in this feed"].waitForExistence(timeout: 5))
        app.buttons["feedFilters"].tap()
        XCTAssertTrue(app.buttons["Last 7 days"].waitForExistence(timeout: 5)); app.buttons["Last 7 days"].tap()
    }

    func testCommentsLoadForKnownVideo() {
        let app = application()
        let video = app.buttons["browseVideo-11-9ZaYiTPE"].firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 10)); video.tap()
        segment(app, "Comments")
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
        libraryPage(app, "library-downloads")
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
            libraryPage(app, "library-downloads")
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
        tab(app, "Home")
        openHomeMenu(app)
        let entry = app.buttons["Road trip"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "Pinned local playlist must survive relaunch as a home tab")
        XCTAssertGreaterThan(entry.frame.minY, app.buttons["Live"].firstMatch.frame.minY, "New pins follow the sections by default")
        entry.tap()
        XCTAssertTrue(app.buttons["Play all"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Road trip"].exists, "The title names the open tab")

        openHomeMenu(app); app.buttons["Customize tabs"].tap()
        let local = app.descendants(matching: .any)["homeTab-local"].firstMatch
        XCTAssertTrue(local.waitForExistence(timeout: 5))
        // The handle is "Reorder" up to iOS 18 and "Reorder <row>" from iOS 26.
        let reorder = NSPredicate(format: "label BEGINSWITH 'Reorder'")
        let first = app.cells.containing(.any, identifier: "homeTab-section:Live").buttons.matching(reorder).firstMatch
        let handle = app.cells.containing(.any, identifier: "homeTab-local").buttons.matching(reorder).firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        handle.press(forDuration: 0.6, thenDragTo: first)
        app.buttons["closeSheet"].tap()
        openHomeMenu(app)
        XCTAssertLessThan(app.buttons["Road trip"].firstMatch.frame.minY, app.buttons["Live"].firstMatch.frame.minY, "The playlist moved ahead of Live")
        app.terminate(); app.launch()
        tab(app, "Home"); openHomeMenu(app)
        XCTAssertLessThan(app.buttons["Road trip"].firstMatch.frame.minY, app.buttons["Live"].firstMatch.frame.minY, "The order survives relaunch")
    }

    func testHomeTitleMenuSwitchesTabsAndTabsCanBeCustomized() {
        let app = application()
        tab(app, "Home")
        XCTAssertTrue(app.navigationBars["Live"].waitForExistence(timeout: 10), "Home opens on Live, named in the title")
        homeTab(app, "Trending music")
        XCTAssertTrue(app.navigationBars["Trending music"].waitForExistence(timeout: 5), "The title names the open tab")
        openHomeMenu(app)
        app.buttons["Customize tabs"].tap()
        XCTAssertTrue(app.navigationBars["Home tabs"].waitForExistence(timeout: 5), "Customize opens the home tab settings")
        let gaming = app.switches["Gaming"]
        for _ in 0..<3 where !gaming.isHittable { app.swipeUp() }
        gaming.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(gaming.value as? String, "1")
        app.buttons["closeSheet"].tap()
        homeTab(app, "Gaming")
        XCTAssertTrue(app.navigationBars["Gaming"].waitForExistence(timeout: 5), "A tab turned on in Customize is in the menu")
    }

    func testLiveKioskLoadsMoreOnItsOwnAtTheBottom() {
        let app = application()
        tab(app, "Home")
        XCTAssertTrue(app.navigationBars["Live"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'browseVideo-'")).firstMatch.waitForExistence(timeout: 45))
        XCTAssertFalse(app.buttons["Load more"].exists, "There is no Load more button")
        // The kiosk page itself has no continuation; scrolling to the end opens each shelf's full list in turn, with no tap.
        let source = app.staticTexts["kioskSource"]
        let first = loadMoreCount(source)
        XCTAssertGreaterThan(first, 20)
        for _ in 0..<30 { app.swipeUp(velocity: .fast) }
        let grew = expectation(for: NSPredicate { _, _ in self.loadMoreCount(source) > first + 30 }, evaluatedWith: source)
        wait(for: [grew], timeout: 30)
    }
    private func loadMoreCount(_ button: XCUIElement) -> Int { Int((button.value as? String ?? "").split(separator: " ").first ?? "") ?? 0 }

    func testLiveKioskIsTheFirstHomeTab() {
        let app = application()
        tab(app, "Home")
        XCTAssertTrue(app.staticTexts["kioskSource"].waitForExistence(timeout: 10))
        let video = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'browseVideo-'")).firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 45), "The Live kiosk should list videos")
        app.terminate(); app.launch()
        tab(app, "Home")
        XCTAssertTrue(app.navigationBars["Live"].waitForExistence(timeout: 10), "Live is on home")
        openHomeMenu(app)
        XCTAssertLessThan(app.buttons["Live"].firstMatch.frame.minY, app.buttons["Trending music"].firstMatch.frame.minY, "Live is the first home tab")
    }

    func testSoundCloudSearchPlaysTracksAndOpensProfiles() {
        let app = application()
        tab(app, "Search")
        app.segmentedControls["searchService"].buttons["SoundCloud"].tap()
        let query = app.searchFields.firstMatch
        XCTAssertTrue(query.waitForExistence(timeout: 5)); query.tap(); query.typeText("lofi hip hop\n")
        let track = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'searchVideo-sc:'")).firstMatch
        XCTAssertTrue(track.waitForExistence(timeout: 45), "SoundCloud search should list tracks")
        track.tap()
        XCTAssertTrue(app.navigationBars["SoundCloud"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["audioArtwork"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["playbackError"].waitForExistence(timeout: 8), "The track should play")
        app.buttons["minimizePlayer"].tap()
        XCTAssertTrue(app.buttons["expandMiniPlayer"].waitForExistence(timeout: 5))
        segment(app, "Users")
        let profile = app.buttons.matching(NSPredicate(format: "label CONTAINS 'SoundCloud · Channel'")).firstMatch
        XCTAssertTrue(profile.waitForExistence(timeout: 45)); profile.tap()
        let subscribe = app.buttons.matching(NSPredicate(format: "label == 'Subscribe'")).firstMatch
        XCTAssertTrue(subscribe.waitForExistence(timeout: 30)); subscribe.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == 'Subscribed'")).firstMatch.waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        tab(app, "Subscriptions"); segment(app, "Channels")
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
        // A long press shows the notification's actions on iPhone; iPadOS doesn't expand the banner that way in tests.
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        banner.press(forDuration: 1.2)
        let retry = springboard.descendants(matching: .any).matching(NSPredicate(format: "label == 'Retry'")).firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 5), "Failures offer Retry")
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
        XCTAssertTrue(tabsAppear(app))
        try openLink(app, "https://youtu.be/dQw4w9WgXcQ?si=shared")
        XCTAssertTrue(app.buttons["minimizePlayer"].waitForExistence(timeout: 15), "A shared video opens the player")
        app.buttons["minimizePlayer"].tap()
        try openLink(app, "https://www.youtube.com/channel/UCUb-HI7Kd-Dr1fBvYjV1IYg")
        let subscribe = app.buttons.matching(NSPredicate(format: "label IN {'Subscribe', 'Subscribed'}")).firstMatch
        if !subscribe.waitForExistence(timeout: 30) { print("TREEDUMP-A\n" + app.debugDescription + "\nTREEDUMP-END") }
        XCTAssertTrue(subscribe.exists, "A shared channel opens its page")
        app.buttons["Done"].tap()
        try openLink(app, "https://soundcloud.com/lofi_girl")
        XCTAssertTrue(app.navigationBars["Lofi Girl"].waitForExistence(timeout: 30), "A shared SoundCloud profile opens its page")
        app.buttons["Done"].tap()
        try openLink(app, "https://example.com/not-supported")
        XCTAssertTrue(app.alerts["Couldn't open link"].waitForExistence(timeout: 10))
    }

    func testSharedInboxKeepsLaterAndHonorsDiscardAcrossLaunches() {
        let app = application(extraArguments: ["--shared-inbox-smoke", "--shared-inbox-url", "https://youtu.be/dQw4w9WgXcQ"])
        let prompt = app.alerts["Open shared link?"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 10))
        prompt.buttons["Later"].tap()
        XCTAssertTrue(tabsAppear(app))
        app.terminate()
        app.launchArguments.removeAll { $0 == "--library-smoke-seed" }
        app.launch()
        XCTAssertTrue(prompt.waitForExistence(timeout: 10), "Later keeps the shared link after a restart")
        prompt.buttons["Discard"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(tabsAppear(app))
        XCTAssertFalse(prompt.exists, "Discard removes the link permanently")
    }

    func testSharedInboxOpensOnlyAfterConfirmation() {
        let app = application(extraArguments: ["--shared-inbox-smoke", "--shared-inbox-url", "https://youtu.be/dQw4w9WgXcQ"])
        let prompt = app.alerts["Open shared link?"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["minimizePlayer"].exists)
        prompt.buttons["Open"].tap()
        XCTAssertTrue(app.buttons["minimizePlayer"].waitForExistence(timeout: 10))
        app.terminate()
        app.launchArguments.removeAll { $0 == "--library-smoke-seed" }
        app.launch()
        XCTAssertTrue(tabsAppear(app))
        XCTAssertFalse(prompt.exists, "Opening consumes the shared link")
    }

    func testSharingFromSafariSavesOrCopiesWithoutOpeningTheApp() throws {
        try shareFromSafari(expectSaved: false)
    }

    func testPALSharingSavesLinkForTheNextLaunch() throws {
#if DRIFTLOOM_PAL_TESTING
        try shareFromSafari(expectSaved: true)
#else
        throw XCTSkip("Requires PAL.xcconfig, simulator signing and DRIFTLOOM_PAL_TESTING")
#endif
    }

    private func shareFromSafari(expectSaved: Bool) throws {
        let app = application()
        XCTAssertTrue(tabsAppear(app))
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.terminate()
        safari.launch()
        let video = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        if #available(iOS 16.4, *) {
            // Safari's address bar label depends on its leftover state (e.g. "Reader Available"), so open the URL directly.
            XCUIDevice.shared.system.open(URL(string: video)!)
            XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 30))
        } else {
            let address = safari.textFields["TabBarItemTitle"].exists ? safari.textFields["TabBarItemTitle"] : safari.buttons["Address"]
            if address.waitForExistence(timeout: 10) { address.tap() }
            let field = safari.textFields["URL"]
            XCTAssertTrue(field.waitForExistence(timeout: 10)); field.typeText(video + "\n")
        }
        let share = safari.buttons["ShareButton"]
        if !share.waitForExistence(timeout: 10) {
            // iOS 26 and later: Share is in the page menu beside the address.
            let pageMenu = safari.buttons["MoreMenuButton"]
            XCTAssertTrue(pageMenu.waitForExistence(timeout: 20))
            // Safari's compact toolbar can report an invalid accessibility hit point (-1, -1).
            // Tap the center of its on-screen frame, then still require the native Share action.
            XCTAssertTrue(safari.windows.firstMatch.frame.contains(pageMenu.frame), "Safari's menu is on screen")
            pageMenu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        let shareAvailable = share.waitForExistence(timeout: 10)
        if !shareAvailable {
            let screen = XCTAttachment(screenshot: safari.screenshot())
            screen.name = "Safari before sharing"; screen.lifetime = .keepAlways; add(screen)
            print("TREEDUMP-SAFARI\n" + safari.debugDescription + "\nTREEDUMP-END")
        }
        XCTAssertTrue(shareAvailable, "Safari exposes its Share action"); share.tap()
        // Use the Apps list so the test does not depend on suggested-app ordering.
        let more = safari.cells["More"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 10)); more.tap()
        // The icon row remains in the accessibility tree behind the Apps list.
        let target = safari.tables.cells.containing(NSPredicate(format: "label == %@", "DriftLoom")).firstMatch
        if !target.waitForExistence(timeout: 10) { print("TREEDUMP-SHARESHEET\n" + safari.debugDescription + "\nTREEDUMP-END") }
        XCTAssertTrue(target.waitForExistence(timeout: 10), "DriftLoom is in the share sheet")
        let readyToShare = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: target)
        XCTAssertEqual(XCTWaiter.wait(for: [readyToShare], timeout: 10), .completed, "The visible share target is tappable")
        target.tap()
        let done = safari.buttons["finishSharing"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        let saved = safari.staticTexts["sharedLinkSaved"].waitForExistence(timeout: 3)
        XCTAssertEqual(saved, expectSaved, "PAL must use the shared inbox; free-account sideloads must offer Copy link")
        if !saved {
            let copy = safari.buttons["copySharedLink"]
            XCTAssertTrue(copy.waitForExistence(timeout: 10)); copy.tap()
            XCTAssertTrue(safari.staticTexts["Link copied. Open DriftLoom and paste it in Search."].waitForExistence(timeout: 5))
        }
        XCTAssertNotEqual(app.state, .runningForeground, "Sharing must not force the containing app open")
        done.tap(); app.activate()
        if saved {
            let prompt = app.alerts["Open shared link?"]
            XCTAssertTrue(prompt.waitForExistence(timeout: 10)); prompt.buttons["Open"].tap()
            XCTAssertTrue(app.buttons["minimizePlayer"].waitForExistence(timeout: 15))
        } else { XCTAssertTrue(tabsAppear(app)) }
    }

    func testBackupScreenExplainsGoogleTakeoutImport() {
        let app = application()
        tab(app, "Settings")
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
        XCTAssertTrue(tabsAppear(app))
        sleep(8) // the first check only records the current feed
        app.terminate()
        app.launchArguments += ["--feed-check-forget", "2"]
        app.launch()
        let banner = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'CNN'")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 45), "Recent uploads that weren't seen before are announced")
        banner.tap()
        let played = app.buttons["minimizePlayer"].waitForExistence(timeout: 15)
        XCTAssertTrue(played || app.segmentedControls.buttons["What's new"].isSelected, "Tapping plays the video (or opens What's new for a summary)")
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
        wait(for: [moved], timeout: 10)
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

        // Turning the phone sideways opens fullscreen; turning it upright closes it again. An iPad keeps the player
        // beside the tabs instead (testIPadShowsThePlayerBesideTheTabsInLandscape).
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
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

        segment(app, "Description")
        let third = app.buttons["chapter-3"]
        XCTAssertTrue(third.waitForExistence(timeout: 10), "Description lists the chapters")
        third.tap()
        // Wait for the playing chapter to be the tapped one, not just any change (it can pass another on the way).
        let jumped = NSPredicate { _, _ in chapter.exists && !chapter.label.isEmpty && third.label.contains(chapter.label) }
        let reached = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: jumped, object: nil)], timeout: 10) == .completed
        XCTAssertTrue(reached, "Tapping a chapter jumps to it (now \(chapter.exists ? chapter.label : "no chapter shown"))")
    }

    func testIPadShowsThePlayerBesideTheTabsInLandscape() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad layout") }
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = application(extraArguments: ["--playback-smoke-url", "https://www.youtube.com/watch?v=dQw4w9WgXcQ", "--player-smoke", "hud"])
        let side = app.descendants(matching: .any)["sideBySideDetail"].firstMatch
        XCTAssertTrue(side.waitForExistence(timeout: 30), "Landscape iPad puts the tabs beside the player")
        let player = app.descendants(matching: .any)["videoPlayer"].firstMatch
        XCTAssertTrue(player.waitForExistence(timeout: 30))
        let related = app.segmentedControls.buttons.matching(NSPredicate(format: "label == 'Related'")).allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(related)
        if let related { XCTAssertGreaterThan(related.frame.minX, player.frame.maxX - 1, "Tabs sit to the right of the player") }
        sleep(4)
        let close = app.buttons.matching(NSPredicate(format: "label IN {'Close', 'Done', 'Dismiss'}")).firstMatch
        XCTAssertFalse(close.exists, "Turning an iPad doesn't force full screen")
        saveScreenshot("ipad-landscape")
        segment(app, "Comments")
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
        segment(app, "Comments")
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
        // In portrait the sides of the video drag the player too; brightness and volume are full screen only.
        let side = player.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.3))
        side.press(forDuration: 0.05, thenDragTo: side.withOffset(CGVector(dx: 0, dy: 420)))
        XCTAssertTrue(mini.waitForExistence(timeout: 5), "Dragging down from the side minimizes as well")
        XCTAssertFalse(app.descendants(matching: .any)["gestureLevel"].firstMatch.exists, "No brightness change in portrait")
        mini.tap()
        XCTAssertTrue(app.descendants(matching: .any)["videoPlayer"].firstMatch.waitForExistence(timeout: 5))
        // The bar's chevron minimizes too.
        app.buttons["minimizePlayer"].tap()
        XCTAssertTrue(mini.waitForExistence(timeout: 5), "The chevron minimizes the player")
    }

    func testAudioOnlyResizeAndFullScreenBrightnessVolumeSwipes() {
        let app = application(extraArguments: ["--playback-smoke-url", "https://www.youtube.com/watch?v=dQw4w9WgXcQ"])
        let player = app.descendants(matching: .any)["videoPlayer"].firstMatch
        XCTAssertTrue(player.waitForExistence(timeout: 30))
        // The controls hide after 3 s, so bring them back right before each read or tap.
        func control(_ id: String) -> XCUIElement {
            let button = app.buttons[id]
            for _ in 0..<3 {
                if button.exists && button.isHittable { return button }
                if !app.buttons["playPause"].exists { player.tap() }
                _ = button.waitForExistence(timeout: 2)
            }
            XCTFail("\(id) never came on screen")
            return button
        }
        // Resize cycles fit -> zoom -> fill and says which.
        XCTAssertEqual(control("resizeMode").value as? String, "Fit")
        control("resizeMode").tap()
        XCTAssertTrue(app.staticTexts["playerToast"].waitForExistence(timeout: 2))
        XCTAssertEqual(control("resizeMode").value as? String, "Zoom")
        // Audio only switches the stream and shows the thumbnail.
        control("audioOnly").tap()
        // The stream reloads at the same position, then the thumbnail stands in for the picture.
        XCTAssertTrue(app.descendants(matching: .any)["audioArtwork"].firstMatch.waitForExistence(timeout: 30), "Audio only shows the video's thumbnail")
        XCTAssertEqual(control("audioOnly").value as? String, "On")
        // Audio only back off; resize back to fit for other tests.
        control("audioOnly").tap()
        let video = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.descendants(matching: .any)["audioArtwork"].firstMatch)
        wait(for: [video], timeout: 30)
        XCTAssertTrue(player.waitForExistence(timeout: 30))
        XCTAssertEqual(control("audioOnly").value as? String, "Off")
        control("resizeMode").tap(); control("resizeMode").tap()
        XCTAssertEqual(control("resizeMode").value as? String, "Fit")

        // In full screen a swipe on the left third is brightness, on the right third volume. Turning a phone opens
        // full screen; an iPad uses the full-screen button, since turning it keeps the player beside the tabs.
        let phone = UIDevice.current.userInterfaceIdiom == .phone
        if phone { XCUIDevice.shared.orientation = .landscapeLeft } else { control("fullscreen").tap() }
        let close = app.buttons.matching(NSPredicate(format: "label IN {'Close', 'Done', 'Dismiss'}")).firstMatch
        if !close.waitForExistence(timeout: 10) { app.windows.firstMatch.tap() }
        XCTAssertTrue(close.waitForExistence(timeout: 10), "The full-screen player opens")
        let window = app.windows.firstMatch
        // Known gap: in iPad full screen these swipes don't respond yet (AVKit seems to take the touches first), so
        // only iPhone checks them; see "Known gaps" in docs/development.md.
        if phone {
            let left = window.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.7))
            left.press(forDuration: 0.05, thenDragTo: left.withOffset(CGVector(dx: 0, dy: -100)))
            let level = app.descendants(matching: .any)["gestureLevel"].firstMatch
            XCTAssertTrue(level.waitForExistence(timeout: 1), "The swipe shows the brightness level")
            XCTAssertEqual(level.label, "Brightness")
            let right = window.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.3))
            right.press(forDuration: 0.05, thenDragTo: right.withOffset(CGVector(dx: 0, dy: 100)))
            XCTAssertTrue(level.waitForExistence(timeout: 1)); XCTAssertEqual(level.label, "Volume")
        }
        // AVKit hides its controls on its own; a tap brings Close back if the player is still full screen.
        for _ in 0..<2 where !close.exists {
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            _ = close.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(close.exists, "Full screen stays open")
        if phone { XCUIDevice.shared.orientation = .portrait } else { close.tap() }
        let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: close)
        wait(for: [closed], timeout: 10)
    }

    func testCrashFromLastLaunchIsOfferedOnceForReporting() {
        let app = application(extraArguments: ["--diagnostic-smoke"])
        let alert = app.alerts["DriftLoom quit unexpectedly"]
        XCTAssertTrue(alert.waitForExistence(timeout: 15), "A crash iOS reported is offered on launch")
        XCTAssertTrue(alert.buttons["Report on GitHub"].exists && alert.buttons["Copy details"].exists)
        alert.buttons["Don't report"].tap()
        // Dismissed reports never come back.
        app.terminate()
        app.launchArguments.removeAll { $0 == "--diagnostic-smoke" }
        app.launch()
        XCTAssertTrue(tabsAppear(app))
        sleep(3)
        XCTAssertFalse(app.alerts.firstMatch.exists, "Nothing is offered again")
        // A new one goes to GitHub.
        app.terminate()
        app.launchArguments.append("--diagnostic-smoke")
        app.launch()
        XCTAssertTrue(alert.waitForExistence(timeout: 15))
        alert.buttons["Report on GitHub"].tap()
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 15), "The crash report opens as a GitHub issue")
        app.activate()
    }

    func testEndingWhileOnScreenIsOfferedAsAnUnexpectedQuit() {
        // Start without reports left pending by earlier runs; the later launches keep the note this test is about.
        let app = application(extraArguments: ["--exit-check-smoke", "--diagnostic-smoke-clear"])
        app.launchArguments.removeAll { $0 == "--diagnostic-smoke-clear" }
        XCTAssertTrue(tabsAppear(app))
        // Going to the background first is a normal exit.
        XCUIDevice.shared.press(.home); sleep(2)
        app.terminate(); app.launch()
        XCTAssertTrue(tabsAppear(app)); sleep(3)
        XCTAssertFalse(app.alerts["DriftLoom quit unexpectedly"].exists, "Leaving normally isn't a crash")
        // Ended while on screen, as a crash would.
        app.terminate(); app.launch()
        let alert = app.alerts["DriftLoom quit unexpectedly"]
        XCTAssertTrue(alert.waitForExistence(timeout: 15), "Ending while on screen is offered for reporting")
        alert.buttons["Don't report"].tap()
    }

    func testReportAProblemOpensAPrefilledGitHubIssue() {
        let app = application(extraArguments: ["--settings-smoke"])
        let report = app.buttons["reportProblem"]
        for _ in 0..<8 where !(report.exists && report.isHittable) { app.swipeUp() }
        XCTAssertTrue(report.waitForExistence(timeout: 10), "Settings has Report a problem")
        report.tap()
        XCTAssertTrue(app.staticTexts["Report a problem"].waitForExistence(timeout: 5), "It explains before anything opens")
        app.buttons["Copy details"].tap()
        XCTAssertTrue(app.alerts["Details copied"].waitForExistence(timeout: 5))
        app.alerts.buttons.firstMatch.tap()
        report.tap()
        XCTAssertTrue(app.buttons["Open GitHub"].waitForExistence(timeout: 5)); app.buttons["Open GitHub"].tap()
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 15), "The issue opens in the browser")
        // Safari fills the address in once the page starts loading (GitHub may redirect to sign-in first). The field
        // can collapse into a label as the page loads, as on iPad, so look for github.com on either.
        let address = safari.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'URL' OR identifier == 'TabBarItemTitle'")).firstMatch
        let named = safari.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'github.com'")).firstMatch
        var seen = ""
        let onGitHub = NSPredicate { _, _ in
            if named.exists { return true }
            guard address.exists else { return false }
            seen = (address.value as? String) ?? address.label
            return seen.contains("github.com")
        }
        let opened = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: onGitHub, object: nil)], timeout: 25) == .completed
        if !opened { print("TREEDUMP-REPORT-SAFARI\n" + safari.debugDescription + "\nTREEDUMP-END") }
        XCTAssertTrue(opened, "Opened GitHub (\(seen))")
        app.activate()
    }

    func testContentRegionAndLanguageAreSearchable() {
        let app = application(extraArguments: ["--settings-smoke"])
        let region = app.buttons["contentRegion"]
        for _ in 0..<4 where !(region.exists && region.isHittable) { app.swipeUp() }
        XCTAssertTrue(region.waitForExistence(timeout: 10))
        region.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "The region list has a search field")
        search.tap(); search.typeText("ukr")
        let ukraine = app.buttons["localeChoice-UA"]
        XCTAssertTrue(ukraine.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["localeChoice-PT"].exists, "Search narrows the list")
        ukraine.tap()
        XCTAssertTrue(region.waitForExistence(timeout: 5), "Choosing returns to Settings")
        XCTAssertTrue(region.label.contains("Ukraine"), "The row shows the new region (\(region.label))")
        // The current choice is listed first; a code like "pt" finds the language too.
        let language = app.buttons["contentLanguage"]
        language.tap()
        XCTAssertTrue(app.staticTexts["English"].waitForExistence(timeout: 5) || app.buttons["localeChoice-en"].exists)
        app.searchFields.firstMatch.tap(); app.searchFields.firstMatch.typeText("pt")
        XCTAssertTrue(app.buttons["localeChoice-pt"].waitForExistence(timeout: 5), "A language can be found by its code")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        // Back to Portugal for the other tests.
        XCTAssertTrue(region.waitForExistence(timeout: 5)); region.tap()
        app.searchFields.firstMatch.tap(); app.searchFields.firstMatch.typeText("Portugal")
        XCTAssertTrue(app.buttons["localeChoice-PT"].waitForExistence(timeout: 5)); app.buttons["localeChoice-PT"].tap()
        XCTAssertTrue(region.waitForExistence(timeout: 5))
        XCTAssertTrue(region.label.contains("Portugal"))
    }

    func testLanguageRowOpensDriftLoomInTheSettingsApp() {
        let app = application()
        tab(app, "Settings")
        let language = app.buttons["interfaceLanguage"]
        XCTAssertTrue(language.waitForExistence(timeout: 5))
        XCTAssertEqual(language.value as? String, "English", "The row names the current interface language")
        language.tap()
        let preferences = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        XCTAssertTrue(preferences.wait(for: .runningForeground, timeout: 10), "It opens the Settings app")
        app.activate()
    }

    func testPlayerShowsElapsedAndTotalTime() {
        let app = application(extraArguments: ["--playback-smoke-url", "https://www.youtube.com/watch?v=dQw4w9WgXcQ"])
        let total = app.staticTexts["totalTime"]
        XCTAssertTrue(total.waitForExistence(timeout: 30), "The video's length is shown")
        XCTAssertEqual(total.label, "3:33")
        let elapsed = app.staticTexts["elapsedTime"]
        XCTAssertTrue(elapsed.exists)
        let start = elapsed.label
        let moving = expectation(for: NSPredicate(format: "label != %@", start), evaluatedWith: elapsed)
        wait(for: [moving], timeout: 15)
        XCTAssertTrue(elapsed.label.range(of: "^[0-9]+:[0-9]{2}$", options: .regularExpression) != nil, "Elapsed time reads like 1:05")
    }

    func testSearchKeepsResultsAcrossTabsAndCancelShowsPreviousSearches() {
        let app = application()
        tab(app, "Search")
        let query = app.searchFields.firstMatch
        XCTAssertTrue(query.waitForExistence(timeout: 5)); query.tap(); query.typeText("lofi")
        let suggestion = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "searchSuggestion-")).firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 15))
        query.typeText("\n")
        let result = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "searchVideo-")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 45))
        XCTAssertFalse(suggestion.exists, "Searching hides the suggestions")
        tab(app, "Home"); tab(app, "Search")
        XCTAssertTrue(result.waitForExistence(timeout: 5), "The previous results are back")
        XCTAssertEqual(query.value as? String, "lofi", "The field shows the search the results are for")
        // Editing again suggests; Cancel empties the field and lists previous searches; one tap searches again.
        query.tap(); query.typeText(" beats")
        XCTAssertTrue(suggestion.waitForExistence(timeout: 15))
        endSearch(app)
        let previous = app.buttons["searchHistory-lofi"]
        XCTAssertTrue(previous.waitForExistence(timeout: 5), "An empty field shows previous searches")
        XCTAssertFalse(result.exists)
        previous.tap()
        XCTAssertTrue(result.waitForExistence(timeout: 45), "A previous search runs again")
    }

    func testUserGuideOpensFromSettings() {
        let app = application()
        tab(app, "Settings")
        let guide = app.buttons["openUserGuide"]
        for _ in 0..<8 where !guide.isHittable { app.swipeUp() }
        guide.tap()
        // Search across the pages.
        let search = app.searchFields.firstMatch
        if !search.waitForExistence(timeout: 3) { app.swipeDown() }
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("Takeout")
        XCTAssertTrue(app.buttons["guidePage-backup-and-import.md"].waitForExistence(timeout: 5), "Search finds pages by their text")
        XCTAssertFalse(app.buttons["guidePage-player.md"].exists)
        endSearch(app)
        let player = app.buttons["guidePage-player.md"]
        for _ in 0..<4 where !(player.exists && player.isHittable) { app.swipeUp() }
        XCTAssertTrue(player.waitForExistence(timeout: 5), "The guide lists its pages")
        player.tap()
        XCTAssertTrue(app.staticTexts["Controls on the video"].waitForExistence(timeout: 5), "A page shows its headings")
        XCTAssertTrue(app.images["The player with its controls showing"].exists, "and its screenshots")
        for _ in 0..<12 where !app.buttons["guideNext"].isHittable { app.swipeUp() }
        app.buttons["guideNext"].tap()
        XCTAssertTrue(app.staticTexts["Playback speed"].waitForExistence(timeout: 5), "Next goes to the following page")
    }

    func testPlaybackSettingsOfferAutoplayAndDefaultResolutions() {
        let app = application()
        tab(app, "Settings")
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
        tab(app, "Subscriptions"); segment(app, "Channels")
        let actions = app.buttons["itemActions-channel:UCUb-HI7Kd-Dr1fBvYjV1IYg"].firstMatch
        XCTAssertTrue(actions.waitForExistence(timeout: 10)); actions.tap()
        app.buttons["Add to home"].tap()
        app.terminate(); app.launch()
        tab(app, "Home")
        homeTab(app, "ndls 404")
        XCTAssertTrue(app.navigationBars["ndls 404"].waitForExistence(timeout: 10), "The pinned channel opens as a home tab")
        app.buttons["pinnedTabOptions"].tap(); app.buttons["Remove from home"].tap()
        app.terminate(); app.launch()
        tab(app, "Home"); openHomeMenu(app)
        XCTAssertFalse(app.buttons["ndls 404"].exists)
    }

    func testSuggestionSelectionSubmitsTheSuggestedQuery() {
        let app = application()
        tab(app, "Search")
        let query = app.searchFields.firstMatch
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
        tab(app, "Home")
        homeTab(app, "Trending music")
        XCTAssertTrue(app.staticTexts["YouTube Charts · PT"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "browseVideo-")).firstMatch.waitForExistence(timeout: 35))
    }


}
