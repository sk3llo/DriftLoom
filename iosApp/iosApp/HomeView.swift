// SPDX-License-Identifier: GPL-3.0-or-later
import DriftLoomPlayback
import SwiftUI

enum AppStyle {
    /// Buttons, links and progress: the icon's coral stripes, darker in light mode so text stays readable.
    static let accent = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0xFF / 255, green: 0x8A / 255, blue: 0x5B / 255, alpha: 1)
            : UIColor(red: 0xC2 / 255, green: 0x41 / 255, blue: 0x0C / 255, alpha: 1)
    })
    /// The home toolbar: the app icon's violet background, deeper in dark mode. Keep it in step with
    /// branding/generate.py and the Android `*_youtube_primary_color` resources.
    static let bar = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0x1F / 255, green: 0x16 / 255, blue: 0x50 / 255, alpha: 1)
            : UIColor(red: 0x2E / 255, green: 0x1C / 255, blue: 0x66 / 255, alpha: 1)
    })
}

/// NewPipe's home tab bar: one icon per tab at equal widths, with an underline under the selected one.
/// It scrolls only when the tabs no longer fit at a comfortable width. Long-press to customize.
struct HomeTabBar: View {
    let tabs: [HomeTabKey]
    @Binding var selection: HomeTabKey
    let title: (HomeTabKey) -> String
    let symbol: (HomeTabKey) -> String
    let thumbnail: (HomeTabKey) -> URL?
    let onCustomize: () -> Void
    private let minimumWidth: CGFloat = 60

    var body: some View {
        GeometryReader { proxy in
            let fits = CGFloat(tabs.count) * minimumWidth <= proxy.size.width
            let width = fits ? proxy.size.width / CGFloat(max(1, tabs.count)) : minimumWidth + 8
            if fits {
                row(width: width)
            } else {
                ScrollViewReader { reader in
                    ScrollView(.horizontal, showsIndicators: false) { row(width: width) }
                        .onChange(of: selection) { value in withAnimation { reader.scrollTo(value, anchor: .center) } }
                }
            }
        }
        .frame(height: 50)
        .background(AppStyle.bar)
        .contextMenu { Button { onCustomize() } label: { Label("Customize tabs", systemImage: "slider.horizontal.3") } }
    }

