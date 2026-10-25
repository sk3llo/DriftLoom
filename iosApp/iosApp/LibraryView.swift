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
                       systemImage: library.isSaved(item.contentID) ? "bookmark.slash" : "bookmark") {
                    library.toggleSaved(item)
                }
            }
            if let channel = channel {
                IconButton(library.isSubscribed(channel.contentID) ? "Unsubscribe" : "Subscribe",
                       systemImage: "person.crop.circle.badge.plus") {
                    library.toggleSubscription(channel)
                }
            }
        }
        .disabled(!library.isWritable)
    }
    private var channel: BrowseItem? {
        if item.kind == .channel { return item }
        guard let id = item.channelID, !item.subtitle.isEmpty else { return nil }
        return BrowseItem(contentID: id, kind: .channel, title: item.subtitle)
    }
}

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    let onPlay: (BrowseItem) -> Void
    @State private var section = Section.saved
    @State private var confirmsClearHistory = false

    private enum Section: String, CaseIterable {
        case saved = "Saved", subscriptions = "Subscriptions", history = "History"
    }
    private var records: [LibraryRecord] {
        switch section {
        case .saved: return library.saved
        case .subscriptions: return library.subscriptions
        case .history: return library.history
        }
    }

    var body: some View {
        AppNavigation {
            VStack(spacing: 0) {
                Picker("Library section", selection: $section) {
                    ForEach(Section.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).padding()
                if !library.isWritable {
                    VStack(spacing: 10) {
                        Text("Your saved library is unavailable. Its file has been left untouched.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("Try loading again", action: library.reload)
                    }.padding()
                }
                if section == .history {
                    Toggle("Record watch history", isOn: Binding(
                        get: { library.historyEnabled }, set: library.setHistoryEnabled
                    ))
                    .disabled(!library.isWritable)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
                if records.isEmpty {
                    EmptyStateView(emptyTitle, systemImage: symbol, message: emptyMessage)
                } else {
                    List(records) { record in
                        VStack(alignment: .leading, spacing: 8) {
                            if section == .subscriptions {
                                BrowseLink(route: .channel(record.item.contentID), onPlay: onPlay) {
                                    BrowseRow(item: record.item)
                                }
                            } else {
                                Button { onPlay(record.item) } label: { BrowseRow(item: record.item) }
                                    .buttonStyle(.plain)
                                if section == .history {
                                    Text(record.date, style: .relative)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .listRowSeparator(.hidden)
                        .contextMenu { LibraryItemActions(item: record.item) }
                        .swipeActions {
                            Button(section == .subscriptions ? "Unsubscribe" : "Remove", role: .destructive) {
                                remove(record.item.contentID)
                            }
                            .disabled(!library.isWritable)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Library")
            .toolbar {
                if section == .history, !records.isEmpty {
                    IconButton("Clear history", systemImage: "trash") { confirmsClearHistory = true }
                        .disabled(!library.isWritable)
                }
            }
            .confirmationDialog("Clear watch history?", isPresented: $confirmsClearHistory, titleVisibility: .visible) {
                Button("Clear history", role: .destructive, action: library.clearHistory)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Saved videos and subscriptions will stay in your library.")
            }
        }
#if DEBUG || DRIFTLOOM_DEVICE_TESTING
        .task {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--library-smoke-run"),
               let flag = arguments.firstIndex(of: "--library-smoke-section"), arguments.indices.contains(flag + 1),
               let requested = Section(rawValue: arguments[flag + 1]) { section = requested }
        }
#endif
    }

    private func remove(_ id: String) {
        switch section {
        case .saved: library.removeSaved(id)
        case .subscriptions: library.unsubscribe(id)
        case .history: library.removeHistory(id)
        }
    }
    private var symbol: String {
        switch section {
        case .saved: return "bookmark"
        case .subscriptions: return "person.crop.circle"
        case .history: return "clock"
        }
    }
    private var emptyTitle: String {
        switch section {
        case .saved: return "Keep a few discoveries"
        case .subscriptions: return "Follow your favorite channels"
        case .history: return "Your recently watched videos"
        }
    }
    private var emptyMessage: String {
        switch section {
        case .saved: return "Save a video from its player or the menu on a search result."
        case .subscriptions: return "Subscribe from a channel page or its search result menu."
        case .history: return library.historyEnabled ? "Videos appear here once playback starts." : "New playback isn't being recorded."
        }
    }
}
