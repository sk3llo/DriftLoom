// SPDX-License-Identifier: GPL-3.0-or-later
import DriftLoomPlayback
import SwiftUI

enum AppStyle {
    /// Buttons, links and progress: the icon's coral stripes, darker in light mode so text stays readable.
    static let accent = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0xFF / 255, green: 0x8A / 255, blue: 0x5B / 255, alpha: 1)
            : UIColor(red: 0xC2 / 255, green: 0x41 / 255, blue: 0x0C / 255, alpha: 1)
    })
    /// The app icon's violet background, deeper in dark mode, for brand marks. Keep it in step with
    /// branding/generate.py and the Android `*_youtube_primary_color` resources.
    static let bar = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0x1F / 255, green: 0x16 / 255, blue: 0x50 / 255, alpha: 1)
            : UIColor(red: 0x2E / 255, green: 0x1C / 255, blue: 0x66 / 255, alpha: 1)
    })
}

extension HomeSection {
    /// Sections that browse YouTube or SoundCloud. Subscriptions, What's new, Bookmarked and History have
    /// their own tabs on iOS, so Home shows only these and pinned pages.
    var isBrowse: Bool {
        switch self {
        case .trending, .live, .gaming, .podcasts, .trailers, .soundCloud: return true
        case .subscriptions, .feed, .bookmarks, .history: return false
        }
    }
    /// The home sections shown on iOS, never empty.
    static func shownOnHome(_ sections: [HomeSection]) -> [HomeSection] {
        let browse = sections.filter(\.isBrowse)
        return browse.isEmpty ? [.live] : browse
    }
}

/// A row of segments for a page's sections: All/Videos/Channels, Related/Comments, a channel's tabs.
struct SectionStrip<Value: Hashable>: View {
    let values: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    var body: some View {
        Picker("Section", selection: $selection) {
            ForEach(values, id: \.self) { Text(title($0)).tag($0) }
        }
        .pickerStyle(.segmented).labelsHidden()
        .padding(.horizontal, 12).padding(.vertical, 8)
        .accessibilityIdentifier("sectionPicker")
    }
}

