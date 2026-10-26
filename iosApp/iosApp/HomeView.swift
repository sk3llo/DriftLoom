// SPDX-License-Identifier: GPL-3.0-or-later
import DriftLoomPlayback
import SwiftUI

enum AppStyle {
    static let accent = Color(red: 205 / 255, green: 32 / 255, blue: 31 / 255)
}

struct SectionStrip<Value: Hashable>: View {
    let values: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(values, id: \.self) { value in
                        Button { selection = value } label: {
                            VStack(spacing: 0) {
                                Text(title(value).uppercased()).font(.caption.weight(.semibold)).lineLimit(1).frame(maxWidth: 200)
                                    .foregroundColor(selection == value ? AppStyle.accent : .secondary)
                                    .padding(.horizontal, 16).frame(minHeight: 46)
                                Rectangle().fill(selection == value ? AppStyle.accent : .clear).frame(height: 2)
                            }
                        }.contentShape(Rectangle()).buttonStyle(.plain).id(value)
                            .accessibilityAddTraits(selection == value ? .isSelected : [])
                    }
                }
            }.onChange(of: selection) { value in withAnimation { proxy.scrollTo(value, anchor: .center) } }
        }
        .frame(height: 48).contentShape(Rectangle()).clipped()
        .background(Color(.secondarySystemBackground))
    }
}

private enum HomeSheet: String, Identifiable {
    case settings, about, link, downloads, groups
    var id: String { rawValue }
}

