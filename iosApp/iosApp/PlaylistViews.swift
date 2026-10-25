// SPDX-License-Identifier: GPL-3.0-or-later
import DriftLoomPlayback
import SwiftUI

struct BookmarksView: View {
    @EnvironmentObject private var playlists: PlaylistStore
    @EnvironmentObject private var library: LibraryStore
    let onPlay: (BrowseItem) -> Void
    @State private var creating = false
    var body: some View {
        VStack(spacing: 0) {
            if !playlists.isWritable {
                Text("Your playlist file is unavailable and has been left untouched.").font(.footnote).padding()
                Button("Try loading playlists again", action: playlists.reload)
            }
            if playlists.playlists.isEmpty, playlists.bookmarks.isEmpty, library.saved.isEmpty {
                EmptyStateView("No bookmarks", systemImage: "bookmark", message: "Save videos, bookmark online playlists, or create a local playlist.")
                Button("Create playlist") { creating = true }.padding().disabled(!playlists.isWritable)
            } else {
                List {
                    if !playlists.playlists.isEmpty {
                        Section("Local playlists") {
                            ForEach(playlists.playlists) { playlist in
                                NavigationLink {
                                    LocalPlaylistView(id: playlist.id, onPlay: onPlay)
                                } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: "music.note.list").frame(width: 52, height: 52).background(Color(.secondarySystemBackground))
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(playlist.name).font(.subheadline.weight(.medium))
                                            Text("\(playlist.entries.count) videos").font(.caption).foregroundStyle(.secondary)
                                        }
                                    }.padding(.vertical, 4)
                                }
                            }
                        }
                    }
                    if !playlists.bookmarks.isEmpty {
                        Section("Bookmarked playlists") {
                            ForEach(playlists.bookmarks) { item in BrowseResultRow(item: item, onPlay: onPlay) }
                        }
                    }
                    if !library.saved.isEmpty {
                        Section("Saved videos") {
                            ForEach(library.saved) { record in
                                BrowseResultRow(item: record.item, onPlay: onPlay)
                                    .swipeActions {
                                        Button("Remove", role: .destructive) { library.removeSaved(record.item.contentID) }.disabled(!library.isWritable)
                                    }
                            }
                        }
                    }
                }.listStyle(.plain)
            }
        }
        .toolbar {
            Button { creating = true } label: { Image(systemName: "plus") }
                .accessibilityLabel("Create playlist").disabled(!playlists.isWritable)
        }
        .sheet(isPresented: $creating) { PlaylistPickerView(item: nil) }
    }
}

struct PlaylistPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var playlists: PlaylistStore
    let item: BrowseItem?
    @State private var name = ""
    var body: some View {
        AppNavigation {
            Form {
                if let item, !playlists.playlists.isEmpty {
                    Section("Add to a playlist") {
                        ForEach(playlists.playlists) { playlist in
                            Button(playlist.name) { if playlists.add(item, to: playlist.id) { dismiss() } }
                        }
                    }
                }
                Section("Create a playlist") {
                    TextField("Playlist name", text: $name).accessibilityIdentifier("playlistName")
                    Button(item == nil ? "Create playlist" : "Create and add video") {
                        if playlists.create(name: name, item: item) != nil { dismiss() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !playlists.isWritable)
                    .accessibilityIdentifier("createPlaylist")
                }
                if let error = playlists.lastError { Text(error).font(.footnote).foregroundColor(.red) }
            }
            .navigationTitle(item == nil ? "New playlist" : "Add to playlist").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Cancel") { dismiss() } }
        }
    }
}

private struct LocalPlaylistView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var playlists: PlaylistStore
    @EnvironmentObject private var queue: PlaybackQueue
    let id: UUID
    let onPlay: (BrowseItem) -> Void
    @State private var renaming = false
    @State private var deleting = false
    private var playlist: LocalPlaylist? { playlists.playlists.first { $0.id == id } }
    var body: some View {
        Group {
            if let playlist {
                List {
                    HStack {
                        Button { play(playlist, at: 0) } label: { Label("Play all", systemImage: "play.fill") }
                        Spacer()
                        Button { for entry in playlist.entries { queue.enqueue(entry.item) } } label: { Label("Enqueue", systemImage: "text.badge.plus") }
                    }.disabled(playlist.entries.isEmpty)
                    if playlist.entries.isEmpty { Text("Add videos from a result menu or the video detail screen.").font(.footnote).foregroundStyle(.secondary) }
                    ForEach(Array(playlist.entries.enumerated()), id: \.element.id) { index, entry in
                        Button { play(playlist, at: index) } label: { BrowseRow(item: entry.item) }.buttonStyle(.plain)
                            .contextMenu { BrowseItemMenu(item: entry.item, onPlay: onPlay) }
                    }
                    .onDelete { indices in for index in indices { playlists.removeVideo(playlist.entries[index].id, from: id) } }
                    .onMove { indices, destination in playlists.move(in: id, from: indices, to: destination) }
                    .deleteDisabled(!playlists.isWritable).moveDisabled(!playlists.isWritable)
                }.listStyle(.plain)
            } else { EmptyStateView("Playlist unavailable", systemImage: "music.note.list", message: "This playlist is no longer in your library.") }
        }
        .navigationTitle(playlist?.name ?? "Playlist").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            EditButton().disabled(!playlists.isWritable)
            Menu {
                Button("Rename") { renaming = true }
                Button("Delete playlist", role: .destructive) { deleting = true }
            } label: { Image(systemName: "ellipsis") }.disabled(!playlists.isWritable)
        }
        .confirmationDialog("Delete this playlist?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete playlist", role: .destructive) { playlists.remove(id); dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Saved videos and other playlists will stay in your library.") }
        .sheet(isPresented: $renaming) {
            if let playlist { RenamePlaylistView(id: id, originalName: playlist.name) }
        }
    }
    private func play(_ playlist: LocalPlaylist, at index: Int) {
        queue.start(playlist.entries.map(\.item), at: index)
        NotificationCenter.default.post(name: .driftLoomExpandPlayer, object: nil)
    }
}

private struct RenamePlaylistView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var playlists: PlaylistStore
    let id: UUID
    @State private var name: String
    init(id: UUID, originalName: String) { self.id = id; _name = State(initialValue: originalName) }
    var body: some View {
        AppNavigation {
            Form {
                TextField("Playlist name", text: $name)
                Button("Save") { playlists.rename(id, name: name); if playlists.lastError == nil { dismiss() } }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let error = playlists.lastError { Text(error).font(.footnote).foregroundColor(.red) }
            }
            .navigationTitle("Rename playlist").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Cancel") { dismiss() } }
        }
    }
}
