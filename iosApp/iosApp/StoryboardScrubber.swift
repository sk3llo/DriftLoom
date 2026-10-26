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
    private weak var player: AVPlayer?
    private var observer: Any?
    init(player: AVPlayer) {
        self.player = player
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 2), queue: .main) { [weak self] time in
            Task { @MainActor [weak self, weak player] in
                guard let self else { return }
                self.time = time.seconds.isFinite ? time.seconds : 0
                let duration = player?.currentItem?.duration.seconds ?? 0
                self.duration = duration.isFinite ? duration : 0
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
    @StateObject private var clock: PlaybackClock
    @State private var dragFraction: Double?
    @State private var preview: UIImage?
    @State private var previewTask: Task<Void, Never>?

    init(playback: PlaybackSession, storyboard: Storyboard?) {
        self.playback = playback; self.storyboard = storyboard
        _clock = StateObject(wrappedValue: PlaybackClock(player: playback.player))
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fraction = dragFraction ?? (clock.duration > 0 ? clock.time / clock.duration : 0)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.3)).frame(height: 4)
                Capsule().fill(AppStyle.accent).frame(width: max(0, width * fraction), height: 4)
                Circle().fill(AppStyle.accent).frame(width: dragFraction == nil ? 12 : 18, height: dragFraction == nil ? 12 : 18)
                    .offset(x: max(0, min(width, width * fraction)) - (dragFraction == nil ? 6 : 9))
            }
            .frame(height: 28).contentShape(Rectangle())
            // The bar alone is the accessible control; the preview bubble stays a separate element.
            .accessibilityElement()
            .accessibilityLabel("Seek")
            .accessibilityValue("\(format(clock.time)) of \(format(clock.duration))")
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
        .frame(height: 28).padding(.horizontal, 12)
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
            Text(format(fraction * clock.duration)).font(.caption.monospacedDigit().weight(.semibold))
                .padding(.horizontal, 6).padding(.vertical, 2).background(Color.black.opacity(0.75)).foregroundColor(.white).cornerRadius(4)
        }
        .offset(x: x, y: storyboard == nil ? 0 : -34).allowsHitTesting(false)
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
