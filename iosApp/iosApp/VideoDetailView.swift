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
    @StateObject private var discussion = DiscussionStore()
    @State private var tab = DetailTab.related
    @State private var sharing = false
    @State private var downloading = false
    @State private var choosingFormat = false
    private enum DetailTab: String, CaseIterable { case related = "Related", comments = "Comments", description = "Description", queue = "Queue" }

    var body: some View {
        AppNavigation {
            VStack(spacing: 0) {
                HStack {
                    Button(action: onCollapse) { Image(systemName: "chevron.down").frame(width: 44, height: 44) }
                        .accessibilityLabel("Minimize player").accessibilityIdentifier("minimizePlayer")
                    Spacer()
                    Text("YouTube").font(.headline)
                    Spacer()
                    playbackOptions
                }.padding(.horizontal, 6).background(Color(.systemBackground))
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
                        if let details = discussion.details {
                            Text([details.views, details.date].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
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
                    case .comments:
                        CommentsPanel(store: discussion)
                    case .description:
                        Text(discussion.details?.description.isEmpty == false ? discussion.details!.description : playback.video?.description.isEmpty == false ? playback.video!.description : "No description is available.")
                            .font(.subheadline).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding()
                    case .queue:
                        QueuePanel()
                    }
                }
            }
            .navigationBarHidden(true)

        }
        .id(playback.videoID)
        .sheet(isPresented: $sharing) {
            if let id = playback.videoID, let url = URL(string: "https://www.youtube.com/watch?v=\(id)") { ShareSheet(items: [url]) }
        }
        .sheet(isPresented: $choosingFormat) { PlaybackFormatPicker(playback: playback) }
        .sheet(isPresented: $downloading) {
            if let item = playback.currentItemMetadata { DownloadPicker(item: item) }
        }
        .task(id: playback.videoID) { if let id = playback.videoID { await related.load(.related(id)) } }
        .task(id: playback.videoID) { if let id = playback.videoID { await discussion.load(videoID: id) } }
    }

    private var playbackOptions: some View {
                    Menu {
                        if playback.currentItemMetadata != nil {
                            IconButton("Download", systemImage: "arrow.down.circle") { downloading = true }
                        }
                        if playback.video?.streamURL.isFileURL != true {
                            IconButton("Playback format", systemImage: "film") { choosingFormat = true }
                        }
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
                    } label: { Image(systemName: "ellipsis").rotationEffect(.degrees(90)).frame(width: 44, height: 44) }.accessibilityLabel("Playback options")
    }

    @ViewBuilder private var playbackStatus: some View {
        if playback.video?.streamURL.isFileURL == true {
            Label("Offline playback", systemImage: "arrow.down.circle.fill").font(.caption).foregroundStyle(.secondary)
        }
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
        // Minimizing the app player must not start a new system presentation on iOS 15.
        controller.canStartPictureInPictureAutomaticallyFromInline = false
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.view.clipsToBounds = true
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) { controller.player = player }
    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
        // The session retains AVPlayer for the mini-player and background audio.
        // Release AVKit's presentation ownership when SwiftUI removes the video surface.
        controller.player = nil
        if controller.presentedViewController != nil { controller.dismiss(animated: false) }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct CommentsPanel: View {
    @ObservedObject var store: DiscussionStore
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            if let error = store.error {
                Text(error).font(.footnote).foregroundStyle(.secondary)
                Button("Try comments again") { Task { await store.loadMore() } }
            }
            if store.loading { ProgressView("Loading comments…") }
            if store.details != nil, !store.loading, !store.canLoadMore, store.comments.isEmpty {
                Text("Comments are unavailable for this video.").foregroundStyle(.secondary)
            }
            ForEach(store.comments) { comment in
                VStack(alignment: .leading, spacing: 8) {
                    commentBody(comment)
                    if store.hasMoreReplies(comment) {
                        Button(store.loadingReplies.contains(comment.id) ? "Loading replies…" : "View replies") {
                            Task { await store.loadReplies(comment) }
                        }.disabled(store.loadingReplies.contains(comment.id))
                    }
                    ForEach(store.replies[comment.id] ?? []) { reply in
                        commentBody(reply).padding(.leading, 24)
                    }
                }
                Divider()
            }
            if store.canLoadMore, !store.loading {
                Button(store.hasLoadedComments ? "More comments" : "Load comments") { Task { await store.loadMore() } }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding()
        .task(id: store.details?.comments?.token) {
            if !store.hasLoadedComments { await store.loadMore() }
        }
    }
    private func commentBody(_ comment: VideoComment) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(comment.author).font(.subheadline.weight(.semibold))
            Text([comment.published, comment.likes.isEmpty ? "" : "\(comment.likes) likes"].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
            Text(comment.text).font(.subheadline).textSelection(.enabled).accessibilityIdentifier("commentText")
        }
    }
}