    private func row(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                Button { selection = tab } label: {
                    VStack(spacing: 0) {
                        icon(tab).frame(height: 47)
                        Rectangle().fill(selection == tab ? Color.white : .clear).frame(height: 3)
                    }
                    .frame(width: width).contentShape(Rectangle())
                    .foregroundColor(.white.opacity(selection == tab ? 1 : 0.7))
                }
                .buttonStyle(.plain).id(tab)
                .accessibilityLabel(title(tab)).accessibilityAddTraits(selection == tab ? .isSelected : [])
                .accessibilityIdentifier("tabBar-" + tab.rawValue)
            }
        }
    }

    @ViewBuilder private func icon(_ tab: HomeTabKey) -> some View {
        if let url = thumbnail(tab) {
            AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Image(systemName: symbol(tab)).font(.title3) }
                .frame(width: 26, height: 26).clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(selection == tab ? 1 : 0), lineWidth: 1.5))
        } else {
            Image(systemName: symbol(tab)).font(.title3).symbolVariant(selection == tab ? .fill : .none)
        }
    }
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
                            .accessibilityIdentifier("sectionTab-\(values.firstIndex(of: value) ?? 0)")
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
    case settings, about, link, downloads, groups, tabs, guide
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
    /// The drawer's horizontal offset while a finger moves it: 0 is fully open, -drawerWidth fully closed.
    @State private var drawerDrag: CGFloat?
    @State private var containerWidth: CGFloat = UIScreen.main.bounds.width
    private var drawerWidth: CGFloat { min(320, containerWidth * 0.85) }
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
        case let .section(section): return section.title
        case let .pinned(id): return pinnedTabs.tabs.first { $0.id == id }?.item.title ?? String(localized: "Home")
        case let .local(id): return playlists.playlists.first { $0.id == id }?.name ?? String(localized: "Playlist")
        }
    }
    private func tabSymbol(_ tab: HomeTabKey) -> String {
        switch tab {
        case let .section(section): return section.symbol
        case let .pinned(id): return pinnedTabs.tabs.first { $0.id == id }?.item.kind == .channel ? "person.crop.circle" : "rectangle.stack"
        case .local: return "music.note.list"
        }
    }
    /// Pinned channels show their avatar, as NewPipe's channel tabs do.
    private func tabThumbnail(_ tab: HomeTabKey) -> URL? {
        guard case let .pinned(id) = tab, let item = pinnedTabs.tabs.first(where: { $0.id == id })?.item, item.kind == .channel else { return nil }
        return item.thumbnail
    }
    var body: some View {
        ZStack(alignment: .leading) {
            AppNavigation {
                VStack(spacing: 0) {
                    // NewPipe's toolbar: the current tab's name on the accent colour, with a fixed icon tab bar below.
                    HStack(spacing: 0) {
                        Button { withAnimation(.easeOut(duration: 0.22)) { menuVisible = true } } label: { Image(systemName: "line.3.horizontal").font(.title3).frame(width: 48, height: 52) }
                            .accessibilityLabel("Main menu").accessibilityIdentifier("mainMenu")
                        Text(tabTitle(currentTab.wrappedValue)).font(.title3.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                            .padding(.leading, 6).frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityAddTraits(.isHeader).accessibilityIdentifier("homeTitle")
                        Button(action: onSearch) { Image(systemName: "magnifyingglass").font(.title3).frame(width: 44, height: 52) }
                            .accessibilityLabel("Search").accessibilityIdentifier("openSearch")
                        Menu {
                            IconButton("Open a link", systemImage: "link") { sheet = .link }
                            IconButton("Customize tabs", systemImage: "slider.horizontal.3") { sheet = .tabs }
                            IconButton("Settings", systemImage: "gearshape") { sheet = .settings }
                            IconButton("About", systemImage: "info.circle") { sheet = .about }
                        } label: { Image(systemName: "ellipsis.circle").font(.title3).frame(width: 44, height: 52) }
                        .accessibilityLabel("More options").accessibilityIdentifier("moreOptions")
                    }
                    .padding(.horizontal, 4).foregroundColor(.white)
                    .background(AppStyle.bar.ignoresSafeArea(edges: .top))
                    HomeTabBar(tabs: homeTabs, selection: currentTab, title: tabTitle, symbol: tabSymbol, thumbnail: tabThumbnail,
                               onCustomize: { sheet = .tabs })
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
            // Dragging from the left edge pulls the drawer out, as in NewPipe. Taps and scrolling are unaffected.
            .simultaneousGesture(DragGesture(minimumDistance: 8, coordinateSpace: .global)
                .onChanged { value in
                    guard !menuVisible, value.startLocation.x < 24, value.translation.width > 0 || drawerDrag != nil else { return }
                    drawerDrag = min(0, -drawerWidth + max(0, value.translation.width))
                }
                .onEnded { value in
                    guard !menuVisible, drawerDrag != nil else { return }
                    settleDrawer(open: value.translation.width > drawerWidth / 3 || value.predictedEndTranslation.width > drawerWidth / 2)
                })
            if menuVisible || drawerDrag != nil {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Button { closeDrawer() } label: {
                            Color.black.opacity(0.4 * (1 + (drawerDrag ?? 0) / drawerWidth)).ignoresSafeArea()
                        }
                            .accessibilityLabel("Close main menu")
                        VStack(alignment: .leading, spacing: 0) {
                            VStack(alignment: .leading, spacing: 10) {
                                Label { Text("DriftLoom") } icon: { Image("BrandMark").resizable().scaledToFit().frame(width: 28, height: 28) }
                                    .font(.title2.weight(.bold))
                                Text("YouTube · SoundCloud").font(.subheadline)
                            }
                            .foregroundColor(.white).frame(maxWidth: .infinity, alignment: .leading).padding(24).background(AppStyle.bar)
                            ScrollView {
                                VStack(spacing: 0) {
                                    ForEach(HomeSection.allCases) { section in
                                        Button {
                                            if !preferences.homeSections.contains(section) { preferences.setHomeSections(preferences.homeSections + [section]) }
                                            selectedPinned = nil; selectedLocal = nil; selection = section; menuVisible = false
                                        } label: {
                                            Label(section.title, systemImage: section.symbol)
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
                                    drawerButton(String(localized: "Search"), id: "Search", symbol: "magnifyingglass") { onSearch() }
                                    drawerButton(String(localized: "Open a link"), id: "Open a link", symbol: "link") { sheet = .link }
                                    drawerButton(String(localized: "Downloads"), id: "Downloads", symbol: "arrow.down.circle") { sheet = .downloads }
                                    drawerButton(String(localized: "User guide"), id: "User guide", symbol: "book") { sheet = .guide }
                                    drawerButton(String(localized: "Settings"), id: "Settings", symbol: "gearshape") { sheet = .settings }
                                    drawerButton(String(localized: "About"), id: "About", symbol: "info.circle") { sheet = .about }
                                }
                            }
                        }
                        .frame(width: drawerWidth, height: geometry.size.height)
                        .background(Color(.systemBackground)).shadow(radius: 10)
                        .offset(x: drawerDrag ?? 0)
                        .accessibilityElement(children: .contain).accessibilityIdentifier("navigationDrawer")
                    }
                    // Dragging the drawer or the dimmed area to the left pushes it back; vertical drags still scroll it.
                    .simultaneousGesture(DragGesture(minimumDistance: 12, coordinateSpace: .global)
                        .onChanged { value in
                            guard drawerDrag != nil || (value.translation.width < 0 && abs(value.translation.width) > abs(value.translation.height)) else { return }
                            drawerDrag = max(-drawerWidth, min(0, value.translation.width))
                        }
                        .onEnded { value in
                            guard drawerDrag != nil else { return }
                            settleDrawer(open: !(value.translation.width < -drawerWidth / 3 || value.predictedEndTranslation.width < -drawerWidth / 2))
                        })
                }
                .transition(.move(edge: .leading)).zIndex(2)
            }
        }
        .background(GeometryReader { proxy in
            Color.clear.onAppear { containerWidth = proxy.size.width }.onChange(of: proxy.size.width) { containerWidth = $0 }
        })
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
#if DEBUG || DRIFTLOOM_DEVICE_TESTING
        // --settings-smoke: open Settings at launch, for device screenshots.
        .task {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--settings-smoke") { try? await Task.sleep(nanoseconds: 1_500_000_000); sheet = .settings }
            // --guide-smoke [page.md]: open the user guide, optionally at a page.
            if arguments.contains("--guide-smoke") { try? await Task.sleep(nanoseconds: 1_500_000_000); sheet = .guide }
            // --kiosk-more-smoke: open Live, whose list then loads more (see KioskView).
            if arguments.contains("--kiosk-more-smoke") { selectedPinned = nil; selectedLocal = nil; selection = .live }
            // --feed-smoke: open What's new, for device screenshots.
            if arguments.contains("--feed-smoke") { try? await Task.sleep(nanoseconds: 1_500_000_000); NotificationCenter.default.post(name: .driftLoomOpenFeed, object: nil) }
        }
#endif
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
                        .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { sheet = nil }.accessibilityIdentifier("closeSheet") } }
                }
            case .groups: SubscriptionGroupsView()
            case .settings: SettingsView()
            case .about: AboutView()
            case .guide:
                AppNavigation {
                    UserGuideView()
                        .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { sheet = nil }.accessibilityIdentifier("closeSheet") } }
                }
            case .tabs:
                AppNavigation {
                    HomeTabsSettings()
                        .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { sheet = nil }.accessibilityIdentifier("closeSheet") } }
                }
            case .link: OpenVideoLinkView { video in pendingVideo = video; sheet = nil }
            }
        }
    }
    /// Finish a drag: slide the drawer fully open or closed from where the finger left it.
    private func settleDrawer(open: Bool) {
        withAnimation(.easeOut(duration: 0.2)) { drawerDrag = open ? 0 : -drawerWidth }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            menuVisible = open
            drawerDrag = nil
        }
    }
    private func closeDrawer() { settleDrawer(open: false) }
    private func drawerButton(_ title: String, id: String? = nil, symbol: String, action: @escaping () -> Void) -> some View {
        Button { menuVisible = false; action() } label: {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity, alignment: .leading).padding(16).foregroundStyle(.primary)
        }.buttonStyle(.plain).accessibilityIdentifier("drawer-" + (id ?? title))
    }
}

