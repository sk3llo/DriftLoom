// SPDX-License-Identifier: GPL-3.0-or-later
import AVKit
import DriftLoomPlayback
import SwiftUI

struct VideoDetailView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var queue: PlaybackQueue
    @EnvironmentObject private var preferences: AppPreferences
    @ObservedObject var playback: PlaybackSession
    let onCollapse: () -> Void
    let onPlay: (BrowseItem) -> Void
    @StateObject private var related = BrowseStore()
    @StateObject private var discussion = DiscussionStore()
    @State private var tab = DetailTab.related
    @State private var sharing = false
    @State private var downloading = false
    @State private var choosingFormat = false
    @StateObject private var inline = InlinePlayerController()
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// How far the page follows a downward drag on the header or video before minimizing, as in NewPipe.
    @State private var dragOffset: CGFloat = 0
    /// The video's frame on screen; its side thirds belong to the brightness and volume swipes.
    @State private var playerFrame: CGRect = .zero
    private enum DetailTab: CaseIterable {
        case related, comments, description, queue
        var title: String {
            switch self {
            case .related: return String(localized: "Related")
            case .comments: return String(localized: "Comments")
            case .description: return String(localized: "Description")
            case .queue: return String(localized: "Queue")
            }
        }
    }

    var body: some View {
        AppNavigation {
            GeometryReader { proxy in
                // iPad in landscape: the player and its details beside the related list, as on YouTube.
                if sizeClass == .regular && proxy.size.width > proxy.size.height && proxy.size.width >= 900 {
                    VStack(spacing: 0) {
                        header
                        HStack(alignment: .top, spacing: 0) {
                            VStack(spacing: 0) {
                                // The player takes its full 16:9 height before the details scroll below it.
                                playerArea.layoutPriority(1)
                                ScrollView { info }
                            }
                            .frame(width: proxy.size.width * 0.62)
                            Divider()
                            VStack(spacing: 0) {
                                SectionStrip(values: DetailTab.allCases, selection: $tab, title: { $0.title })
                                ScrollView { tabContent }
                            }
                        }
                    }
                    .accessibilityElement(children: .contain).accessibilityIdentifier("sideBySideDetail")
                } else {
                    VStack(spacing: 0) {
                        header
                        playerArea
                        ScrollView {
                            info
                            SectionStrip(values: DetailTab.allCases, selection: $tab, title: { $0.title })
                            tabContent
                        }
                    }
                }
            }
            .navigationBarHidden(true)

        }
        .offset(y: dragOffset)
        .id(playback.videoID)
        .sheet(isPresented: $sharing) {
            if let url = playback.currentItemMetadata?.shareURL { ShareSheet(items: [url]) }
        }
        .sheet(isPresented: $choosingFormat) { PlaybackFormatPicker(playback: playback) }
        .sheet(isPresented: $downloading) {
            if let item = playback.currentItemMetadata { DownloadPicker(item: item).environmentObject(preferences) }
        }
        .task(id: playback.videoID) { if let id = playback.videoID { await related.load(.related(id)) } }
        .task(id: playback.videoID) { if let id = playback.videoID { await discussion.load(videoID: id) } }
#if DEBUG || DRIFTLOOM_DEVICE_TESTING
        .onAppear {
            // --detail-tab comments: open a tab directly for device screenshots.
            let arguments = ProcessInfo.processInfo.arguments
            if let flag = arguments.firstIndex(of: "--detail-tab"), arguments.indices.contains(flag + 1) {
                tab = DetailTab.allCases.first { "\($0)" == arguments[flag + 1] } ?? tab
            }
        }
#endif
        .onReceive(discussion.$details) { details in
            if let details, let id = playback.videoID { playback.useChapters(fromDescription: details.description, videoID: id) }
        }
    }

    private var overlay: SubtitleOverlay {
        SubtitleOverlay(playback: playback, size: preferences.subtitleSize,
                        artwork: playback.currentItemMetadata.flatMap { $0.isSoundCloud || playback.audioOnly ? $0.thumbnail : nil })
    }

    private var playbackOptions: some View {
                    Menu {
                        if playback.video?.streamURL.isFileURL != true, playback.currentItemMetadata?.isSoundCloud != true {
                            IconButton("Playback format", systemImage: "film") { choosingFormat = true }
                        }
                        if playback.currentItemMetadata?.isSoundCloud != true {
                        Menu("Quality") {
                            ForEach([0, 360, 480, 720, 1080], id: \.self) { height in
                                Button((height == 0 ? String(localized: "Auto") : String(localized: "Up to \(String(height))p")) + (playback.maximumHeight == height ? " ✓" : "")) {
                                    playback.setMaximumHeight(height)
                                }
                            }
                        }
                        }
                        if !playback.subtitleTracks.isEmpty {
                            Menu("Subtitles") {
                                Button(String(localized: "Off") + (playback.selectedSubtitle == nil ? " ✓" : "")) { playback.selectSubtitle(nil) }
                                ForEach(playback.subtitleTracks) { track in
                                    Button((track.isAutoGenerated && !track.name.localizedCaseInsensitiveContains("auto") ? String(localized: "\(track.name) (auto-generated)") : track.name)
                                           + (playback.selectedSubtitle == track ? " ✓" : "")) { playback.selectSubtitle(track) }
                                }
                                if !playback.subtitleTranslations.isEmpty {
                                    Menu("Auto-translate") {
                                        ForEach(playback.subtitleTranslations) { language in
                                            Button(language.name + (playback.selectedSubtitle?.translationCode == language.code ? " ✓" : "")) {
                                                playback.selectTranslation(language)
                                            }
                                        }
                                    }
                                }
                            }
                        } else if let group = playback.player.currentItem?.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) {
                            Menu("Captions") {
                                Button("Off") { playback.player.currentItem?.select(nil, in: group) }
                                ForEach(group.options, id: \.displayName) { option in
                                    Button(option.displayName) { playback.player.currentItem?.select(option, in: group) }
                                }
                            }
                        }
                        IconButton("Stop playback", systemImage: "stop") { queue.stop(); onCollapse() }
                    } label: { Image(systemName: "ellipsis").rotationEffect(.degrees(90)).frame(width: 44, height: 44) }.accessibilityLabel("Playback options").accessibilityIdentifier("playbackOptions")
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
        if let error = playback.subtitleError {
            Label(error, systemImage: "captions.bubble").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("subtitleError")
        }
        if playback.didRecover {
            Label("Stream refreshed", systemImage: "arrow.clockwise").font(.caption).foregroundStyle(.secondary)
        }
    }
    /// Drag the video or the header down to shrink the player into the mini-player bar.
    private var minimizeDrag: some Gesture { minimizeDrag(fromVideo: false) }
    private func minimizeDrag(fromVideo: Bool) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in
                if fromVideo, dragOffset == 0, playerFrame.width > 0 {
                    let third = playerFrame.width / 3
                    guard value.startLocation.x > playerFrame.minX + third, value.startLocation.x < playerFrame.maxX - third else { return }
                }
                // Only a mostly downward drag moves the page; sideways drags stay with the controls.
                guard value.translation.height > 0, value.translation.height > abs(value.translation.width) || dragOffset > 0 else { return }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                let height = UIScreen.main.bounds.height
                if dragOffset > 0, value.translation.height > height * 0.2 || value.predictedEndTranslation.height > height * 0.45 {
                    withAnimation(.easeOut(duration: 0.2)) { dragOffset = height }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onCollapse() }
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { dragOffset = 0 }
                }
            }
    }
    private var header: some View {
        HStack {
            Button(action: onCollapse) { Image(systemName: "chevron.down").frame(width: 44, height: 44) }
                .accessibilityLabel("Minimize player").accessibilityIdentifier("minimizePlayer")
            Spacer()
            Text(playback.currentItemMetadata?.isSoundCloud == true ? "SoundCloud" : "YouTube").font(.headline)
            Spacer()
            playbackOptions
        }.padding(.horizontal, 6).background(Color(.systemBackground))
        .contentShape(Rectangle()).gesture(minimizeDrag)
    }
    @ViewBuilder private var playerArea: some View {
        Group {
            if playback.player.currentItem != nil {
                ZStack {
                    InlinePlayerSurface(player: playback.player, overlay: overlay, controller: inline, gravity: preferences.videoResize.gravity)
                    InlinePlayerControls(playback: playback, controller: inline, overlay: overlay)
                }
                .aspectRatio(16 / 9, contentMode: .fit).background(Color.black)
                .simultaneousGesture(minimizeDrag(fromVideo: true))
                .background(GeometryReader { proxy in
                    Color.clear.onAppear { playerFrame = proxy.frame(in: .global) }.onChange(of: proxy.frame(in: .global)) { playerFrame = $0 }
                })
                .accessibilityElement(children: .contain).accessibilityIdentifier("videoPlayer")
            } else {
                ZStack {
                    Color.black
                    if case .failed = playback.phase { Image(systemName: "exclamationmark.triangle").foregroundColor(.white) }
                    else { ProgressView().tint(.white) }
                }.aspectRatio(16 / 9, contentMode: .fit)
                .contentShape(Rectangle()).gesture(minimizeDrag)
            }
        }
        if playback.player.currentItem != nil {
            StoryboardScrubber(playback: playback, storyboard: playback.storyboard).id(playback.videoID).padding(.top, 8)
        }
    }
    private var info: some View {
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
                            Label(item.subtitle.isEmpty ? String(localized: "Channel") : item.subtitle, systemImage: "person.crop.circle")
                                .font(.subheadline).foregroundStyle(.primary).lineLimit(1)
                        }
                        Spacer()
                        Button(library.isSubscribed(id) ? "SUBSCRIBED" : "SUBSCRIBE") {
                            library.toggleSubscription(BrowseItem(contentID: id, kind: .channel,
                                                                  title: item.subtitle.isEmpty ? String(localized: "Channel") : item.subtitle))
                        }.font(.caption.weight(.semibold)).disabled(!library.isWritable)
                    } else { Text(item.isSoundCloud ? "SoundCloud" : "YouTube").font(.caption).foregroundStyle(.secondary) }
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
                    detailAction("Download", symbol: "arrow.down.circle") { downloading = true }.accessibilityIdentifier("detailDownload")
                }
            }
        }.padding(12)
    }
    @ViewBuilder private var tabContent: some View {
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
            if !playback.chapters.isEmpty { chapterList }
            Text(discussion.details?.description.isEmpty == false ? discussion.details!.description : playback.video?.description.isEmpty == false ? playback.video!.description : String(localized: "No description is available."))
                .font(.subheadline).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding()
        case .queue:
            QueuePanel()
        }
    }
    private var chapterList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Chapters").font(.headline).padding(.bottom, 6)
            ForEach(Array(playback.chapters.enumerated()), id: \.offset) { index, chapter in
                Button {
                    Task { await playback.player.seek(to: CMTime(seconds: chapter.start, preferredTimescale: 600)) }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(chapter.timestamp).font(.subheadline.monospacedDigit()).foregroundColor(AppStyle.accent)
                        Text(chapter.title).font(.subheadline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }.padding(.vertical, 8).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("chapter-\(index)")
            }
        }.padding([.horizontal, .top])
    }
    private func detailAction(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { actionLabel(title, symbol: symbol) }.buttonStyle(.plain)
    }
    private func actionLabel(_ title: LocalizedStringKey, symbol: String) -> some View {
        VStack(spacing: 6) { Image(systemName: symbol).font(.title3); Text(title).font(.caption).lineLimit(1).minimumScaleFactor(0.75) }
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
                }.accessibilityLabel(queue.shuffled ? "Shuffle on" : "Shuffle off")
                Menu {
                    ForEach(QueueRepeat.allCases, id: \.self) { mode in Button(mode.title) { queue.repeatMode = mode } }
                } label: {
                    Image(systemName: queue.repeatMode == .one ? "repeat.1" : "repeat")
                        .foregroundColor(queue.repeatMode == .off ? .secondary : AppStyle.accent).frame(width: 44, height: 44)
                }.accessibilityLabel("Repeat: \(queue.repeatMode.title)")
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

