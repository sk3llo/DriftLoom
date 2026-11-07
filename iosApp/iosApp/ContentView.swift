// SPDX-License-Identifier: GPL-3.0-or-later
import AVFoundation
import DriftLoomPlayback
import SwiftUI
import UIKit

extension Notification.Name {
    static let driftLoomExpandPlayer = Notification.Name("DriftLoom.expandPlayer")
    static let driftLoomAddToPlaylist = Notification.Name("DriftLoom.addToPlaylist")
    /// Object: the URL to open (a YouTube/SoundCloud link or a driftloom://open link).
    static let driftLoomOpenLink = Notification.Name("DriftLoom.openLink")
}

struct ContentView: View {
    @StateObject private var playback: PlaybackSession
    @StateObject private var queue: PlaybackQueue
    @StateObject private var positions: PlaybackPositions
    @StateObject private var library = makeLibraryStore()
    @StateObject private var playlists = makePlaylistStore()
    @StateObject private var preferences = makePreferences()
    @StateObject private var pinnedTabs = PinnedHomeTabs(fileURL: libraryFileURL().deletingLastPathComponent().appendingPathComponent("home-tabs.json"))
    @StateObject private var subscriptionGroups = makeSubscriptionGroups()
    @StateObject private var network = NetworkStatus()
    @State private var historyRecorder: LibraryPlaybackRecorder?
    @State private var nowPlaying: NowPlayingController?
    @State private var selectedSection = HomeSection.live
    @State private var tab = AppTab.home
    @State private var subscriptionsPage = SubscriptionsView.Page.feed
    @State private var libraryRequest: LibraryRequest?
    @State private var expanded = false
    @State private var addingToPlaylist: BrowseItem?
    @State private var linkedPage: LinkedPage?
    @State private var linkError: String?
    @State private var linkTask: Task<Void, Never>?
    @State private var configured = false
    @Environment(\.scenePhase) private var scenePhase
    private struct LinkedPage: Identifiable { let id = UUID(); let route: BrowseRoute }

