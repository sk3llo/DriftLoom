// SPDX-License-Identifier: GPL-3.0-or-later
import DriftLoomPlayback
import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var preferences: AppPreferences
    let onPlay: (BrowseItem) -> Void
    var onClose: () -> Void = {}
    @StateObject private var results = BrowseStore()
    @State private var query = ""
    @State private var submittedQuery = ""
    @State private var filter = SearchFilter.all
    @FocusState private var focused: Bool
    private var route: BrowseRoute { .filteredSearch(submittedQuery, filter) }

    var body: some View {
        AppNavigation {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button(action: onClose) { Image(systemName: "arrow.left").frame(width: 40, height: 44) }
                        .accessibilityLabel("Back to home")
                    TextField("Search YouTube", text: $query)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .submitLabel(.search).focused($focused).onSubmit(submit)
                        .accessibilityIdentifier("searchQuery")
                    if !query.isEmpty {
                        Button { query = ""; focused = true } label: { Image(systemName: "xmark").frame(width: 40, height: 44) }
                            .accessibilityLabel("Clear search")
                    }
                    Button(action: submit) { Image(systemName: "magnifyingglass").frame(width: 40, height: 44) }
                        .accessibilityLabel("Search")
                        .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding(.horizontal, 8)
                Divider()
                SectionStrip(values: SearchFilter.allCases, selection: $filter, title: { $0.rawValue })
                if submittedQuery.isEmpty {
                    if preferences.searchHistory.isEmpty {
                        EmptyStateView("Search", systemImage: "magnifyingglass", message: "Find videos, channels, and playlists, or paste a video link.")
                    } else {
                        List {
                            ForEach(preferences.searchHistory.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }, id: \.self) { text in
                                Button { query = text; submit() } label: {
                                    HStack {
                                        Image(systemName: "clock").foregroundStyle(.secondary)
                                        Text(text).foregroundStyle(.primary)
                                        Spacer()
                                        Image(systemName: "arrow.up.left").foregroundStyle(.secondary)
                                    }.padding(.vertical, 6)
                                }
                                .swipeActions { Button("Remove", role: .destructive) { preferences.removeSearch(text) } }
                            }
                        }.listStyle(.plain)
                    }
                } else {
                    BrowseResults(store: results, onPlay: onPlay, retry: { Task { await results.load(route) } }, videoIdentifierPrefix: "searchVideo")
                }
            }
            .navigationBarHidden(true)
            .task(id: route) {
                guard !submittedQuery.isEmpty else { return }
                await results.load(route)
#if DEBUG || DRIFTLOOM_DEVICE_TESTING
                await runBrowseSmokeCheck(results, onPlay: onPlay)
#endif
            }
            .task {
#if DEBUG || DRIFTLOOM_DEVICE_TESTING
                let arguments = ProcessInfo.processInfo.arguments
                if submittedQuery.isEmpty, let flag = arguments.firstIndex(of: "--browse-smoke-query"), arguments.indices.contains(flag + 1) {
                    query = arguments[flag + 1]; submit()
                }
#endif
            }
        }
    }
    private func submit() {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        focused = false
        if value.contains("://"), let video = try? VideoRequest(input: value) {
            onPlay(BrowseItem(contentID: video.videoID, kind: .video, title: "YouTube video")); return
        }
        preferences.recordSearch(value)
        if submittedQuery == value { Task { await results.load(route) } }
        else { submittedQuery = value }
    }
}

