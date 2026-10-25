import AVKit
import DriftLoomPlayback
import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var playback = PlaybackSession()
    @StateObject private var library = makeLibraryStore()
    @State private var historyRecorder: LibraryPlaybackRecorder?
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            SearchView(onPlay: play)
                .tabItem { Label("Discover", systemImage: "magnifyingglass") }.tag(0)
            PlaybackView(playback: playback)
                .tabItem { Label("Watch", systemImage: "play.rectangle") }.tag(1)
            LibraryView(onPlay: play)
                .tabItem { Label("Library", systemImage: "books.vertical") }.tag(2)
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }.tag(3)
        }
        .environmentObject(library)
        .tint(.teal)
        .accentColor(.teal)
        .alert("Library", isPresented: Binding(get: { library.lastError != nil }, set: {
            if !$0 { library.dismissError() }
        })) {
            Button("OK") { library.dismissError() }
        } message: { Text(library.lastError ?? "") }
        .task {
            if historyRecorder == nil { historyRecorder = LibraryPlaybackRecorder(playback: playback, library: library) }
#if DEBUG || DRIFTLOOM_DEVICE_TESTING
            if ProcessInfo.processInfo.arguments.contains("--library-smoke-run") {
                if !ProcessInfo.processInfo.arguments.contains("--browse-smoke-query") { selectedTab = 2 }
                runLibrarySmokeSetup(library)
            }
            if ProcessInfo.processInfo.arguments.contains("--playback-smoke-url") { selectedTab = 1 }
            await runPlaybackSmokeCheck(playback)
#endif
        }
        .onOpenURL { url in
            selectedTab = 1
            playback.open(url.absoluteString)
        }
    }

    private func play(_ item: BrowseItem) {
        selectedTab = 1
        playback.open(item)
    }
}

private struct PlaybackView: View {
    @EnvironmentObject private var library: LibraryStore
    @ObservedObject var playback: PlaybackSession
    @State private var input = ""
    @State private var showsLicenses = false

    var body: some View {
        AppNavigation {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("A little room to explore.")
                        .font(.title2.weight(.semibold))
                    Text("Paste a YouTube link to start watching.")
                        .foregroundStyle(.secondary)
                    HStack(alignment: .top) {
                        TextField("YouTube video link", text: $input)
                            .textContentType(.URL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.go)
                            .onSubmit(openVideo)
                            .accessibilityIdentifier("videoURL")
                        Button(action: openVideo) { Image(systemName: "arrow.right") }
                            .buttonStyle(.borderedProminent)
                            .accessibilityLabel("Open video")
                            .accessibilityIdentifier("openVideo")
                            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if playback.player.currentItem != nil {
                        VideoPlayer(player: playback.player)
                            .aspectRatio(16 / 9, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .accessibilityIdentifier("videoPlayer")
                        Text(playback.title).font(.headline)
                        if let item = playback.currentItemMetadata {
                            IconButton(library.isSaved(item.contentID) ? "Saved" : "Save video",
                                   systemImage: library.isSaved(item.contentID) ? "bookmark.fill" : "bookmark") {
                                library.toggleSaved(item)
                            }
                            .buttonStyle(.bordered)
                            .disabled(!library.isWritable)
                        }
                    }
                    status
                    if playback.didRecover {
                        Label("Stream refreshed. Continuing playback.", systemImage: "arrow.clockwise")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if let videoID = playback.videoID {
                        RelatedVideosView(videoID: videoID, onPlay: playback.open)
                    }
                    if playback.phase == .idle {
                        EmptyStateView("Your next discovery starts here",
                                               systemImage: "play.rectangle.on.rectangle",
                                               message: "Videos open in the built-in player.")
                    }
                }
                .padding()
            }
            .navigationTitle("DriftLoom")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if playback.phase != .idle {
                        IconButton("Stop", systemImage: "stop.circle", action: playback.stop)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showsLicenses = true } label: { Image(systemName: "doc.text") }
                        .accessibilityLabel("Open-source licenses")
                }
            }
            .sheet(isPresented: $showsLicenses) {
                AppNavigation {
                    ScrollView {
                        Text(licenseText)
                            .font(.footnote).padding()
                    }
                    .navigationTitle("Open-source licenses")
                    .toolbar { Button("Done") { showsLicenses = false } }
                }
            }
        }
        .id(playback.videoID)
    }

    @ViewBuilder private var status: some View {
        switch playback.phase {
        case .resolving: ProgressView("Opening video…")
        case .loading: ProgressView("Loading stream…")
        case let .failed(message):
            VStack(alignment: .leading, spacing: 12) {
                Label(message, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("playbackError")
                Button("Try again", action: playback.retry).buttonStyle(.bordered)
            }
        case .playing: Label("Playing", systemImage: "play.fill").foregroundStyle(.secondary)
        case .paused: Label("Paused", systemImage: "pause.fill").foregroundStyle(.secondary)
        case .idle: EmptyView()
        }
    }

    private var licenseText: String {
        Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "License information is unavailable."
    }

    private func openVideo() {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        dismissKeyboard()
        playback.open(input)
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}


private struct RelatedVideosView: View {
    let videoID: String
    let onPlay: (BrowseItem) -> Void
    @StateObject private var related = BrowseStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !related.items.isEmpty {
                Text("More to explore").font(.title3.weight(.semibold))
                ForEach(related.items.filter { $0.kind == .video }.prefix(5)) { item in
                    Button { onPlay(item) } label: { BrowseRow(item: item) }
                        .buttonStyle(.plain)
                        .contextMenu { LibraryItemActions(item: item) }
                }
                BrowseLink(route: .related(videoID), onPlay: onPlay) { Text("See all related videos") }
            } else if related.isLoading {
                ProgressView("Finding related videos…").font(.footnote)
            } else if related.error != nil {
                Button("Try loading related videos again") {
                    Task { await related.load(.related(videoID)) }
                }
                .font(.footnote)
            }
        }
        .task(id: videoID) { await related.load(.related(videoID)) }
    }
}