    init() {
        let positions = PlaybackPositions(defaults: makeAppDefaults())
        let playback = PlaybackSession(positions: positions, subtitles: YouTubeSubtitleClient())
        playback.localMedia = { id in
            let manager = DownloadManager.shared
            return manager.records.first(where: { $0.item.contentID == id && manager.localURL($0) != nil }).flatMap(manager.localURL)
        }
        // Saved subtitles are used only when this video plays from its download.
        playback.localSubtitles = { [weak playback] id in
            guard playback?.video?.streamURL.isFileURL == true || playback?.localMedia?(id) != nil else { return nil }
            return DownloadManager.shared.localSubtitles(videoID: id)
        }
        _positions = StateObject(wrappedValue: positions)
        _playback = StateObject(wrappedValue: playback)
        _queue = StateObject(wrappedValue: PlaybackQueue(playback: playback, archiveURL: libraryFileURL().deletingLastPathComponent().appendingPathComponent("queue.json")))
    }
    var body: some View {
        ZStack {
            TabView(selection: $tab) {
                HomeView(selection: $selectedSection, onPlay: play).modifier(bottomAccessory)
                    .tabItem { Label("Home", systemImage: "house") }.tag(AppTab.home)
                SubscriptionsView(onPlay: play, page: $subscriptionsPage).modifier(bottomAccessory)
                    .tabItem { Label("Subscriptions", systemImage: "play.square.stack") }.tag(AppTab.subscriptions)
                LibraryTabView(onPlay: play, request: $libraryRequest).modifier(bottomAccessory)
                    .tabItem { Label("Library", systemImage: "books.vertical") }.tag(AppTab.library)
                SearchView(onPlay: play).modifier(bottomAccessory)
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }.tag(AppTab.search)
                SettingsView().modifier(bottomAccessory)
                    .tabItem { Label("Settings", systemImage: "gearshape") }.tag(AppTab.settings)
            }
            .accessibilityHidden(expanded).allowsHitTesting(!expanded)
            if expanded {
                VideoDetailView(playback: playback, onCollapse: { expanded = false }, onPlay: play)
                    .background(Color(.systemBackground)).transition(.move(edge: .bottom)).zIndex(2)
            }
        }
        .background(Color(.systemBackground))
        .environmentObject(library).environmentObject(queue).environmentObject(preferences).environmentObject(playlists).environmentObject(pinnedTabs).environmentObject(subscriptionGroups).environmentObject(positions)
        .tint(AppStyle.accent).accentColor(AppStyle.accent)
        .preferredColorScheme(preferences.appearance == "Dark" ? .dark : preferences.appearance == "Light" ? .light : nil)
        .alert("Library", isPresented: Binding(get: { library.lastError != nil || playlists.lastError != nil || queue.storageError != nil || pinnedTabs.error != nil || subscriptionGroups.error != nil }, set: {
            if !$0 { library.dismissError(); playlists.dismissError(); queue.dismissStorageError(); pinnedTabs.dismissError(); subscriptionGroups.dismissError() }
        })) { Button("OK") { library.dismissError(); playlists.dismissError(); queue.dismissStorageError(); pinnedTabs.dismissError(); subscriptionGroups.dismissError() } } message: { Text(library.lastError ?? playlists.lastError ?? queue.storageError ?? pinnedTabs.error ?? subscriptionGroups.error ?? "") }
        .sheet(item: $addingToPlaylist) { item in PlaylistPickerView(item: item).environmentObject(playlists) }
        .onReceive(NotificationCenter.default.publisher(for: .driftLoomAddToPlaylist)) { addingToPlaylist = $0.object as? BrowseItem }
        .onReceive(NotificationCenter.default.publisher(for: .driftLoomExpandPlayer)) { _ in expanded = true }
        .onReceive(NotificationCenter.default.publisher(for: .driftLoomOpenDownloads)) { _ in
            expanded = false; dismissKeyboard(); tab = .library; libraryRequest = LibraryRequest(page: "downloads")
        }
        .onOpenURL { url in openLink(url) }
        .modifier(CrashReportPrompt(inbox: .shared))
        .onReceive(NotificationCenter.default.publisher(for: .driftLoomOpenLink)) { if let url = $0.object as? URL { openLink(url) } }
        .onReceive(NotificationCenter.default.publisher(for: .driftLoomOpenFeed)) { _ in
            expanded = false; dismissKeyboard(); linkedPage = nil; tab = .subscriptions; subscriptionsPage = .feed
        }
        .onReceive(NotificationCenter.default.publisher(for: .driftLoomPlayVideo)) { note in
            guard let id = note.object as? String, (try? VideoRequest(input: id))?.videoID == id else { return }
            dismissKeyboard(); linkedPage = nil
            play(BrowseItem(contentID: id, kind: .video, title: SoundCloudID.isSoundCloud(id) ? String(localized: "SoundCloud track") : PlaybackSession.placeholderTitle))
        }
        .onChange(of: scenePhase) { if $0 == .background { FeedRefresher.shared.schedule() } }
        .sheet(item: $linkedPage) { page in
            AppNavigation {
                BrowsePageView(route: page.route, onPlay: { item in linkedPage = nil; play(item) })
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { linkedPage = nil }.accessibilityIdentifier("closeSheet") } }
            }
            .environmentObject(library).environmentObject(queue).environmentObject(preferences).environmentObject(playlists)
            .environmentObject(pinnedTabs).environmentObject(subscriptionGroups).environmentObject(positions)
        }
        .alert("Couldn't open link", isPresented: Binding(get: { linkError != nil }, set: { if !$0 { linkError = nil } })) {
            Button("OK") { linkError = nil }
        } message: { Text(linkError ?? "") }
        .onChange(of: preferences.homeSections) { values in
            if !HomeSection.shownOnHome(values).contains(selectedSection) { selectedSection = HomeSection.shownOnHome(values)[0] }
        }
        .onChange(of: preferences.resumesPlayback) { playback.resumesPositions = $0 }
        .onChange(of: preferences.subtitleLanguage) { playback.preferredSubtitleLanguage = $0 }
        .onChange(of: preferences.translatesSubtitles) { playback.translatesSubtitles = $0 }
        .onChange(of: preferences.autoplaysRelated) { queue.autoplaysRelated = $0 }
        .onChange(of: defaultMaximumHeight) { playback.defaultMaximumHeight = $0 }
        .onChange(of: library.historyEnabled) { playback.remembersPositions = $0 && library.isWritable }
        .onChange(of: library.isWritable) { playback.remembersPositions = $0 && library.historyEnabled }
        .onChange(of: library.history.map { $0.item.contentID }) { ids in
            if library.isWritable { positions.retainOnly(Set(ids)) }
        }
        .task {
            // Runs again whenever the window's content reappears (e.g. after a full-screen presentation).
            guard !configured else { return }
            configured = true
            playback.remembersPositions = library.historyEnabled && library.isWritable
            playback.resumesPositions = preferences.resumesPlayback
            playback.preferredSubtitleLanguage = preferences.subtitleLanguage
            playback.translatesSubtitles = preferences.translatesSubtitles
            queue.autoplaysRelated = preferences.autoplaysRelated
            playback.defaultMaximumHeight = defaultMaximumHeight
            playback.onSubtitleChoice = { [weak preferences] in preferences?.setSubtitleLanguage($0) }
            if library.isWritable { positions.retainOnly(Set(library.history.map { $0.item.contentID })) }
            if preferences.movedLiveFirst { pinnedTabs.moveToFront(.section(.live)) }
            selectedSection = HomeSection.shownOnHome(preferences.homeSections)[0]
            if historyRecorder == nil { historyRecorder = LibraryPlaybackRecorder(playback: playback, library: library) }
            if nowPlaying == nil { nowPlaying = NowPlayingController(playback: playback, queue: queue) }
#if DEBUG || DRIFTLOOM_DEVICE_TESTING
            let arguments = ProcessInfo.processInfo.arguments
            let searching = arguments.contains("--browse-smoke-query") || arguments.contains("--suggestion-smoke")
            if searching { tab = .search }
            if arguments.contains("--library-smoke-run") {
                runLibrarySmokeSetup(library)
                if let flag = arguments.firstIndex(of: "--library-smoke-section"), arguments.indices.contains(flag + 1) {
                    switch arguments[flag + 1] {
                    case "Home": tab = .home
                    case "History": tab = .library; libraryRequest = LibraryRequest(page: "history")
                    case "Subscriptions": tab = .subscriptions; subscriptionsPage = .channels
                    default: tab = .library; libraryRequest = LibraryRequest(page: "bookmarks")
                    }
                } else if !searching { tab = .library; libraryRequest = LibraryRequest(page: "bookmarks") }
            }
            // --settings-smoke, --guide-smoke: open Settings at launch, for device screenshots.
            if arguments.contains("--settings-smoke") || arguments.contains("--guide-smoke") { tab = .settings }
            // --feed-smoke: open What's new, for device screenshots.
            if arguments.contains("--feed-smoke") { tab = .subscriptions; subscriptionsPage = .feed }
            if arguments.contains("--playback-smoke-url") || arguments.contains("--autoplay-smoke") { expanded = true }
            await runPlaybackSmokeCheck(playback)
            await runAutoplaySmokeCheck(queue)
            await runBackgroundSmokeCheck(playback)
            await runDownloadSmokeCheck(playback)
            runDiagnosticSmoke()
            await runKioskSmokeCheck()
            await runSoundCloudSmokeCheck()
            await FeedRefresher.shared.runSmokeCheck()
            await runImportSmokeCheck(library: library, playlists: playlists, groups: subscriptionGroups, positions: positions,
                                      preferences: preferences, pinnedTabs: pinnedTabs)
#endif
        }
    }
    /// The resolution cap for the current connection.
    private var defaultMaximumHeight: Int { network.isMobileData ? preferences.mobileMaximumHeight : preferences.wifiMaximumHeight }
    private func play(_ item: BrowseItem) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        queue.start([item]); expanded = true
    }
    /// Links from other apps (share extension, driftloom:// URLs) and from the in-app link box:
    /// videos and tracks play; channels, profiles and playlists open as a page.
    private func openLink(_ url: URL) {
        guard let link = SharedLink.target(of: url) else {
            linkError = String(localized: "DriftLoom opens YouTube and SoundCloud links."); return
        }
        linkTask?.cancel()
        dismissKeyboard(); linkedPage = nil
        if let target = LinkResolver.immediate(link) { show(target); return }
        linkTask = Task {
            do {
                let target = try await LinkResolver.resolve(link)
                if !Task.isCancelled { show(target) }
            } catch { if !Task.isCancelled { linkError = error.localizedDescription } }
        }
    }
    private func show(_ target: LinkTarget) {
        switch target {
        case let .play(item): play(item)
        case let .browse(route): expanded = false; linkedPage = LinkedPage(route: route)
        }
    }
    /// The download strip and mini-player sit above the tab bar, on every page of every tab.
    private var bottomAccessory: BottomAccessory {
        BottomAccessory(playback: playback, expanded: expanded, onExpand: { expanded = true }, onStop: queue.stop)
    }
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

