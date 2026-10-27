// SPDX-License-Identifier: GPL-3.0-or-later
import DriftLoomPlayback
import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var preferences: AppPreferences
    let onPlay: (BrowseItem) -> Void
    var onClose: () -> Void = {}
    @StateObject private var results = BrowseStore()
    @StateObject private var suggestions = SuggestionStore()
    @State private var query = ""
    @State private var submittedQuery = ""
    @State private var filter = SearchFilter.all
    @State private var order = SearchOrder.relevance
    @State private var date = SearchDate.any
    @State private var duration = SearchDuration.any
    @State private var service = SearchService.youTube
    @State private var soundCloudFilter = SoundCloudSearchFilter.tracks
    @State private var linkError: String?
    @FocusState private var focused: Bool
    enum SearchService: String, CaseIterable { case youTube = "YouTube", soundCloud = "SoundCloud" }
    private struct SuggestionInput: Hashable { let query: String; let focused: Bool; let enabled: Bool; let locale: ContentLocale }
    private var suggestionInput: SuggestionInput {
        SuggestionInput(query: query, focused: focused, enabled: preferences.usesSearchSuggestions && service == .youTube, locale: preferences.contentLocale)
    }
    private var route: BrowseRoute {
        service == .soundCloud ? .soundCloudSearch(submittedQuery, soundCloudFilter)
            : .advancedSearch(submittedQuery, SearchOptions(type: filter, order: order, date: date, duration: duration))
    }

    var body: some View {
        AppNavigation {
            VStack(spacing: 0) {
                // The same red toolbar as home, with the query typed straight into it, as in NewPipe.
                HStack(spacing: 8) {
                    Button(action: onClose) { Image(systemName: "arrow.left").font(.title3).frame(width: 40, height: 52) }
                        .accessibilityLabel("Back to home").accessibilityIdentifier("closeSearch")
                    TextField(service == .youTube ? "Search YouTube" : "Search SoundCloud", text: $query,
                              prompt: Text(service == .youTube ? "Search YouTube" : "Search SoundCloud").foregroundColor(.white.opacity(0.7)))
                        .font(.title3).foregroundColor(.white).tint(.white)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .submitLabel(.search).focused($focused).onSubmit(submit)
                        .accessibilityIdentifier("searchQuery")
                    if !query.isEmpty {
                        Button { query = ""; focused = true } label: { Image(systemName: "xmark").font(.title3).frame(width: 40, height: 52) }
                            .accessibilityLabel("Clear search")
                    }
                    Button(action: submit) { Image(systemName: "magnifyingglass").font(.title3).frame(width: 40, height: 52) }
                        .accessibilityLabel("Search").accessibilityIdentifier("submitSearch")
                        .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 4).foregroundColor(.white)
                .background(AppStyle.bar.ignoresSafeArea(edges: .top))
                .padding(.bottom, 8)
                Picker("Service", selection: $service) {
                    ForEach(SearchService.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).padding(.horizontal, 12).padding(.bottom, 6).accessibilityIdentifier("searchService")
                Divider()
                if let linkError { Text(linkError).font(.footnote).foregroundStyle(.secondary).padding(8) }
                if service == .soundCloud {
                    SectionStrip(values: SoundCloudSearchFilter.allCases, selection: $soundCloudFilter, title: { $0.title })
                } else {
                HStack(spacing: 0) {
                    SectionStrip(values: SearchFilter.allCases, selection: $filter, title: { $0.title })
                    Menu {
                        Picker("Sort by", selection: $order) { ForEach(SearchOrder.allCases, id: \.self) { Text($0.title).tag($0) } }
                        Picker("Upload date", selection: $date) { ForEach(SearchDate.allCases, id: \.self) { Text($0.title).tag($0) } }
                        if filter == .videos || filter == .all {
                            Picker("Duration", selection: $duration) { ForEach(SearchDuration.allCases, id: \.self) { Text($0.title).tag($0) } }
                        }
                        Button("Reset filters") { order = .relevance; date = .any; duration = .any }
                    } label: { Image(systemName: "line.3.horizontal.decrease.circle").frame(width: 44, height: 46) }
                    .accessibilityLabel("Search filters").accessibilityIdentifier("searchFilters")
                }
                }
                if focused, !suggestions.suggestions.isEmpty {
                    List {
                        Section("Suggestions") {
                            ForEach(suggestions.suggestions, id: \.self) { text in
                                Button { query = text; submit() } label: {
                                    Label(text, systemImage: "magnifyingglass").foregroundStyle(.primary).padding(.vertical, 5)
                                }.accessibilityLabel(text).accessibilityIdentifier("searchSuggestion-" + text)
                            }
                        }
                    }.listStyle(.plain)
                } else if submittedQuery.isEmpty {
                    if preferences.searchHistory.isEmpty {
                        EmptyStateView("Search", systemImage: "magnifyingglass", message: "Find videos, channels, tracks and playlists, or paste a YouTube or SoundCloud link.")
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
            .task(id: suggestionInput) {
                await suggestions.load(query: query, locale: preferences.contentLocale, enabled: focused && preferences.usesSearchSuggestions && query != submittedQuery)
            }
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
                if arguments.contains("--browse-smoke-soundcloud") { service = .soundCloud }
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
        suggestions.clear()
        linkError = nil
        if value.contains("://"), let video = try? VideoRequest(input: value) {
            onPlay(BrowseItem(contentID: video.videoID, kind: .video, title: PlaybackSession.placeholderTitle)); return
        }
        if value.contains("://"), let link = SharedLink.firstSupportedURL(in: value) {
            NotificationCenter.default.post(name: .driftLoomOpenLink, object: link); return
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
                        Text(channelTitle.isEmpty ? String(localized: "Channel") : channelTitle).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
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
                if !SoundCloudID.isSoundCloud(id) {
                    SectionStrip(values: channelHeader?.tabs.isEmpty == false ? channelHeader!.tabs : [.videos], selection: $tab, title: { $0.title })
                }
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
        .navigationTitle(store.title.isEmpty ? (channelID.map(SoundCloudID.isSoundCloud) == true ? "SoundCloud" : "YouTube") : store.title)
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
            }.foregroundStyle(.secondary).accessibilityLabel(Text("Actions for \(item.title)"))
                .accessibilityIdentifier("itemActions-\(item.id)")
        }
    }
}

struct BrowseItemMenu: View {
    @EnvironmentObject private var queue: PlaybackQueue
    @EnvironmentObject private var playlists: PlaylistStore
    @EnvironmentObject private var pinnedTabs: PinnedHomeTabs
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
        if item.kind == .channel || item.kind == .playlist {
            IconButton(pinnedTabs.contains(item) ? "Remove from home" : "Add to home", systemImage: "pin") { pinnedTabs.toggle(item) }
                .disabled(!pinnedTabs.isWritable)
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
            if item.kind != .video || item.isSoundCloud {
                Text([item.isSoundCloud ? "SoundCloud" : nil, item.kind == .channel ? String(localized: "Channel") : item.kind == .playlist ? String(localized: "Playlist") : nil]
                    .compactMap { $0 }.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
    private var symbol: String {
        item.kind == .video ? (item.isSoundCloud ? "music.note" : "play.rectangle") : item.kind == .channel ? "person.crop.circle" : "rectangle.stack"
    }
}