struct BrowsePageView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var queue: PlaybackQueue
    let route: BrowseRoute
    let onPlay: (BrowseItem) -> Void
    @StateObject private var store = BrowseStore()
    @State private var tab = ChannelTab.videos
    @State private var showsDescription = false
    @State private var channelHeader: BrowseHeader?
    @State private var channelTitle = ""
    private var channelID: String? {
        switch route { case let .channel(id), let .channelTab(id, _): return id; default: return nil }
    }
    private var effectiveRoute: BrowseRoute { channelID.map { .channelTab($0, tab) } ?? route }
    var body: some View {
        VStack(spacing: 0) {
            if let id = channelID {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        AsyncImage(url: channelHeader?.thumbnail) { $0.resizable().scaledToFill() } placeholder: {
                            Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary)
                        }.frame(width: 52, height: 52).clipShape(Circle()).accessibilityHidden(true)
                        Text(channelTitle.isEmpty ? "Channel" : channelTitle).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                        Button(library.isSubscribed(id) ? "SUBSCRIBED" : "SUBSCRIBE") {
                            library.toggleSubscription(BrowseItem(contentID: id, kind: .channel, title: channelTitle,
                                                                  thumbnail: channelHeader?.thumbnail))
                        }.font(.caption.weight(.semibold)).disabled(!library.isWritable || !store.hasLoaded)
                    }
                    if let description = channelHeader?.description, !description.isEmpty {
                        Button { showsDescription.toggle() } label: {
                            Text(description).font(.caption).foregroundStyle(.secondary)
                                .lineLimit(showsDescription ? nil : 2).multilineTextAlignment(.leading)
                        }.buttonStyle(.plain)
                    }
                }.padding(12)
                SectionStrip(values: channelHeader?.tabs.isEmpty == false ? channelHeader!.tabs : [.videos], selection: $tab, title: { $0.rawValue })
            } else if isPlaylist, !store.items.isEmpty {
                HStack {
                    Button {
                        queue.start(store.items)
                        NotificationCenter.default.post(name: .driftLoomExpandPlayer, object: nil)
                    } label: { Label("Play all", systemImage: "play.fill") }
                    Spacer()
                    Button { for item in store.items { queue.enqueue(item) } } label: { Label("Enqueue", systemImage: "text.badge.plus") }
                }.font(.subheadline).padding(12)
            }
            BrowseResults(store: store, onPlay: onPlay, retry: { Task { await store.load(effectiveRoute) } })
        }
        .navigationTitle(store.title.isEmpty ? "YouTube" : store.title)
        .navigationBarTitleDisplayMode(.inline).navigationBarHidden(false)
        .task(id: effectiveRoute) { await store.load(effectiveRoute) }
        .onReceive(store.$header) { header in
            if let header {
                channelHeader = header
                if !header.tabs.isEmpty, !header.tabs.contains(tab) { tab = header.tabs[0] }
            }
        }
        .onReceive(store.$title) { if !$0.isEmpty { channelTitle = $0 } }
    }
    private var isPlaylist: Bool {
        switch route { case .playlist, .mix: return true; default: return false }
    }
}

struct BrowseResults: View {
    @ObservedObject var store: BrowseStore
    let onPlay: (BrowseItem) -> Void
    let retry: () -> Void
    var videoIdentifierPrefix = "browseVideo"
    var body: some View {
        Group {
            if store.isLoading {
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = store.error {
                VStack(spacing: 16) {
                    EmptyStateView("Couldn't load this page", systemImage: "wifi.exclamationmark", message: error)
                    Button("Try again", action: retry).buttonStyle(.bordered)
                }.padding()
            } else if store.hasLoaded && store.items.isEmpty {
                EmptyStateView("No results", systemImage: "magnifyingglass", message: "This section has no available items. Try another filter or tab.")
            } else {
                List {
                    ForEach(store.items) { item in
                        BrowseResultRow(item: item, onPlay: onPlay, videoIdentifierPrefix: videoIdentifierPrefix)
                            .listRowInsets(EdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 4))
                            .listRowSeparator(.hidden)
                    }
                    if let message = store.paginationError { Text(message).font(.footnote).foregroundStyle(.secondary) }
                    if store.canLoadMore {
                        Button { Task { await store.loadMore() } } label: {
                            HStack {
                                Spacer()
                                if store.isLoadingMore { ProgressView() }
                                else { Text(store.paginationError == nil ? "Load more" : "Try loading more again") }
                                Spacer()
                            }.padding(.vertical, 10)
                        }.disabled(store.isLoadingMore)
                    }
                }.listStyle(.plain).dismissKeyboardOnScroll()
            }
        }
    }
}

