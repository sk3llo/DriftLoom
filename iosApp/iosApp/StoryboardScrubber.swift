// SPDX-License-Identifier: GPL-3.0-or-later
import AVFoundation
import DriftLoomPlayback
import SwiftUI
import UIKit

/// Playback position for the seek bar, kept apart from PlaybackSession so ticks don't redraw the whole page.
@MainActor
final class PlaybackClock: ObservableObject {
    @Published private(set) var time: Double = 0
    @Published private(set) var duration: Double = 0
    /// Live streams have no end, so no total time.
    @Published private(set) var isLive = false
    private weak var player: AVPlayer?
    private var observer: Any?
    init(player: AVPlayer) {
        self.player = player
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 2), queue: .main) { [weak self, weak player] time in
            Task { @MainActor [weak self, weak player] in
                guard let self else { return }
                self.time = time.seconds.isFinite ? time.seconds : 0
                let length = player?.currentItem?.duration
                let duration = length?.seconds ?? 0
                self.duration = duration.isFinite ? duration : 0
                self.isLive = length?.isIndefinite == true && player?.currentItem?.status == .readyToPlay
            }
        }
    }
    deinit { if let observer { player?.removeTimeObserver(observer) } }
}

/// Downloads storyboard sheets once and cuts single frames out of them.
@MainActor
final class StoryboardImages {
    static let shared = StoryboardImages()
    private let cache = NSCache<NSURL, UIImage>()
    private var loading: [URL: Task<UIImage?, Never>] = [:]
    init() { cache.countLimit = 40 }
    func frame(_ frame: Storyboard.Frame) async -> UIImage? {
        guard let sheet = await sheet(frame.sheet)?.cgImage else { return nil }
        let rect = CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
        guard rect.maxX <= CGFloat(sheet.width), rect.maxY <= CGFloat(sheet.height), let cell = sheet.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cell)
    }
    private func sheet(_ url: URL) async -> UIImage? {
        if let image = cache.object(forKey: url as NSURL) { return image }
        if let task = loading[url] { return await task.value }
        let task = Task<UIImage?, Never> {
            guard let (data, response) = try? await URLSession.shared.data(from: url), (response as? HTTPURLResponse)?.statusCode == 200,
                  data.count < 2_000_000 else { return nil }
            return UIImage(data: data)
        }
        loading[url] = task
        let image = await task.value
        loading[url] = nil
        if let image { cache.setObject(image, forKey: url as NSURL) }
        return image
    }
}

/// A seek bar with YouTube's preview frames above the finger while dragging.
struct StoryboardScrubber: View {
    @ObservedObject var playback: PlaybackSession
    /// Preview frames when YouTube provides them; without, the bubble shows only the time.
    let storyboard: Storyboard?
    /// Tells the player controls to stay up while the finger is on the bar.
    var onScrubbing: (Bool) -> Void = { _ in }
    @StateObject private var clock: PlaybackClock
    @State private var dragFraction: Double?
    @State private var preview: UIImage?
    @State private var previewTask: Task<Void, Never>?

    init(playback: PlaybackSession, storyboard: Storyboard?, onScrubbing: @escaping (Bool) -> Void = { _ in }) {
        self.playback = playback; self.storyboard = storyboard; self.onScrubbing = onScrubbing
        _clock = StateObject(wrappedValue: PlaybackClock(player: playback.player))
    }

    var body: some View {
        // Drawn over the bottom of the video, as in NewPipe: elapsed time, the bar, then the length,
        // with the chapter's name just above.
        VStack(alignment: .leading, spacing: 0) {
            if let chapter = currentChapter {
                Text(chapter.title).font(.caption.weight(.semibold)).foregroundColor(.white).lineLimit(1)
                    .shadow(color: .black.opacity(0.6), radius: 2).accessibilityIdentifier("currentChapter")
            }
            HStack(spacing: 10) {
                Text(format(dragFraction.map { $0 * clock.duration } ?? clock.time))
                    .accessibilityIdentifier("elapsedTime")
                bar
                if clock.isLive {
                    Text("Live").foregroundColor(AppStyle.accent).accessibilityIdentifier("totalTime")
                } else if clock.duration > 0 {
                    Text(format(clock.duration)).accessibilityIdentifier("totalTime")
                }
            }
            .font(.caption.monospacedDigit().weight(.semibold)).foregroundColor(.white)
            .shadow(color: .black.opacity(0.6), radius: 2)
        }
        .onChange(of: dragFraction != nil) { onScrubbing($0) }
    }
    private var chapters: [VideoChapter] { playback.chapters }
    private var currentChapter: VideoChapter? {
        let time = dragFraction.map { $0 * clock.duration } ?? clock.time
        return VideoChapters.index(at: time, in: chapters).map { chapters[$0] }
    }