@MainActor
private func makePreferences() -> AppPreferences {
    AppPreferences(defaults: makeAppDefaults())
}

@MainActor
func makeAppDefaults() -> UserDefaults {
#if DEBUG || DRIFTLOOM_DEVICE_TESTING
    let arguments = ProcessInfo.processInfo.arguments
    if let flag = arguments.firstIndex(of: "--library-smoke-run"), arguments.indices.contains(flag + 1),
       arguments[flag + 1].range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil,
       let defaults = UserDefaults(suiteName: "DriftLoom.Smoke." + arguments[flag + 1]) { return defaults }
#endif
    return .standard
}

struct BottomAccessory: ViewModifier {
    @ObservedObject var playback: PlaybackSession
    let expanded: Bool
    let onExpand: () -> Void
    let onStop: () -> Void
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                DownloadProgressStrip()
                if playback.videoID != nil, !expanded { MiniPlayer(playback: playback, onExpand: onExpand, onStop: onStop) }
            }
        }
    }
}

struct MiniPlayer: View {
    @ObservedObject var playback: PlaybackSession
    let onExpand: () -> Void
    let onStop: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 4) {
                Button(action: onExpand) {
                    HStack(spacing: 10) {
                        AsyncImage(url: playback.currentItemMetadata?.thumbnail) { $0.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.2) }
                            .frame(width: 72, height: 42).clipped().accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(playback.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                            Text(playback.sourceItem?.subtitle ?? "YouTube").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.buttonStyle(.plain).accessibilityIdentifier("expandMiniPlayer")
                Button(action: playback.togglePlayPause) {
                    Image(systemName: playback.phase == .playing ? "pause.fill" : "play.fill").frame(width: 44, height: 52)
                }.accessibilityLabel(playback.phase == .playing ? "Pause" : "Play")
                Button(action: onStop) { Image(systemName: "xmark").frame(width: 40, height: 52) }.accessibilityLabel("Close player")
            }.padding(.leading, 8).background(Color(.secondarySystemBackground))
        }
    }
}