private struct KioskView: View {
    let kiosk: YouTubeKiosk
    let onPlay: (BrowseItem) -> Void
    @EnvironmentObject private var preferences: AppPreferences
    @StateObject private var store = BrowseStore()
    var body: some View {
        VStack(spacing: 0) {
            Text("YouTube · " + kiosk.title + " · " + preferences.contentLocale.country).font(.caption).foregroundStyle(.secondary).padding(8)
                .accessibilityIdentifier("kioskSource").accessibilityValue(Text("\(store.items.count) shown"))
            BrowseResults(store: store, onPlay: onPlay, retry: { Task { await store.load(.kiosk(kiosk)) } })
        }.task(id: preferences.contentLocale) {
            await store.load(.kiosk(kiosk))
#if DEBUG || DRIFTLOOM_DEVICE_TESTING
            // --kiosk-more-smoke: load more three times and log the counts, for device checks.
            if ProcessInfo.processInfo.arguments.contains("--kiosk-more-smoke") {
                var counts = [store.items.count]
                for _ in 0..<3 where store.canLoadMore { await store.loadMore(); counts.append(store.items.count) }
                let grew = counts.count == 4 && zip(counts, counts.dropFirst()).allSatisfy { $0 < $1 }
                NSLog("DriftLoomKioskMoreSmoke: %@ %@ counts=%@", grew ? "PASS" : "FAIL", kiosk.rawValue, counts.map(String.init).joined(separator: ","))
            }
#endif
        }
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
    /// "21 min ago": upload times from a channel's Videos tab are approximate, so no live seconds counter.
    private static let age: RelativeDateTimeFormatter = { let formatter = RelativeDateTimeFormatter(); formatter.unitsStyle = .short; return formatter }()
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
                        ForEach(FeedPeriod.allCases) { Text($0.title).tag($0) }
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
                    Text("Recent uploads from each channel; each channel supplies a limited number of videos.")
                        .font(.caption).foregroundStyle(.secondary)
                    if preferences.feedPeriod != .all || preferences.hidesWatchedFeed {
                        Text(preferences.feedPeriod.title + (preferences.hidesWatchedFeed ? " · " + String(localized: "Watched videos hidden") : "")).font(.caption)
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
                            Text(Self.age.localizedString(for: entry.published, relativeTo: Date())).font(.caption2).foregroundStyle(.secondary)
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
            .toolbar { Button("Cancel") { dismiss() }.accessibilityIdentifier("closeSheet") }
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
            onOpen(BrowseItem(contentID: video.videoID, kind: .video, title: PlaybackSession.placeholderTitle))
        } catch { self.error = error.localizedDescription }
    }
}