/// The navigation title as a menu, as Mail and Files switch mailboxes and locations: a native title menu on
/// iOS 16 and later, and a title button with a chevron on iOS 15.
private struct TitleMenu<Items: View>: ViewModifier {
    let title: String
    @ViewBuilder let items: () -> Items
    func body(content: Content) -> some View {
        if #available(iOS 16, *) {
            content.navigationTitle(title).toolbarTitleMenu(content: items)
        } else {
            content.navigationTitle(title).toolbar {
                ToolbarItem(placement: .principal) {
                    Menu(content: items) {
                        HStack(spacing: 4) {
                            Text(title).font(.headline).foregroundColor(.primary).lineLimit(1)
                            Image(systemName: "chevron.down.circle.fill").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.accessibilityIdentifier("homeTitle")
                }
            }
        }
    }
}

private enum HomeSheet: String, Identifiable {
    case link, tabs
    var id: String { rawValue }
}

struct HomeView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var pinnedTabs: PinnedHomeTabs
    @EnvironmentObject private var playlists: PlaylistStore
    @Binding var selection: HomeSection
    let onPlay: (BrowseItem) -> Void
    @State private var sheet: HomeSheet?
    @State private var pendingVideo: BrowseItem?
    @StateObject private var pinnedPage = BrowseStore()
    @State private var selectedPinned: String?
    @State private var selectedLocal: UUID?
    private var homeTabs: [HomeTabKey] {
        pinnedTabs.arrangement(sections: HomeSection.shownOnHome(preferences.homeSections), localPlaylistIDs: Set(playlists.playlists.map(\.id)))
    }
    private var currentTab: Binding<HomeTabKey> {
        Binding(get: {
            if let id = selectedLocal { return .local(id) }
            if let id = selectedPinned { return .pinned(id) }
            return selection.isBrowse ? .section(selection) : homeTabs.first ?? .section(.live)
        }, set: { tab in
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
    var body: some View {
        AppNavigation {
            page
                .navigationBarTitleDisplayMode(.inline)
                .modifier(TitleMenu(title: tabTitle(currentTab.wrappedValue)) {
                    Picker("Home tabs", selection: currentTab) {
                        ForEach(homeTabs, id: \.self) { tab in
                            Label(tabTitle(tab), systemImage: tabSymbol(tab)).tag(tab)
                        }
                    }
                    Divider()
                    IconButton("Customize tabs", systemImage: "slider.horizontal.3") { sheet = .tabs }
                })
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button { sheet = .link } label: { Image(systemName: "link") }
                            .accessibilityLabel("Open a link").accessibilityIdentifier("openLink")
                    }
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
#if DEBUG || DRIFTLOOM_DEVICE_TESTING
        .task {
            // --kiosk-more-smoke: open Live, whose list then loads more (see KioskView).
            if ProcessInfo.processInfo.arguments.contains("--kiosk-more-smoke") { selectedPinned = nil; selectedLocal = nil; selection = .live }
        }
#endif
        .sheet(item: $sheet, onDismiss: {
            if let video = pendingVideo { pendingVideo = nil; onPlay(video) }
        }) { target in
            switch target {
            case .tabs:
                AppNavigation {
                    HomeTabsSettings()
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { sheet = nil }.accessibilityIdentifier("closeSheet") } }
                }
            case .link: OpenVideoLinkView { video in pendingVideo = video; sheet = nil }
            }
        }
    }
    @ViewBuilder private var page: some View {
        switch currentTab.wrappedValue {
        case let .local(id) where playlists.playlists.contains(where: { $0.id == id }):
            LocalPlaylistView(id: id, onPlay: onPlay, embedded: true).id(id)
        case let .pinned(id):
            if let tab = pinnedTabs.tabs.first(where: { $0.id == id }) { PinnedPageView(item: tab.item, store: pinnedPage, onPlay: onPlay) }
        case let .section(section):
            if section == .trending { TrendingMusicView(onPlay: onPlay) }
            else if let kiosk = section.kiosk { KioskView(kiosk: kiosk, onPlay: onPlay).id(kiosk) }
            else { SoundCloudTrendingView(onPlay: onPlay) }
        default: EmptyView()
        }
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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu { BrowseItemMenu(item: item, onPlay: onPlay) } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("Pinned tab options").accessibilityIdentifier("pinnedTabOptions")
            }
        }
    }
}

struct FeedView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var groups: SubscriptionGroups
    @EnvironmentObject private var preferences: AppPreferences
    @ObservedObject var store: SubscriptionFeedStore
    /// The subscription group to show, or nil for all subscriptions.
    let selectedGroup: UUID?
    let onPlay: (BrowseItem) -> Void
    /// "21 min ago": upload times from a channel's Videos tab are approximate, so no live seconds counter.
    private static let age: RelativeDateTimeFormatter = { let formatter = RelativeDateTimeFormatter(); formatter.unitsStyle = .short; return formatter }()
    private var channels: [String] { groups.channelIDs(for: selectedGroup, subscribed: library.subscriptions.map { $0.item.contentID }) }
    private var visible: [FeedVideo] {
        FeedFilter.apply(store.items, period: preferences.feedPeriod, hidingWatched: preferences.hidesWatchedFeed,
                         watchedIDs: Set(library.history.map { $0.item.contentID }))
    }
    var body: some View {
        Group {
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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Picker("Upload date", selection: Binding(get: { preferences.feedPeriod }, set: preferences.setFeedPeriod)) {
                        ForEach(FeedPeriod.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Hide watched videos", isOn: Binding(get: { preferences.hidesWatchedFeed }, set: preferences.setHidesWatchedFeed))
                    Divider()
                    IconButton("Refresh feed", systemImage: "arrow.clockwise") { Task { await store.load(channelIDs: channels) } }
                        .disabled(store.loading || channels.isEmpty)
                } label: { Image(systemName: "slider.horizontal.3") }
                    .accessibilityLabel("Feed filters").accessibilityIdentifier("feedFilters")
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
            }
            .navigationTitle("Open a link").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("closeSheet") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open", action: open).disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
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
