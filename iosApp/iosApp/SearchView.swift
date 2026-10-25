// SPDX-License-Identifier: GPL-3.0-or-later
import DriftLoomPlayback
import SwiftUI

struct SearchView: View {
    let onPlay: (BrowseItem) -> Void
    @StateObject private var results = BrowseStore()
    @State private var query = ""
    @State private var submittedQuery = ""

    var body: some View {
        AppNavigation {
            Group {
                if submittedQuery.isEmpty {
                    EmptyStateView("Find your next discovery", systemImage: "magnifyingglass",
                                           message: "Search YouTube for videos, channels, and playlists.")
                } else {
                    BrowseResults(store: results, onPlay: onPlay, retry: {
                        Task { await results.load(.search(submittedQuery)) }
                    })
                }
            }
            .navigationTitle("Discover")
            .searchable(text: $query, prompt: "Search YouTube")
            .onSubmit(of: .search, submit)
            .task {
#if DEBUG || DRIFTLOOM_DEVICE_TESTING
                let arguments = ProcessInfo.processInfo.arguments
                if submittedQuery.isEmpty, let flag = arguments.firstIndex(of: "--browse-smoke-query"), arguments.indices.contains(flag + 1) {
                    query = arguments[flag + 1]
                    submit()
                }
#endif
            }
            .task(id: submittedQuery) {
                guard !submittedQuery.isEmpty else { return }
                await results.load(.search(submittedQuery))
#if DEBUG || DRIFTLOOM_DEVICE_TESTING
                await runBrowseSmokeCheck(results, onPlay: onPlay)
#endif
            }
        }
    }

    private func submit() {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        // Re-submitting the same search also provides a fresh retry.
        if submittedQuery == value { Task { await results.load(.search(value)) } }
        else { submittedQuery = value }
    }
}

struct BrowsePageView: View {
    @EnvironmentObject private var library: LibraryStore
    let route: BrowseRoute
    let onPlay: (BrowseItem) -> Void
    @StateObject private var store = BrowseStore()

    var body: some View {
        BrowseResults(store: store, onPlay: onPlay, retry: { Task { await store.load(route) } })
            .navigationTitle(store.title.isEmpty ? fallbackTitle : store.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if case let .channel(id) = route, store.hasLoaded {
                    IconButton(library.isSubscribed(id) ? "Subscribed" : "Subscribe",
                           systemImage: library.isSubscribed(id) ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.plus") {
                        library.toggleSubscription(BrowseItem(contentID: id, kind: .channel, title: store.title))
                    }
                    .disabled(!library.isWritable)
                }
            }
            .task(id: route) { await store.load(route) }
    }

    private var fallbackTitle: String {
        switch route {
        case .channel: return "Channel"
        case .playlist: return "Playlist"
        case .mix: return "Mix"
        case .search: return "Results"
        case .related: return "Related videos"
        }
    }
}

private struct BrowseResults: View {
    @ObservedObject var store: BrowseStore
    let onPlay: (BrowseItem) -> Void
    let retry: () -> Void

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
                EmptyStateView("No results", systemImage: "magnifyingglass",
                                       message: "Try a different search, or explore another page.")
            } else {
                List {
                    ForEach(store.items) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            if let destination = item.destination {
                                BrowseLink(route: destination, onPlay: onPlay) { BrowseRow(item: item) }
                            } else {
                                Button { onPlay(item) } label: { BrowseRow(item: item) }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("searchVideo-\(item.contentID)")
                            }
                            if item.kind == .video, let channelID = item.channelID, !item.subtitle.isEmpty {
                                BrowseLink(route: .channel(channelID), onPlay: onPlay) {
                                    Label(item.subtitle, systemImage: "person.crop.circle")
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                        .contextMenu { LibraryItemActions(item: item) }
                        .listRowSeparator(.hidden)
                        .padding(.vertical, 4)
                    }
                    if let message = store.paginationError {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                    if store.canLoadMore {
                        Button {
                            Task { await store.loadMore() }
                        } label: {
                            HStack {
                                Spacer()
                                if store.isLoadingMore { ProgressView() }
                                else { Text(store.paginationError == nil ? "Load more" : "Try loading more again") }
                                Spacer()
                            }
                        }
                        .disabled(store.isLoadingMore)
                    }
                }
                .listStyle(.plain)
                .dismissKeyboardOnScroll()
            }
        }
    }
}

struct BrowseRow: View {
    let item: BrowseItem
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: item.thumbnail) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(.quaternary)
                    .overlay { Image(systemName: symbol).foregroundStyle(.secondary) }
            }
            .frame(width: 136, height: 77)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: item.kind == .channel ? 30 : 10))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(3)
                    .foregroundStyle(.primary)
                if item.kind != .video || item.channelID == nil {
                    Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                if let duration = item.duration {
                    Text(duration).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                } else if item.kind != .video {
                    Label(item.kind == .channel ? "Channel" : "Playlist", systemImage: symbol)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
    private var symbol: String {
        switch item.kind {
        case .video: return "play.rectangle"
        case .channel: return "person.crop.circle"
        case .playlist: return "rectangle.stack"
        }
    }
}