struct BrowseResultRow: View {
    let item: BrowseItem
    let onPlay: (BrowseItem) -> Void
    var videoIdentifierPrefix = "browseVideo"
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Group {
                if let route = item.destination { BrowseLink(route: route, onPlay: onPlay) { BrowseRow(item: item) } }
                else {
                    Button { onPlay(item) } label: { BrowseRow(item: item) }.buttonStyle(.plain)
                        .accessibilityIdentifier("\(videoIdentifierPrefix)-\(item.contentID)")
                }
            }.contextMenu { BrowseItemMenu(item: item, onPlay: onPlay) }
            Menu { BrowseItemMenu(item: item, onPlay: onPlay) } label: {
                Image(systemName: "ellipsis").rotationEffect(.degrees(90)).frame(width: 36, height: 44)
            }.foregroundStyle(.secondary).accessibilityLabel("Actions for \(item.title)")
                .accessibilityIdentifier("itemActions-\(item.id)")
        }
    }
}

struct BrowseItemMenu: View {
    @EnvironmentObject private var queue: PlaybackQueue
    @EnvironmentObject private var playlists: PlaylistStore
    let item: BrowseItem
    let onPlay: (BrowseItem) -> Void
    var body: some View {
        if item.kind == .video {
            IconButton("Play", systemImage: "play") { onPlay(item) }
            IconButton("Play next", systemImage: "text.line.first.and.arrowtriangle.forward") { queue.enqueue(item, next: true) }
            IconButton("Enqueue", systemImage: "text.badge.plus") { queue.enqueue(item) }
            IconButton("Add to playlist", systemImage: "plus.rectangle.on.rectangle") {
                NotificationCenter.default.post(name: .driftLoomAddToPlaylist, object: item)
            }.disabled(!playlists.isWritable)
            if let id = item.channelID {
                BrowseLink(route: .channel(id), onPlay: onPlay) { Label("Open channel", systemImage: "person.crop.circle") }
            }
            Divider()
        }
        if item.kind == .playlist {
            IconButton(playlists.isBookmarked(item.contentID) ? "Remove bookmark" : "Bookmark playlist", systemImage: "bookmark") {
                playlists.toggleBookmark(item)
            }.disabled(!playlists.isWritable)
        }
        LibraryItemActions(item: item)
    }
}

struct BrowseRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let item: BrowseItem
    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) { thumbnail; metadata }
            } else {
                HStack(alignment: .top, spacing: 10) { thumbnail; metadata; Spacer(minLength: 0) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
    private var thumbnail: some View {
        AsyncImage(url: item.thumbnail) { $0.resizable().scaledToFill() } placeholder: {
            Rectangle().fill(.quaternary).overlay { Image(systemName: symbol).foregroundStyle(.secondary) }
        }
        .frame(width: 124, height: 70).clipped()
        .clipShape(RoundedRectangle(cornerRadius: item.kind == .channel ? 35 : 2))
        .overlay(alignment: .bottomTrailing) {
            if let duration = item.duration {
                Text(duration).font(.caption2.monospacedDigit()).foregroundColor(.white)
                    .padding(3).background(Color.black.opacity(0.85)).padding(3)
            }
        }.accessibilityHidden(true)
    }
    private var metadata: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title).font(.subheadline.weight(.medium)).lineLimit(typeSize.isAccessibilitySize ? nil : 3).foregroundStyle(.primary)
            if !item.subtitle.isEmpty { Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            if item.kind != .video {
                Text(item.kind == .channel ? "Channel" : "Playlist").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
    private var symbol: String { item.kind == .video ? "play.rectangle" : item.kind == .channel ? "person.crop.circle" : "rectangle.stack" }
}