struct HomeView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var pinnedTabs: PinnedHomeTabs
    @EnvironmentObject private var playlists: PlaylistStore
    @Binding var selection: HomeSection
    let onSearch: () -> Void
    let onPlay: (BrowseItem) -> Void
    @State private var menuVisible = false
    @State private var sheet: HomeSheet?
    @State private var pendingVideo: BrowseItem?
    @StateObject private var feed = SubscriptionFeedStore()
    @StateObject private var pinnedPage = BrowseStore()
    @State private var selectedPinned: String?
    @State private var selectedLocal: UUID?
    private var homeTabs: [HomeTabKey] {
        pinnedTabs.arrangement(sections: preferences.homeSections, localPlaylistIDs: Set(playlists.playlists.map(\.id)))
    }
    private var currentTab: Binding<HomeTabKey> {
        Binding(get: { selectedLocal.map(HomeTabKey.local) ?? selectedPinned.map(HomeTabKey.pinned) ?? .section(selection) }, set: { tab in
            switch tab {
            case let .section(section): selectedPinned = nil; selectedLocal = nil; selection = section
            case let .pinned(id): selectedLocal = nil; selectedPinned = id
            case let .local(id): selectedPinned = nil; selectedLocal = id
            }
        })
    }
    private func tabTitle(_ tab: HomeTabKey) -> String {
        switch tab {
        case let .section(section): return section.rawValue
        case let .pinned(id): return pinnedTabs.tabs.first { $0.id == id }?.item.title ?? "Home"
        case let .local(id): return playlists.playlists.first { $0.id == id }?.name ?? "Playlist"
        }
    }
    var body: some View {
        ZStack(alignment: .leading) {
            AppNavigation {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Button { menuVisible = true } label: { Image(systemName: "line.3.horizontal").frame(width: 44, height: 44) }
                            .accessibilityLabel("Main menu").accessibilityIdentifier("mainMenu")
                        Spacer()
                        Text("DriftLoom").font(.headline).lineLimit(1)
                        Spacer()
                        Button(action: onSearch) { Image(systemName: "magnifyingglass").frame(width: 44, height: 44) }
                            .accessibilityLabel("Search").accessibilityIdentifier("openSearch")
                        Menu {
                            IconButton("Open a link", systemImage: "link") { sheet = .link }
                            IconButton("Settings", systemImage: "gearshape") { sheet = .settings }
                            IconButton("About", systemImage: "info.circle") { sheet = .about }
                        } label: { Image(systemName: "ellipsis").rotationEffect(.degrees(90)).frame(width: 44, height: 44) }
                        .accessibilityLabel("More options")
                    }.padding(.horizontal, 6).background(Color(.systemBackground))
                    SectionStrip(values: homeTabs, selection: currentTab, title: tabTitle)
                    if let id = selectedLocal, playlists.playlists.contains(where: { $0.id == id }) {
                        LocalPlaylistView(id: id, onPlay: onPlay, embedded: true).id(id)
                    } else if let id = selectedPinned, let tab = pinnedTabs.tabs.first(where: { $0.id == id }) {
                        PinnedPageView(item: tab.item, store: pinnedPage, onPlay: onPlay)
                    } else if selection == .trending { TrendingMusicView(onPlay: onPlay) }
                    else if let kiosk = selection.kiosk { KioskView(kiosk: kiosk, onPlay: onPlay).id(kiosk) }
                    else if selection == .soundCloud { SoundCloudTrendingView(onPlay: onPlay) }
                    else if selection == .feed { FeedView(store: feed, onPlay: onPlay) }
                    else if selection == .bookmarks { BookmarksView(onPlay: onPlay) }
                    else { LibrarySectionView(section: selection, onPlay: onPlay).id(selection) }
                }
                .navigationBarHidden(true)
            }
            .accessibilityHidden(menuVisible || sheet != nil).allowsHitTesting(!menuVisible && sheet == nil)
            if menuVisible {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Button { menuVisible = false } label: { Color.black.opacity(0.4).ignoresSafeArea() }
                            .accessibilityLabel("Close main menu")
                        VStack(alignment: .leading, spacing: 0) {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("DriftLoom", systemImage: "play.rectangle.fill").font(.title2.weight(.bold))
                                Text("YouTube · SoundCloud").font(.subheadline)
                            }
                            .foregroundColor(.white).frame(maxWidth: .infinity, alignment: .leading).padding(24).background(AppStyle.accent)
                            ScrollView {
                                VStack(spacing: 0) {
                                    ForEach(HomeSection.allCases) { section in
                                        Button {
                                            if !preferences.homeSections.contains(section) { preferences.setHomeSections(preferences.homeSections + [section]) }
                                            selectedPinned = nil; selectedLocal = nil; selection = section; menuVisible = false
                                        } label: {
                                            Label(section.rawValue, systemImage: section.symbol)
                                                .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                                                .foregroundColor(selection == section ? AppStyle.accent : .primary)
                                                .background(selection == section ? AppStyle.accent.opacity(0.08) : .clear)
                                        }.buttonStyle(.plain).accessibilityIdentifier("drawer-section-" + section.rawValue)
                                    }
                                    ForEach(pinnedTabs.tabs) { tab in
                                        drawerButton(tab.item.title, symbol: tab.item.kind == .channel ? "person.crop.circle" : "rectangle.stack") { selectedLocal = nil; selectedPinned = tab.id }
                                            .accessibilityIdentifier("drawer-pinned-" + tab.id)
                                    }
                                    ForEach(playlists.playlists.filter { pinnedTabs.containsLocal($0.id) }) { playlist in
                                        drawerButton(playlist.name, symbol: "music.note.list") { selectedPinned = nil; selectedLocal = playlist.id }
                                            .accessibilityIdentifier("drawer-local-" + playlist.id.uuidString)
                                    }
                                    Divider().padding(.vertical, 8)
                                    drawerButton("Search", symbol: "magnifyingglass") { onSearch() }
                                    drawerButton("Open a link", symbol: "link") { sheet = .link }
                                    drawerButton("Downloads", symbol: "arrow.down.circle") { sheet = .downloads }
                                    drawerButton("Settings", symbol: "gearshape") { sheet = .settings }
                                    drawerButton("About", symbol: "info.circle") { sheet = .about }
                                }
                            }
                        }
                        .frame(width: min(320, geometry.size.width * 0.85), height: geometry.size.height)
                        .background(Color(.systemBackground)).shadow(radius: 10)
                        .accessibilityElement(children: .contain).accessibilityIdentifier("navigationDrawer")
                    }
                }.zIndex(1)
            }
        }
        .onChange(of: selection) { _ in selectedPinned = nil; selectedLocal = nil }
        .onChange(of: playlists.playlists.map(\.id)) { ids in
            if playlists.isWritable { pinnedTabs.retainLocal(Set(ids)) }
            if let selectedLocal, !ids.contains(selectedLocal) { self.selectedLocal = nil }
        }
        .onChange(of: pinnedTabs.tabs) { tabs in
            if let selectedPinned, !tabs.contains(where: { $0.id == selectedPinned }) { self.selectedPinned = nil }
        }
        .task(id: selectedPinned) {
            if let id = selectedPinned, let route = pinnedTabs.tabs.first(where: { $0.id == id })?.item.destination { await pinnedPage.load(route) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .driftLoomManageGroups)) { _ in sheet = .groups }
        .onReceive(NotificationCenter.default.publisher(for: .driftLoomOpenDownloads)) { _ in menuVisible = false; sheet = .downloads }
        .onReceive(NotificationCenter.default.publisher(for: .driftLoomOpenFeed)) { _ in
            menuVisible = false; sheet = nil
            if !preferences.homeSections.contains(.feed) { preferences.setHomeSections(preferences.homeSections + [.feed]) }
            selection = .feed
        }
        .sheet(item: $sheet, onDismiss: {
            if let video = pendingVideo { pendingVideo = nil; onPlay(video) }
        }) { target in
            switch target {
            case .downloads:
                AppNavigation {
                    DownloadsView { video in pendingVideo = video; sheet = nil }
                        .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { sheet = nil } } }
                }
            case .groups: SubscriptionGroupsView()
            case .settings: SettingsView()
            case .about: AboutView()
            case .link: OpenVideoLinkView { video in pendingVideo = video; sheet = nil }
            }
        }
    }
    private func drawerButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button { menuVisible = false; action() } label: {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity, alignment: .leading).padding(16).foregroundStyle(.primary)
        }.buttonStyle(.plain).accessibilityIdentifier("drawer-" + title)
    }
}

