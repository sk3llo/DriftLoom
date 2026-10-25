// SPDX-License-Identifier: GPL-3.0-or-later
import AVKit
import DriftLoomPlayback
import SwiftUI

struct VideoDetailView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var queue: PlaybackQueue
    @ObservedObject var playback: PlaybackSession
    let onCollapse: () -> Void
    let onPlay: (BrowseItem) -> Void
    @StateObject private var related = BrowseStore()
    @State private var tab = DetailTab.related
    @State private var sharing = false
    private enum DetailTab: String, CaseIterable { case related = "Related", description = "Description", queue = "Queue" }

    var body: some View {
        AppNavigation {
            VStack(spacing: 0) {
                Group {
                    if playback.player.currentItem != nil {
                        NativeVideoPlayer(player: playback.player)
                            .aspectRatio(16 / 9, contentMode: .fit).background(Color.black)
                            .accessibilityIdentifier("videoPlayer")
                    } else {
                        ZStack {
                            Color.black
                            if case .failed = playback.phase { Image(systemName: "exclamationmark.triangle").foregroundColor(.white) }
                            else { ProgressView().tint(.white) }
                        }.aspectRatio(16 / 9, contentMode: .fit)
                    }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(playback.title).font(.headline).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        playbackStatus
                        if let item = playback.currentItemMetadata {
                            HStack {
                                if let id = item.channelID {
                                    BrowseLink(route: .channel(id), onPlay: onPlay) {
                                        Label(item.subtitle.isEmpty ? "Channel" : item.subtitle, systemImage: "person.crop.circle")
                                            .font(.subheadline).foregroundStyle(.primary).lineLimit(1)
                                    }
                                    Spacer()
                                    Button(library.isSubscribed(id) ? "SUBSCRIBED" : "SUBSCRIBE") {
                                        library.toggleSubscription(BrowseItem(contentID: id, kind: .channel,
                                                                              title: item.subtitle.isEmpty ? "Channel" : item.subtitle))
                                    }.font(.caption.weight(.semibold)).disabled(!library.isWritable)
                                } else { Text("YouTube").font(.caption).foregroundStyle(.secondary) }
                            }
                            HStack(spacing: 0) {
                                detailAction(library.isSaved(item.contentID) ? "Saved" : "Save",
                                             symbol: library.isSaved(item.contentID) ? "bookmark.fill" : "bookmark") { library.toggleSaved(item) }
                                    .disabled(!library.isWritable)
                                detailAction("Share", symbol: "square.and.arrow.up") { sharing = true }
                                detailAction("Queue", symbol: "list.bullet") { tab = .queue }
                                detailAction("Playlist", symbol: "plus.rectangle.on.rectangle") {
                                    NotificationCenter.default.post(name: .driftLoomAddToPlaylist, object: item)
                                }
                                Menu {
                                    ForEach([Float(0.25), 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2], id: \.self) { rate in
                                        Button("\(String(format: "%g", rate))×\(playback.playbackRate == rate ? " ✓" : "")") { playback.setPlaybackRate(rate) }
                                    }
                                } label: { actionLabel("\(String(format: "%g", playback.playbackRate))×", symbol: "speedometer") }
                                .accessibilityLabel("Playback speed")
                            }
                        }
                    }.padding(12)
                    SectionStrip(values: DetailTab.allCases, selection: $tab, title: { $0.rawValue })
                    switch tab {
                    case .related:
                        LazyVStack(spacing: 14) {
                            if related.isLoading { ProgressView("Loading related videos…").padding() }
                            if let error = related.error {
                                Text(error).font(.footnote).foregroundStyle(.secondary)
                                Button("Try again") { Task { if let id = playback.videoID { await related.load(.related(id)) } } }
                            }
                            ForEach(related.items) { item in BrowseResultRow(item: item, onPlay: onPlay) }
                            if let error = related.paginationError { Text(error).font(.footnote).foregroundStyle(.secondary) }
                            if related.canLoadMore {
                                Button(related.isLoadingMore ? "Loading…" : "Load more") { Task { await related.loadMore() } }.disabled(related.isLoadingMore)
                            }
                        }.padding(12)
                    case .description:
                        Text(playback.video?.description.isEmpty == false ? playback.video!.description : "No description is available.")
                            .font(.subheadline).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding()
                    case .queue:
                        QueuePanel()
                    }
                }
            }
            .navigationTitle("YouTube").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: onCollapse) { Image(systemName: "chevron.down") }.accessibilityLabel("Minimize player").accessibilityIdentifier("minimizePlayer")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Menu("Maximum video resolution") {
                            ForEach([0, 360, 480, 720, 1080], id: \.self) { height in
                                Button((height == 0 ? "Auto" : "Up to \(height)p") + (playback.maximumHeight == height ? " ✓" : "")) {
                                    playback.setMaximumHeight(height)
                                }
                            }
                        }
                        if let group = playback.player.currentItem?.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) {
                            Menu("Captions") {
                                Button("Off") { playback.player.currentItem?.select(nil, in: group) }
                                ForEach(group.options, id: \.displayName) { option in
                                    Button(option.displayName) { playback.player.currentItem?.select(option, in: group) }
                                }
                            }
                        }
                        IconButton("Stop playback", systemImage: "stop") { queue.stop(); onCollapse() }
                    } label: { Image(systemName: "ellipsis").rotationEffect(.degrees(90)) }.accessibilityLabel("Playback options")
                }
            }
        }
        .id(playback.videoID)
        .sheet(isPresented: $sharing) {
            if let id = playback.videoID, let url = URL(string: "https://www.youtube.com/watch?v=\(id)") { ShareSheet(items: [url]) }
        }
        .task(id: playback.videoID) { if let id = playback.videoID { await related.load(.related(id)) } }
    }

    @ViewBuilder private var playbackStatus: some View {
        if case let .failed(message) = playback.phase {
            Text(message).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("playbackError")
            Button("Try again", action: playback.retry)
        } else if playback.phase == .resolving || playback.phase == .loading {
            ProgressView(playback.phase == .resolving ? "Opening video…" : "Buffering…").font(.caption)
        }
        if playback.didRecover {
            Label("Stream refreshed", systemImage: "arrow.clockwise").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func detailAction(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { actionLabel(title, symbol: symbol) }.buttonStyle(.plain)
    }
    private func actionLabel(_ title: String, symbol: String) -> some View {
        VStack(spacing: 6) { Image(systemName: symbol).font(.title3); Text(title).font(.caption) }
            .frame(maxWidth: .infinity, minHeight: 54).foregroundColor(AppStyle.accent)
    }
}

private struct QueuePanel: View {
    @EnvironmentObject private var queue: PlaybackQueue
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                Button(action: queue.previous) { Image(systemName: "backward.end.fill").frame(width: 44, height: 44) }
                    .disabled(!queue.canGoPrevious).accessibilityLabel("Previous")
                Button(action: queue.next) { Image(systemName: "forward.end.fill").frame(width: 44, height: 44) }
                    .disabled(!queue.canGoNext).accessibilityLabel("Next")
                Button { queue.shuffled.toggle() } label: {
                    Image(systemName: "shuffle").foregroundColor(queue.shuffled ? AppStyle.accent : .secondary).frame(width: 44, height: 44)
                }.accessibilityLabel("Shuffle \(queue.shuffled ? "on" : "off")")
                Menu {
                    ForEach(QueueRepeat.allCases, id: \.self) { mode in Button(mode.rawValue) { queue.repeatMode = mode } }
                } label: {
                    Image(systemName: queue.repeatMode == .one ? "repeat.1" : "repeat")
                        .foregroundColor(queue.repeatMode == .off ? .secondary : AppStyle.accent).frame(width: 44, height: 44)
                }.accessibilityLabel("Repeat \(queue.repeatMode.rawValue)")
            }
            // An embedded list supplies native accessible drag handles without nesting scroll views.
            List {
                ForEach(queue.entries) { entry in
                    Button { queue.select(entry.id) } label: {
                        HStack {
                            Image(systemName: queue.currentID == entry.id ? "play.fill" : "music.note")
                                .foregroundColor(queue.currentID == entry.id ? AppStyle.accent : .secondary)
                            Text(entry.item.title).font(.subheadline).foregroundStyle(.primary).lineLimit(2)
                        }.padding(.vertical, 4)
                    }
                    .swipeActions { Button("Remove", role: .destructive) { queue.remove(entry.id) } }
                }
                .onMove(perform: queue.move)
            }
            .listStyle(.plain).environment(\.editMode, .constant(.active))
            .frame(height: max(150, min(600, CGFloat(queue.entries.count) * 72)))
        }
    }
}

private struct NativeVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) { controller.player = player }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
