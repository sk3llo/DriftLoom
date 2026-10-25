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
                                Text(title(value).uppercased()).font(.caption.weight(.semibold))
                                    .foregroundColor(selection == value ? AppStyle.accent : .secondary)
                                    .padding(.horizontal, 16).frame(minHeight: 46)
                                Rectangle().fill(selection == value ? AppStyle.accent : .clear).frame(height: 2)
                            }
                        }.buttonStyle(.plain).id(value)
                            .accessibilityAddTraits(selection == value ? .isSelected : [])
                    }
                }
            }.onChange(of: selection) { value in withAnimation { proxy.scrollTo(value, anchor: .center) } }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(.secondarySystemBackground))
    }
}

private enum HomeSheet: String, Identifiable {
    case settings, about, link
    var id: String { rawValue }
}

struct HomeView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @Binding var selection: HomeSection
    let onSearch: () -> Void
    let onPlay: (BrowseItem) -> Void
    @State private var menuVisible = false
    @State private var sheet: HomeSheet?
    @State private var pendingVideo: BrowseItem?
    @StateObject private var feed = SubscriptionFeedStore()
    var body: some View {
        ZStack(alignment: .leading) {
            AppNavigation {
                VStack(spacing: 0) {
                    SectionStrip(values: preferences.homeSections, selection: $selection, title: { $0.rawValue })
                    if selection == .feed { FeedView(store: feed, onPlay: onPlay) }
                    else if selection == .bookmarks { BookmarksView(onPlay: onPlay) }
                    else { LibrarySectionView(section: selection, onPlay: onPlay).id(selection) }
                }
                .navigationTitle("DriftLoom").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button { menuVisible = true } label: { Image(systemName: "line.3.horizontal") }
                            .accessibilityLabel("Main menu").accessibilityIdentifier("mainMenu")
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: onSearch) { Image(systemName: "magnifyingglass") }
                            .accessibilityLabel("Search").accessibilityIdentifier("openSearch")
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            IconButton("Open a link", systemImage: "link") { sheet = .link }
                            IconButton("Settings", systemImage: "gearshape") { sheet = .settings }
                            IconButton("About", systemImage: "info.circle") { sheet = .about }
                        } label: { Image(systemName: "ellipsis").rotationEffect(.degrees(90)) }
                        .accessibilityLabel("More options")
                    }
                }
            }
            if menuVisible {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Button { menuVisible = false } label: { Color.black.opacity(0.4).ignoresSafeArea() }
                            .accessibilityLabel("Close main menu")
                        VStack(alignment: .leading, spacing: 0) {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("DriftLoom", systemImage: "play.rectangle.fill").font(.title2.weight(.bold))
                                Text("YouTube").font(.subheadline)
                            }
                            .foregroundColor(.white).frame(maxWidth: .infinity, alignment: .leading).padding(24).background(AppStyle.accent)
                            ScrollView {
                                VStack(spacing: 0) {
                                    ForEach(HomeSection.allCases) { section in
                                        Button {
                                            if !preferences.homeSections.contains(section) { preferences.setHomeSections(preferences.homeSections + [section]) }
                                            selection = section; menuVisible = false
                                        } label: {
                                            Label(section.rawValue, systemImage: section.symbol)
                                                .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                                                .foregroundColor(selection == section ? AppStyle.accent : .primary)
                                                .background(selection == section ? AppStyle.accent.opacity(0.08) : .clear)
                                        }
                                    }
                                    Divider().padding(.vertical, 8)
                                    drawerButton("Search", symbol: "magnifyingglass") { onSearch() }
                                    drawerButton("Open a link", symbol: "link") { sheet = .link }
                                    drawerButton("Settings", symbol: "gearshape") { sheet = .settings }
                                    drawerButton("About", symbol: "info.circle") { sheet = .about }
                                }
                            }
                        }
                        .frame(width: min(320, geometry.size.width * 0.85), height: geometry.size.height)
                        .background(Color(.systemBackground)).shadow(radius: 10)
                        .accessibilityIdentifier("navigationDrawer")
                    }
                }.zIndex(1)
            }
        }
        .sheet(item: $sheet, onDismiss: {
            if let video = pendingVideo { pendingVideo = nil; onPlay(video) }
        }) { target in
            switch target {
            case .settings: SettingsView()
            case .about: AboutView()
            case .link: OpenVideoLinkView { video in pendingVideo = video; sheet = nil }
            }
        }
    }
    private func drawerButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button { menuVisible = false; action() } label: {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity, alignment: .leading).padding(16).foregroundStyle(.primary)
        }
    }
}

private struct FeedView: View {
    @EnvironmentObject private var library: LibraryStore
    @ObservedObject var store: SubscriptionFeedStore
    let onPlay: (BrowseItem) -> Void
    private var channels: [String] { library.subscriptions.map { $0.item.contentID } }
    var body: some View {
        Group {
            if channels.isEmpty {
                EmptyStateView("No new videos", systemImage: "tray", message: "Subscribe to channels to build your feed.")
            } else {
                List {
                    if store.loading {
                        HStack { ProgressView(); Text("Refreshing \(store.completedChannels) of \(channels.count) channels…").font(.footnote) }
                    }
                    if store.failedChannels > 0 {
                        Text("\(store.failedChannels) channel feeds could not be loaded. Pull to refresh and try again.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if !store.loading, store.items.isEmpty {
                        Text("No recent videos are available.").foregroundStyle(.secondary)
                    }
                    ForEach(store.items) { entry in
                        VStack(alignment: .leading, spacing: 5) {
                            BrowseResultRow(item: entry.item, onPlay: onPlay)
                            Text(entry.published, style: .relative).font(.caption2).foregroundStyle(.secondary)
                        }.listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 4))
                    }
                }.listStyle(.plain).refreshable { await store.load(channelIDs: channels) }
            }
        }
        .task(id: channels) {
            if !channels.isEmpty { await store.load(channelIDs: channels) }
        }
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
                TextField("YouTube video link", text: $input).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .submitLabel(.go).onSubmit(open)
                if let error { Text(error).foregroundColor(.red).font(.footnote) }
                Button("Open", action: open).disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .navigationTitle("Open a link").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Cancel") { dismiss() } }
        }
    }
    private func open() {
        do {
            let video = try VideoRequest(input: input)
            onOpen(BrowseItem(contentID: video.videoID, kind: .video, title: "YouTube video"))
        } catch { self.error = error.localizedDescription }
    }
}
