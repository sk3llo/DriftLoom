// SPDX-License-Identifier: GPL-3.0-or-later
import DriftLoomPlayback
import SwiftUI

struct LibraryItemActions: View {
    @EnvironmentObject private var library: LibraryStore
    let item: BrowseItem
    var body: some View {
        Group {
            if item.kind == .video {
                IconButton(library.isSaved(item.contentID) ? "Remove saved video" : "Save video",
                           systemImage: library.isSaved(item.contentID) ? "bookmark.slash" : "bookmark") { library.toggleSaved(item) }
            }
            if let channel = channel {
                IconButton(library.isSubscribed(channel.contentID) ? "Unsubscribe" : "Subscribe",
                           systemImage: "person.crop.circle.badge.plus") { library.toggleSubscription(channel) }
            }
        }.disabled(!library.isWritable)
    }
    private var channel: BrowseItem? {
        if item.kind == .channel { return item }
        guard let id = item.channelID, !item.subtitle.isEmpty else { return nil }
        return BrowseItem(contentID: id, kind: .channel, title: item.subtitle)
    }
}

struct LibrarySectionView: View {
    @EnvironmentObject private var library: LibraryStore
    let section: HomeSection
    let onPlay: (BrowseItem) -> Void
    @State private var confirmsClearHistory = false
    private var records: [LibraryRecord] {
        switch section { case .subscriptions: return library.subscriptions; case .history: return library.history; default: return library.saved }
    }
    var body: some View {
        VStack(spacing: 0) {
            if !library.isWritable {
                VStack(spacing: 8) {
                    Text("Your saved library is unavailable. Its file has been left untouched.").font(.footnote)
                    Button("Try loading again", action: library.reload)
                }.padding()
            }
            if records.isEmpty {
                EmptyStateView(emptyTitle, systemImage: section.symbol, message: emptyMessage)
            } else {
                List(records) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        BrowseResultRow(item: record.item, onPlay: onPlay)
                        if section == .history { Text(record.date, style: .relative).font(.caption2).foregroundStyle(.secondary) }
                    }
                    .listRowInsets(EdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 4)).listRowSeparator(.hidden)
                    .swipeActions {
                        Button(section == .subscriptions ? "Unsubscribe" : "Remove", role: .destructive) { remove(record.item.contentID) }
                            .disabled(!library.isWritable)
                    }
                }.listStyle(.plain)
            }
        }
        .toolbar {
            if section == .history, !records.isEmpty {
                Button { confirmsClearHistory = true } label: { Image(systemName: "trash") }
                    .accessibilityLabel("Clear history").disabled(!library.isWritable)
            }
        }
        .confirmationDialog("Clear watch history?", isPresented: $confirmsClearHistory, titleVisibility: .visible) {
            Button("Clear history", role: .destructive, action: library.clearHistory)
            Button("Cancel", role: .cancel) {}
        } message: { Text("Saved videos and subscriptions will stay in your library.") }
    }
    private func remove(_ id: String) {
        switch section { case .subscriptions: library.unsubscribe(id); case .history: library.removeHistory(id); default: library.removeSaved(id) }
    }
    private var emptyTitle: String {
        switch section { case .subscriptions: return "No subscriptions"; case .history: return "No history"; default: return "No bookmarks" }
    }
    private var emptyMessage: String {
        switch section {
        case .subscriptions: return "Search for a channel and subscribe to see it here."
        case .history: return library.historyEnabled ? "Videos appear here once playback starts." : "Recording watch history is disabled in Settings."
        default: return "Save videos from their action menu or the video detail screen."
        }
    }
}
