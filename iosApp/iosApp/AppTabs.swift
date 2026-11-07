// SPDX-License-Identifier: GPL-3.0-or-later
import DriftLoomPlayback
import SwiftUI

/// The tabs of the tab bar.
enum AppTab: Hashable { case home, subscriptions, library, search, settings }

/// A Library page to open, from a notification, the download strip or a launch flag.
struct LibraryRequest: Equatable {
    let id = UUID()
    let page: String
}

/// Subscriptions: new videos from subscribed channels, or the channels themselves, filtered by group.
struct SubscriptionsView: View {
    enum Page: Hashable { case feed, channels }
    @EnvironmentObject private var groups: SubscriptionGroups
    let onPlay: (BrowseItem) -> Void
    @Binding var page: Page
    @State private var group: UUID?
    @State private var managingGroups = false
    @StateObject private var feed = SubscriptionFeedStore()
    private var groupName: String? { groups.groups.first { $0.id == group }?.name }

    var body: some View {
        AppNavigation {
            VStack(spacing: 0) {
                if let groupName {
                    HStack {
                        Label(groupName, systemImage: "folder").font(.subheadline).lineLimit(1)
                        Spacer()
                        Button("Show all") { group = nil }.font(.subheadline)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .accessibilityElement(children: .contain).accessibilityIdentifier("selectedGroup")
                    Divider()
                }
                if page == .feed { FeedView(store: feed, selectedGroup: group, onPlay: onPlay) }
                else { LibrarySectionView(section: .subscriptions, group: group, onPlay: onPlay) }
            }
            .navigationTitle("Subscriptions").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Subscriptions", selection: $page) {
                        Text("What's new").tag(Page.feed)
                        Text("Channels").tag(Page.channels)
                    }
                    .pickerStyle(.segmented).fixedSize().accessibilityIdentifier("subscriptionsPage")
                }
                ToolbarItem(placement: .navigationBarLeading) { groupMenu }
            }
            .sheet(isPresented: $managingGroups) { SubscriptionGroupsView() }
        }
        .onChange(of: groups.groups.map(\.id)) { ids in
            if let id = group, !ids.contains(id) { group = nil }
        }
    }

    private var groupMenu: some View {
        Menu {
            Picker("Subscription group", selection: $group) {
                Text("All subscriptions").tag(UUID?.none)
                ForEach(groups.groups) { group in Text(group.name).tag(Optional(group.id)) }
            }
            Divider()
            IconButton("Manage subscription groups", systemImage: "folder.badge.gearshape") { managingGroups = true }
        } label: {
            Image(systemName: group == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityLabel("Subscription group").accessibilityIdentifier("subscriptionGroupFilter")
    }
}

/// Library: bookmarks and playlists, watch history and downloads.
struct LibraryTabView: View {
    let onPlay: (BrowseItem) -> Void
    @Binding var request: LibraryRequest?
    /// iOS 16 and later: the pushed pages, so a request can replace whatever is open.
    @State private var path: [String] = []
    /// iOS 15: the open page, through tagged links.
    @State private var opened: String?
    @EnvironmentObject private var playlists: PlaylistStore
    @EnvironmentObject private var library: LibraryStore
    @ObservedObject private var downloads = DownloadManager.shared
    private static let pages = ["bookmarks", "history", "downloads"]

    var body: some View {
        Group {
            if #available(iOS 16, *) {
                NavigationStack(path: $path) {
                    list { page in NavigationLink(value: page) { row(page) } }
                        .navigationDestination(for: String.self) { destination($0) }
                }
            } else {
                NavigationView {
                    list { page in NavigationLink(tag: page, selection: $opened) { destination(page) } label: { row(page) } }
                }.navigationViewStyle(.stack)
            }
        }
        .onAppear(perform: openRequested)
        .onChange(of: request) { _ in openRequested() }
    }

    private func list<Link: View>(@ViewBuilder link: @escaping (String) -> Link) -> some View {
        List {
            ForEach(Self.pages, id: \.self) { page in link(page).accessibilityIdentifier("library-" + page) }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Library")
    }

    @ViewBuilder private func destination(_ page: String) -> some View {
        switch page {
        case "bookmarks": BookmarksView(onPlay: onPlay).navigationTitle("Bookmarked").navigationBarTitleDisplayMode(.inline)
        case "history": LibrarySectionView(section: .history, onPlay: onPlay).navigationTitle("History").navigationBarTitleDisplayMode(.inline)
        default: DownloadsView(onPlay: onPlay)
        }
    }

    /// Opens a requested page in place of any open one. iOS 15's tagged links need the list on screen first.
    private func openRequested() {
        guard let page = request?.page else { return }
        request = nil
        if #available(iOS 16, *) { path = [page]; return }
        let delay = opened == nil ? 0.3 : 0.6
        opened = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { opened = page }
    }

    @ViewBuilder private func row(_ page: String) -> some View {
        switch page {
        case "bookmarks": row("Bookmarked", symbol: "bookmark", count: playlists.playlists.count + playlists.bookmarks.count + library.saved.count)
        case "history": row("History", symbol: "clock", count: library.history.count)
        default: row("Downloads", symbol: "arrow.down.circle", count: downloads.records.count)
        }
    }

    private func row(_ title: LocalizedStringKey, symbol: String, count: Int) -> some View {
        HStack {
            Label { Text(title) } icon: { Image(systemName: symbol).foregroundColor(AppStyle.accent) }
            Spacer()
            if count > 0 { Text("\(count)").foregroundStyle(.secondary) }
        }
    }
}

/// Subscribe or unsubscribe, as a filled capsule that turns plain once subscribed.
struct SubscribeButton: View {
    let subscribed: Bool
    let action: () -> Void
    var body: some View {
        Group {
            if subscribed { Button("Subscribed", action: action).buttonStyle(.bordered) }
            else { Button("Subscribe", action: action).buttonStyle(.borderedProminent) }
        }
        .buttonBorderShape(.capsule).controlSize(.small).font(.subheadline.weight(.semibold))
        .accessibilityIdentifier("subscribeButton")
    }
}