    private var bar: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fraction = dragFraction ?? (clock.duration > 0 ? clock.time / clock.duration : 0)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.35)).frame(height: 4)
                Capsule().fill(AppStyle.accent).frame(width: max(0, width * fraction), height: 4)
                // Chapter boundaries cut small gaps into the bar, as on YouTube.
                if clock.duration > 0 {
                    ForEach(chapters.dropFirst(), id: \.start) { chapter in
                        Rectangle().fill(Color.black.opacity(0.7)).frame(width: 2, height: 6)
                            .offset(x: width * min(1, chapter.start / clock.duration) - 1)
                    }
                    .accessibilityHidden(true)
                }
                Circle().fill(AppStyle.accent).frame(width: dragFraction == nil ? 12 : 18, height: dragFraction == nil ? 12 : 18)
                    .offset(x: max(0, min(width, width * fraction)) - (dragFraction == nil ? 6 : 9))
            }
            .frame(height: 28).contentShape(Rectangle())
            // The bar alone is the accessible control; the preview bubble stays a separate element.
            .accessibilityElement()
            .accessibilityLabel("Seek")
            .accessibilityValue(currentChapter.map { Text("\(format(clock.time)) of \(format(clock.duration)), \($0.title)") }
                ?? Text("\(format(clock.time)) of \(format(clock.duration))"))
            .accessibilityAdjustableAction { direction in
                let step = direction == .increment ? 10.0 : -10.0
                Task { await playback.player.seek(to: CMTime(seconds: max(0, clock.time + step), preferredTimescale: 600)) }
            }
            .accessibilityIdentifier("seekBar")
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in update(max(0, min(1, value.location.x / max(1, width)))) }
                .onEnded { _ in finish() })
            .overlay(alignment: .bottomLeading) {
                if let dragFraction { previewBubble(fraction: dragFraction, width: width) }
            }
        }
        .frame(height: 28)
#if DEBUG || DRIFTLOOM_DEVICE_TESTING
        .task(id: clock.duration > 0) {
            // --seek-preview-smoke 0.3: hold a drag at that position so the preview can be inspected.
            let arguments = ProcessInfo.processInfo.arguments
            if clock.duration > 0, let flag = arguments.firstIndex(of: "--seek-preview-smoke"), arguments.indices.contains(flag + 1),
               let fraction = Double(arguments[flag + 1]) { update(max(0, min(1, fraction))) }
        }
#endif
    }

    private func previewBubble(fraction: Double, width: CGFloat) -> some View {
        let bubble: CGFloat = 160
        let x = min(max(0, width * fraction - bubble / 2), max(0, width - bubble))
        return VStack(spacing: 4) {
            if storyboard != nil {
                ZStack {
                    Color.black
                    if let preview { Image(uiImage: preview).resizable().scaledToFill().accessibilityIdentifier("seekPreviewImage") }
                }
                .frame(width: bubble, height: bubble * 9 / 16).clipped().cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.8), lineWidth: 1))
            }
            if let chapter = VideoChapters.index(at: fraction * clock.duration, in: chapters).map({ chapters[$0] }) {
                Text(chapter.title).font(.caption.weight(.semibold)).lineLimit(1).frame(maxWidth: bubble)
                    .padding(.horizontal, 6).padding(.vertical, 2).background(Color.black.opacity(0.75)).foregroundColor(.white).cornerRadius(4)
                    .accessibilityIdentifier("seekPreviewChapter")
            }
            Text(format(fraction * clock.duration)).font(.caption.monospacedDigit().weight(.semibold))
                .padding(.horizontal, 6).padding(.vertical, 2).background(Color.black.opacity(0.75)).foregroundColor(.white).cornerRadius(4)
        }
        .offset(x: x, y: (storyboard == nil ? 0 : -34)).allowsHitTesting(false)
    }

    private func update(_ fraction: Double) {
        dragFraction = fraction
        guard let frame = storyboard?.frame(at: fraction * clock.duration, duration: clock.duration) else { return }
        previewTask?.cancel()
        previewTask = Task {
            let image = await StoryboardImages.shared.frame(frame)
            if !Task.isCancelled, let image { preview = image }
        }
    }
    private func finish() {
        guard let fraction = dragFraction else { return }
        let target = CMTime(seconds: fraction * clock.duration, preferredTimescale: 600)
        Task { await playback.player.seek(to: target); dragFraction = nil }
    }
    private func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let value = Int(seconds)
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, (value % 3600) / 60, value % 60) : String(format: "%d:%02d", value / 60, value % 60)
    }
}