private struct KioskView: View {
    let kiosk: YouTubeKiosk
    let onPlay: (BrowseItem) -> Void
    @EnvironmentObject private var preferences: AppPreferences
    @StateObject private var store = BrowseStore()
    var body: some View {
        VStack(spacing: 0) {
            Text("YouTube · " + kiosk.rawValue + " · " + preferences.contentLocale.country).font(.caption).foregroundStyle(.secondary).padding(8)
                .accessibilityIdentifier("kioskSource")
            BrowseResults(store: store, onPlay: onPlay, retry: { Task { await store.load(.kiosk(kiosk)) } })
        }.task(id: preferences.contentLocale) { await store.load(.kiosk(kiosk)) }
    }
}

private struct SoundCloudTrendingView: View {
    let onPlay: (BrowseItem) -> Void
    @StateObject private var store = BrowseStore()
    var body: some View {
        VStack(spacing: 0) {
            Text("SoundCloud · Trending").font(.caption).foregroundStyle(.secondary).padding(8).accessibilityIdentifier("kioskSource")
            BrowseResults(store: store, onPlay: onPlay, retry: { Task { await store.load(.soundCloudTrending) } })
        }.task { await store.load(.soundCloudTrending) }
    }
}

private struct TrendingMusicView: View {
    let onPlay: (BrowseItem) -> Void
    @EnvironmentObject private var preferences: AppPreferences
    @StateObject private var store = BrowseStore()
    var body: some View {
        VStack(spacing: 0) {
            Text("YouTube Charts · " + preferences.contentLocale.country).font(.caption).foregroundStyle(.secondary).padding(8)
            BrowseResults(store: store, onPlay: onPlay, retry: { Task { await store.load(.trendingMusic) } })
        }.task(id: preferences.contentLocale) { await store.load(.trendingMusic) }
    }
}

private struct PinnedPageView: View {
    let item: BrowseItem
    @ObservedObject var store: BrowseStore
    let onPlay: (BrowseItem) -> Void
    @EnvironmentObject private var queue: PlaybackQueue
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(store.title.isEmpty ? item.title : store.title).font(.headline).lineLimit(2)
                    .accessibilityIdentifier("pinnedPageTitle")
                Spacer()
                Menu { BrowseItemMenu(item: item, onPlay: onPlay) } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                }.accessibilityLabel("Pinned tab options")
            }.padding(.horizontal, 12)
            if item.kind == .playlist, !store.items.isEmpty {
                HStack {
                    Button("Play all") {
                        queue.start(store.items)
                        NotificationCenter.default.post(name: .driftLoomExpandPlayer, object: nil)
                    }
                    Spacer()
                    Button("Enqueue") { for item in store.items { queue.enqueue(item) } }
                }.padding(12)
            }
            BrowseResults(store: store, onPlay: onPlay, retry: {
                Task { if let route = item.destination { await store.load(route) } }
            })
        }
    }
}