/// Draws external subtitles. Hosted in the player's content overlay so fullscreen keeps them.
struct SubtitleOverlay: View {
    @ObservedObject var playback: PlaybackSession
    let size: SubtitleSize
    /// Cover art for audio-only items, drawn where the video would be.
    var artwork: URL? = nil
    var body: some View {
        GeometryReader { proxy in
            if let artwork {
                AsyncImage(url: artwork) { $0.resizable().scaledToFit() } placeholder: { Image(systemName: "music.note").font(.largeTitle).foregroundColor(.gray) }
                    .frame(width: proxy.size.width, height: proxy.size.height).accessibilityIdentifier("audioArtwork")
            }
            VStack {
                Spacer()
                if let text = playback.subtitleText {
                    Text(text)
                        .font(.system(size: max(12, proxy.size.height * 0.055) * size.scale, weight: .medium))
                        .foregroundColor(.white).multilineTextAlignment(.center)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.black.opacity(0.6)).cornerRadius(4)
                        .padding(.horizontal, 12).padding(.bottom, proxy.size.height * 0.06)
                        .accessibilityIdentifier("subtitleText")
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.allowsHitTesting(false)
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
            if !store.sortOptions.isEmpty {
                Menu {
                    ForEach(store.sortOptions, id: \.self) { option in
                        Button { Task { await store.setSort(option) } } label: {
                            if option == store.sort { Label(title(option), systemImage: "checkmark") } else { Text(title(option)) }
                        }
                    }
                } label: {
                    Label(title(store.sort), systemImage: "arrow.up.arrow.down").font(.subheadline.weight(.medium))
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Sort comments").accessibilityValue(title(store.sort)).accessibilityIdentifier("commentSort")
            }
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
    private func title(_ sort: CommentSort) -> LocalizedStringKey {
        sort == .top ? "Top comments" : "Newest first"
    }
    private func commentBody(_ comment: VideoComment) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(comment.author).font(.subheadline.weight(.semibold))
            Text([comment.published, comment.likes.isEmpty ? "" : String(localized: "\(comment.likes) likes")].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
            Text(comment.text).font(.subheadline).textSelection(.enabled).accessibilityIdentifier("commentText")
        }
    }
}
