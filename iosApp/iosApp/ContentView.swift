// SPDX-License-Identifier: GPL-3.0-or-later
import AVFoundation
import DriftLoomPlayback
import SwiftUI
import UIKit

extension Notification.Name {
    static let driftLoomExpandPlayer = Notification.Name("DriftLoom.expandPlayer")
    static let driftLoomAddToPlaylist = Notification.Name("DriftLoom.addToPlaylist")
}

struct ContentView: View {
    @StateObject private var playback: PlaybackSession
    @StateObject private var queue: PlaybackQueue
    @StateObject private var positions: PlaybackPositions
    @StateObject private var library = makeLibraryStore()
    @StateObject private var playlists = makePlaylistStore()
    @StateObject private var preferences = makePreferences()
    @State private var historyRecorder: LibraryPlaybackRecorder?
    @State private var nowPlaying: NowPlayingController?
    @State private var selectedSection = HomeSection.subscriptions
    @State private var searching = false
    @State private var expanded = false
    @State private var addingToPlaylist: BrowseItem?

    init() {
        let positions = PlaybackPositions(defaults: makeAppDefaults())
        let playback = PlaybackSession(positions: positions)
        _positions = StateObject(wrappedValue: positions)
        _playback = StateObject(wrappedValue: playback)
        _queue = StateObject(wrappedValue: PlaybackQueue(playback: playback))
    }
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ZStack {
                    HomeView(selection: $selectedSection, onSearch: { searching = true }, onPlay: play)
                        .opacity(searching ? 0 : 1).allowsHitTesting(!searching).accessibilityHidden(searching)
                    // Keep the search hierarchy mounted so player dismissal restores its results and scroll.
                    SearchView(onPlay: play, onClose: closeSearch)
                        .opacity(searching ? 1 : 0).allowsHitTesting(searching).accessibilityHidden(!searching)
                }
                if playback.videoID != nil, !expanded {
                    MiniPlayer(playback: playback, onExpand: { expanded = true }, onStop: queue.stop)
                }
            }
            if expanded {
                VideoDetailView(playback: playback, onCollapse: { expanded = false }, onPlay: play)
                    .background(Color(.systemBackground)).transition(.move(edge: .bottom)).zIndex(2)
            }
        }
        .background(Color(.systemBackground))
        .environmentObject(library).environmentObject(queue).environmentObject(preferences).environmentObject(playlists)
        .tint(AppStyle.accent).accentColor(AppStyle.accent)
        .preferredColorScheme(preferences.appearance == "Dark" ? .dark : preferences.appearance == "Light" ? .light : nil)
        .alert("Library", isPresented: Binding(get: { library.lastError != nil || playlists.lastError != nil }, set: {
            if !$0 { library.dismissError(); playlists.dismissError() }
        })) { Button("OK") { library.dismissError(); playlists.dismissError() } } message: { Text(library.lastError ?? playlists.lastError ?? "") }
        .sheet(item: $addingToPlaylist) { item in PlaylistPickerView(item: item).environmentObject(playlists) }
        .onReceive(NotificationCenter.default.publisher(for: .driftLoomAddToPlaylist)) { addingToPlaylist = $0.object as? BrowseItem }
        .onReceive(NotificationCenter.default.publisher(for: .driftLoomExpandPlayer)) { _ in expanded = true }
        .onOpenURL { url in openLink(url.absoluteString) }
        .onChange(of: preferences.homeSections) { values in
            if !values.contains(selectedSection), let first = values.first { selectedSection = first }
        }
        .onChange(of: preferences.resumesPlayback) { playback.resumesPositions = $0 }
        .onChange(of: library.historyEnabled) { playback.remembersPositions = $0 && library.isWritable }
        .onChange(of: library.isWritable) { playback.remembersPositions = $0 && library.historyEnabled }
        .onChange(of: library.history.map { $0.item.contentID }) { ids in
            if library.isWritable { positions.retainOnly(Set(ids)) }
        }
        .task {
            playback.remembersPositions = library.historyEnabled && library.isWritable
            playback.resumesPositions = preferences.resumesPlayback
            if library.isWritable { positions.retainOnly(Set(library.history.map { $0.item.contentID })) }
            selectedSection = preferences.homeSections.first ?? .subscriptions
            if historyRecorder == nil { historyRecorder = LibraryPlaybackRecorder(playback: playback, library: library) }
            if nowPlaying == nil { nowPlaying = NowPlayingController(playback: playback, queue: queue) }
#if DEBUG || DRIFTLOOM_DEVICE_TESTING
            let arguments = ProcessInfo.processInfo.arguments
            searching = arguments.contains("--browse-smoke-query")
            if arguments.contains("--library-smoke-run") {
                runLibrarySmokeSetup(library)
                if let flag = arguments.firstIndex(of: "--library-smoke-section"), arguments.indices.contains(flag + 1) {
                    selectedSection = arguments[flag + 1] == "History" ? .history : arguments[flag + 1] == "Subscriptions" ? .subscriptions : .bookmarks
                } else if !searching { selectedSection = .bookmarks }
            }
            if arguments.contains("--playback-smoke-url") { expanded = true }
            await runPlaybackSmokeCheck(playback)
            await runBackgroundSmokeCheck(playback)
#endif
        }
    }
    private func play(_ item: BrowseItem) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        queue.start([item]); expanded = true
    }
    private func openLink(_ input: String) {
        guard let request = try? VideoRequest(input: input) else { return }
        play(BrowseItem(contentID: request.videoID, kind: .video, title: "YouTube video"))
    }
    private func closeSearch() {
        searching = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

@MainActor
private func makePreferences() -> AppPreferences {
    AppPreferences(defaults: makeAppDefaults())
}

@MainActor
private func makeAppDefaults() -> UserDefaults {
#if DEBUG || DRIFTLOOM_DEVICE_TESTING
    let arguments = ProcessInfo.processInfo.arguments
    if let flag = arguments.firstIndex(of: "--library-smoke-run"), arguments.indices.contains(flag + 1),
       arguments[flag + 1].range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil,
       let defaults = UserDefaults(suiteName: "DriftLoom.Smoke." + arguments[flag + 1]) { return defaults }
#endif
    return .standard
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