private struct FeedView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var groups: SubscriptionGroups
    @EnvironmentObject private var preferences: AppPreferences
    @ObservedObject var store: SubscriptionFeedStore
    let onPlay: (BrowseItem) -> Void
    @State private var selectedGroup: UUID?
    private var channels: [String] { groups.channelIDs(for: selectedGroup, subscribed: library.subscriptions.map { $0.item.contentID }) }
    private var visible: [FeedVideo] {
        FeedFilter.apply(store.items, period: preferences.feedPeriod, hidingWatched: preferences.hidesWatchedFeed,
                         watchedIDs: Set(library.history.map { $0.item.contentID }))
    }
    var body: some View {
        VStack(spacing: 0) {
            SubscriptionGroupFilter(selection: $selectedGroup)
            HStack {
                Menu {
                    Picker("Upload date", selection: Binding(get: { preferences.feedPeriod }, set: preferences.setFeedPeriod)) {
                        ForEach(FeedPeriod.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("Hide watched videos", isOn: Binding(get: { preferences.hidesWatchedFeed }, set: preferences.setHidesWatchedFeed))
                } label: { Label("Feed filters", systemImage: "slider.horizontal.3").frame(minHeight: 44) }
                    .accessibilityIdentifier("feedFilters")
                Spacer()
                Button { Task { await store.load(channelIDs: channels) } } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }
                    .accessibilityLabel("Refresh feed").disabled(store.loading || channels.isEmpty)
            }.padding(.horizontal, 12)
            if channels.isEmpty {
                EmptyStateView("No channels in this feed", systemImage: "tray", message: selectedGroup == nil ? "Subscribe to channels to build your feed." : "Edit this group to add subscribed channels.")
            } else {
                List {
                    Text("Recent uploads from channel RSS feeds; each channel supplies a limited number of videos.")
                        .font(.caption).foregroundStyle(.secondary)
                    if preferences.feedPeriod != .all || preferences.hidesWatchedFeed {
                        Text(preferences.feedPeriod.rawValue + (preferences.hidesWatchedFeed ? " · Watched videos hidden" : "")).font(.caption)
                    }
                    if store.loading {
                        HStack { ProgressView(); Text("Refreshing \(store.completedChannels) of \(channels.count) channels…").font(.footnote) }
                    }
                    if store.failedChannels > 0 {
                        Text("\(store.failedChannels) channel feeds could not be loaded. Pull to refresh and try again.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if !store.loading, visible.isEmpty {
                        Text("No videos match these feed filters.").foregroundStyle(.secondary)
                    }
                    ForEach(visible) { entry in
                        VStack(alignment: .leading, spacing: 5) {
                            BrowseResultRow(item: entry.item, onPlay: onPlay)
                            Text(entry.published, style: .relative).font(.caption2).foregroundStyle(.secondary)
                        }.listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 4))
                    }
                }.listStyle(.plain).refreshable { await store.load(channelIDs: channels) }
            }
        }
        .task(id: channels) { await store.load(channelIDs: channels) }
    }
}

struct OpenVideoLinkView: View {
    @Environment(\.dismiss) private var dismiss
    let onOpen: (BrowseItem) -> Void
    @State private var input = ""
    @State private var error: String?
    var body: some View {
        AppNavigation {
            Form {
                TextField("YouTube or SoundCloud link", text: $input).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .submitLabel(.go).onSubmit(open)
                if let error { Text(error).foregroundColor(.red).font(.footnote) }
                Button("Open", action: open).disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .navigationTitle("Open a link").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Cancel") { dismiss() } }
        }
    }
    private func open() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        // Channel, playlist and SoundCloud links go through the app-wide link handler.
        if let url = SharedLink.firstSupportedURL(in: text), (try? VideoRequest(input: text)) == nil {
            dismiss()
            // Present the linked page once this sheet has finished closing.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { NotificationCenter.default.post(name: .driftLoomOpenLink, object: url) }
            return
        }
        do {
            let video = try VideoRequest(input: text)
            onOpen(BrowseItem(contentID: video.videoID, kind: .video, title: "YouTube video"))
        } catch { self.error = error.localizedDescription }
    }
}
