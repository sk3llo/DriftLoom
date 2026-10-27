// SPDX-License-Identifier: GPL-3.0-or-later
import AVFoundation
import AVKit
import MediaPlayer
import DriftLoomPlayback
import SwiftUI
import UIKit

/// A view whose backing layer is an AVPlayerLayer.
final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

/// Picture in Picture and fullscreen for the inline player, which draws DriftLoom's own controls
/// instead of AVKit's (AVKit's seek bar can't show preview frames).
@MainActor
final class InlinePlayerController: NSObject, ObservableObject, AVPictureInPictureControllerDelegate {
    @Published private(set) var isPictureInPictureActive = false
    @Published private(set) var isPictureInPicturePossible = false
    private var pictureInPicture: AVPictureInPictureController?
    private var possibleObservation: NSKeyValueObservation?
    private weak var fullscreen: AVPlayerViewController?
    /// The resize mode, applied to the full-screen player too.
    var videoGravity: AVLayerVideoGravity = .resizeAspect
    /// Fullscreen opened by turning the phone sideways closes again when it's turned upright.
    private var openedByRotation = false

    func attach(_ layer: AVPlayerLayer) {
#if DEBUG || DRIFTLOOM_DEVICE_TESTING
        attachCount += 1
        NSLog("DriftLoomPlayerSmoke: pip supported=%d", AVPictureInPictureController.isPictureInPictureSupported() ? 1 : 0)
#endif
        guard pictureInPicture?.playerLayer !== layer, AVPictureInPictureController.isPictureInPictureSupported(),
              let controller = AVPictureInPictureController(playerLayer: layer) else { return }
        controller.delegate = self
        // Minimizing the app player must not start a system presentation by itself.
        controller.canStartPictureInPictureAutomaticallyFromInline = false
        pictureInPicture = controller
        possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] controller, _ in
            let possible = controller.isPictureInPicturePossible
            Task { @MainActor [weak self] in
                self?.isPictureInPicturePossible = possible
#if DEBUG || DRIFTLOOM_DEVICE_TESTING
                NSLog("DriftLoomPlayerSmoke: pip possible=%d", possible ? 1 : 0)
                // --player-smoke pip: start Picture in Picture as soon as it's possible.
                if possible, self?.smokeAction == "pip", self?.smokeDone == false { self?.smokeDone = true; self?.togglePictureInPicture() }
#endif
            }
        }
    }
    func togglePictureInPicture() {
        guard let pictureInPicture else { return }
        if pictureInPicture.isPictureInPictureActive { pictureInPicture.stopPictureInPicture() } else { pictureInPicture.startPictureInPicture() }
    }

    /// Apple's player with its native controls, presented over everything; its close button returns here.
    func presentFullscreen(player: AVPlayer, overlay: SubtitleOverlay, byRotation: Bool = false) {
        guard !isFullscreen, let presenter = Self.topViewController() else { return }
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.videoGravity = videoGravity
        // Over full screen keeps DriftLoom's views in the window: with .fullScreen they are removed and
        // rebuilt on return, which recreated the video surface and reloaded the page.
        controller.modalPresentationStyle = .overFullScreen
        openedByRotation = byRotation
        let host = UIHostingController(rootView: overlay)
        host.view.backgroundColor = .clear; host.view.isUserInteractionEnabled = false
        host.view.translatesAutoresizingMaskIntoConstraints = false
        if let content = controller.contentOverlayView {
            content.addSubview(host.view)
            NSLayoutConstraint.activate([host.view.leadingAnchor.constraint(equalTo: content.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                                         host.view.topAnchor.constraint(equalTo: content.topAnchor), host.view.bottomAnchor.constraint(equalTo: content.bottomAnchor)])
        }
        controller.addChild(host); host.didMove(toParent: controller)
        fullscreen = controller
        presenter.present(controller, animated: true)
    }
    /// AVKit can keep a closed player controller alive, so check that it is still on screen.
    var isFullscreen: Bool { fullscreen.map { $0.presentingViewController != nil || $0.isBeingPresented } ?? false }

    /// Turning the phone sideways opens fullscreen; turning it back closes fullscreen that rotation opened.
    func deviceRotated(to orientation: UIDeviceOrientation, player: AVPlayer, overlay: SubtitleOverlay) {
        // An iPad has room for the player beside the details; only phones go full screen when turned.
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        if orientation.isLandscape {
            // Not over another sheet or menu, and not while Picture in Picture has the video.
            guard !isFullscreen, !isPictureInPictureActive, player.currentItem != nil,
                  let root = Self.keyWindow()?.rootViewController, root.presentedViewController == nil else { return }
            presentFullscreen(player: player, overlay: overlay, byRotation: true)
        } else if orientation == .portrait, openedByRotation, isFullscreen, let fullscreen, fullscreen.presentedViewController == nil {
            openedByRotation = false
            fullscreen.dismiss(animated: true)
        }
    }

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow }
    }
    private static func topViewController() -> UIViewController? {
        var top = keyWindow()?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

#if DEBUG || DRIFTLOOM_DEVICE_TESTING
    var smokeAction: String? {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.firstIndex(of: "--player-smoke").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
    }
    var smokeDone = false
    private(set) var attachCount = 0
    func dismissFullscreenForSmoke() { fullscreen?.dismiss(animated: true) }
#endif
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in
            isPictureInPictureActive = true
#if DEBUG || DRIFTLOOM_DEVICE_TESTING
            NSLog("DriftLoomPlayerSmoke: PASS pip started")
#endif
        }
    }
    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
#if DEBUG || DRIFTLOOM_DEVICE_TESTING
        NSLog("DriftLoomPlayerSmoke: FAIL pip %@", error.localizedDescription)
#endif
    }
    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in isPictureInPictureActive = false }
    }
    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completion: @escaping (Bool) -> Void) {
        // Returning from PiP shows the full player again.
        Task { @MainActor in
            NotificationCenter.default.post(name: .driftLoomExpandPlayer, object: nil)
            completion(true)
        }
    }
}

/// The video surface with the subtitle/artwork overlay; controls are drawn by SwiftUI on top.
struct InlinePlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    let overlay: SubtitleOverlay
    let controller: InlinePlayerController
    var gravity: AVLayerVideoGravity = .resizeAspect
    final class Coordinator { var host: UIHostingController<SubtitleOverlay>? }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.backgroundColor = .black; view.clipsToBounds = true
        view.playerLayer.videoGravity = gravity
        view.playerLayer.player = player
        let host = UIHostingController(rootView: overlay)
        host.view.backgroundColor = .clear; host.view.isUserInteractionEnabled = false
        host.view.frame = view.bounds; host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        context.coordinator.host = host
        controller.attach(view.playerLayer)
        return view
    }
    func updateUIView(_ view: PlayerLayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
        if view.playerLayer.videoGravity != gravity { view.playerLayer.videoGravity = gravity }
        controller.videoGravity = gravity
        context.coordinator.host?.rootView = overlay
    }
    static func dismantleUIView(_ view: PlayerLayerView, coordinator: Coordinator) {
        coordinator.host?.view.removeFromSuperview(); coordinator.host = nil
        // The session keeps the AVPlayer for the mini-player and background audio.
        view.playerLayer.player = nil
    }
}

/// AirPlay picker in DriftLoom's colours.
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .white; picker.activeTintColor = UIColor(AppStyle.accent)
        picker.prioritizesVideoDevices = true
        picker.accessibilityIdentifier = "airPlay"
        return picker
    }
    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}

/// Play/pause, skip ±10 s, fullscreen, PiP and AirPlay over the video. Tap toggles; they hide after 3 s while playing.
struct InlinePlayerControls: View {
    @ObservedObject var playback: PlaybackSession
    @ObservedObject var controller: InlinePlayerController
    let overlay: SubtitleOverlay
    @State private var visible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var choosingSpeed = false
    /// Seconds skipped by the latest double tap, shown briefly on that side.
    @State private var skipFeedback: Int?
    @State private var feedbackTask: Task<Void, Never>?
    @EnvironmentObject private var preferences: AppPreferences
    /// A short message after toggling a mode (resize, audio only), as NewPipe shows.
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var size: CGSize = .zero
    private enum Adjustment { case brightness, volume }
    /// The swipe in progress, and the level indicator, which stays up a moment after the swipe ends.
    @State private var adjusting: Adjustment?
    @State private var shownLevel: Adjustment?
    @State private var startLevel = 0.0
    @State private var level = 0.0
    @State private var levelTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.opacity(visible ? 0.35 : 0).accessibilityHidden(true).allowsHitTesting(false)
            // Single tap shows or hides the controls; double tap on either half skips 10 seconds, as on YouTube.
            HStack(spacing: 0) { tapZone(-10); tapZone(10) }.accessibilityHidden(true)
                // Vertical swipes on the left third change brightness, on the right third volume, as in NewPipe.
                .simultaneousGesture(adjustDrag)
            HiddenVolumeView().frame(width: 1, height: 1).opacity(0.01).allowsHitTesting(false).accessibilityHidden(true)
            if let shownLevel {
                HStack(spacing: 10) {
                    Image(systemName: shownLevel == .brightness ? "sun.max.fill" : level == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(width: 24)
                    ProgressView(value: level).tint(.white).frame(width: 96)
                }
                .foregroundColor(.white).padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.black.opacity(0.6)).clipShape(Capsule())
                .frame(maxHeight: .infinity, alignment: .top).padding(.top, 14)
                .allowsHitTesting(false)
                .accessibilityElement().accessibilityIdentifier("gestureLevel")
                .accessibilityLabel(shownLevel == .brightness ? "Brightness" : "Volume").accessibilityValue("\(Int((level * 100).rounded()))%")
            }
            if let toast {
                Text(toast).font(.subheadline.weight(.semibold)).foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7).background(Color.black.opacity(0.6)).clipShape(Capsule())
                    .frame(maxHeight: .infinity, alignment: .top).padding(.top, 14)
                    .allowsHitTesting(false).accessibilityIdentifier("playerToast")
            }
            if let skipFeedback {
                Text(skipFeedback < 0 ? "−10 s" : "+10 s").font(.headline.monospacedDigit()).foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6).background(Color.black.opacity(0.55)).clipShape(Capsule())
                    .frame(maxWidth: .infinity, alignment: skipFeedback < 0 ? .leading : .trailing).padding(.horizontal, 28)
                    .allowsHitTesting(false).accessibilityIdentifier("skipFeedback")
            }
            if visible {
                HStack(spacing: 44) {
                    controlButton("gobackward.10", label: "Back 10 seconds", id: "skipBack") { skip(-10) }
                    controlButton(playback.phase == .playing ? "pause.fill" : "play.fill", label: playback.phase == .playing ? "Pause" : "Play",
                                  id: "playPause", size: 34) { playback.togglePlayPause(); scheduleHide() }
                    controlButton("goforward.10", label: "Forward 10 seconds", id: "skipForward") { skip(10) }
                }
                VStack {
                    Spacer()
                    HStack(spacing: 4) {
                        Button { hideTask?.cancel(); choosingSpeed = true } label: {
                            Text("\(String(format: "%g", playback.playbackRate))×")
                                .font(.system(size: 15, weight: .semibold)).monospacedDigit().foregroundColor(.white)
                                .frame(minWidth: 44, minHeight: 40).contentShape(Rectangle())
                        }
                        .accessibilityLabel("Playback speed").accessibilityValue("\(String(format: "%g", playback.playbackRate))×")
                        .accessibilityIdentifier("playbackSpeed")
                        Spacer()
                        controlButton(resizeSymbol, label: "Resize", id: "resizeMode", size: 18) {
                            let next = preferences.videoResize.next
                            preferences.setVideoResize(next); show(resizeTitle(next)); scheduleHide()
                        }
                        .accessibilityValue(Text(resizeTitle(preferences.videoResize)))
                        if playback.currentItemMetadata?.isSoundCloud != true {
                            controlButton(playback.audioOnly ? "headphones.circle.fill" : "headphones", label: "Audio only", id: "audioOnly", size: 18) {
                                playback.setAudioOnly(!playback.audioOnly)
                                show(playback.audioOnly ? String(localized: "Audio only") : String(localized: "Video and audio")); scheduleHide()
                            }
                            .accessibilityValue(playback.audioOnly ? "On" : "Off")
                        }
                        AirPlayButton().frame(width: 40, height: 40)
                        if controller.isPictureInPicturePossible || controller.isPictureInPictureActive {
                            controlButton(controller.isPictureInPictureActive ? "pip.exit" : "pip.enter",
                                          label: controller.isPictureInPictureActive ? "Exit Picture in Picture" : "Picture in Picture",
                                          id: "pictureInPicture", size: 18) { controller.togglePictureInPicture() }
                        }
                        controlButton("arrow.up.left.and.arrow.down.right", label: "Full screen", id: "fullscreen", size: 18) {
                            controller.presentFullscreen(player: playback.player, overlay: overlay)
                        }
                    }.padding(.horizontal, 6).padding(.bottom, 2)
                }
            }
        }
        .background(GeometryReader { proxy in
            Color.clear.onAppear { size = proxy.size }.onChange(of: proxy.size) { size = $0 }
        })
        .animation(.easeInOut(duration: 0.2), value: visible)
        // Attached to the always-present container so auto-hiding the controls can't dismiss it.
        .confirmationDialog("Playback speed", isPresented: $choosingSpeed, titleVisibility: .visible) {
            ForEach([Float(0.25), 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2], id: \.self) { rate in
                Button("\(String(format: "%g", rate))×\(playback.playbackRate == rate ? " ✓" : "")") { playback.setPlaybackRate(rate) }
            }
        }
        .onChange(of: choosingSpeed) { open in if !open { scheduleHide() } }
        .onAppear(perform: scheduleHide)
#if DEBUG || DRIFTLOOM_DEVICE_TESTING
        .task(id: playback.phase == .playing) {
            // --player-smoke fullscreen|fullscreen-close|speed|hud: open the full-screen player, the speed choices or the paused controls once playback runs.
            guard playback.phase == .playing, !controller.smokeDone else { return }
            if controller.smokeAction == "speed" {
                controller.smokeDone = true
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                visible = true; choosingSpeed = true
                NSLog("DriftLoomPlayerSmoke: PASS speed choices shown at %g×", playback.playbackRate)
                return
            }
            if controller.smokeAction == "audio" {
                // Switch to audio only once playing and report what the new stream carries.
                controller.smokeDone = true
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                let before = playback.player.currentTime().seconds
                let started = Date()
                playback.setAudioOnly(true)
                Task { @MainActor in
                    for _ in 0..<120 {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        guard let item = playback.player.currentItem, item.status == .readyToPlay else { continue }
                        let tracks = (try? await item.asset.loadTracks(withMediaType: .video)) ?? []
                        NSLog("DriftLoomPlayerSmoke: %@ audio only after %.1f s: video tracks=%d size=%.0fx%.0f at %.1f s (was %.1f s)",
                              tracks.isEmpty && item.presentationSize == .zero ? "PASS" : "FAIL", Date().timeIntervalSince(started), tracks.count,
                              item.presentationSize.width, item.presentationSize.height, playback.player.currentTime().seconds, before)
                        return
                    }
                    NSLog("DriftLoomPlayerSmoke: FAIL audio only never became ready")
                }
                return
            }
            if controller.smokeAction == "hud" {
                // Pause so the controls stay up for a screenshot.
                controller.smokeDone = true
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                playback.togglePlayPause(); visible = true
                NSLog("DriftLoomPlayerSmoke: PASS controls shown")
                return
            }
            guard controller.smokeAction == "fullscreen" || controller.smokeAction == "fullscreen-close" else { return }
            controller.smokeDone = true
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            controller.presentFullscreen(player: playback.player, overlay: overlay)
            NSLog("DriftLoomPlayerSmoke: %@ fullscreen presented", controller.isFullscreen ? "PASS" : "FAIL")
            guard controller.smokeAction == "fullscreen-close" else { return }
            // Not tied to this task: buffering changes the phase, which cancels it and skips the waits.
            Task { @MainActor in
                // Closing must keep the same player item and video surface.
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                // A reload replaces the player item or recreates the video surface; time can stall on a slow network either way.
                let item = playback.player.currentItem, surfaces = controller.attachCount
                controller.dismissFullscreenForSmoke()
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                let ok = item != nil && playback.player.currentItem === item && controller.attachCount == surfaces && !controller.isFullscreen
                NSLog("DriftLoomPlayerSmoke: %@ fullscreen closed without reload (same item %d, surfaces %d)", ok ? "PASS" : "FAIL",
                      playback.player.currentItem === item ? 1 : 0, controller.attachCount)
                controller.presentFullscreen(player: playback.player, overlay: overlay)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                NSLog("DriftLoomPlayerSmoke: %@ fullscreen reopened", controller.isFullscreen ? "PASS" : "FAIL")
            }
        }
#endif
        .onChange(of: playback.phase) { _ in scheduleHide() }
        .onAppear { UIDevice.current.beginGeneratingDeviceOrientationNotifications() }
        .onDisappear { UIDevice.current.endGeneratingDeviceOrientationNotifications() }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            controller.deviceRotated(to: UIDevice.current.orientation, player: playback.player, overlay: overlay)
        }
    }

    private func controlButton(_ symbol: String, label: LocalizedStringKey, id: String, size: CGFloat = 24, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size, weight: .semibold)).foregroundColor(.white)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel(label).accessibilityIdentifier(id)
    }
    private var resizeSymbol: String {
        switch preferences.videoResize {
        case .fit: return "rectangle.arrowtriangle.2.inward"
        case .zoom: return "plus.magnifyingglass"
        case .fill: return "rectangle.arrowtriangle.2.outward"
        }
    }
    private func resizeTitle(_ mode: VideoResize) -> String {
        switch mode {
        case .fit: return String(localized: "Fit")
        case .zoom: return String(localized: "Zoom")
        case .fill: return String(localized: "Fill")
        }
    }
    private func show(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { try? await Task.sleep(nanoseconds: 2_000_000_000); if !Task.isCancelled { toast = nil } }
    }
    /// Brightness on the left third, volume on the right third; the middle is left to dragging the player down.
    private var adjustDrag: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                if adjusting == nil {
                    guard abs(value.translation.height) > abs(value.translation.width), size.width > 0 else { return }
                    if value.startLocation.x < size.width / 3 {
                        adjusting = .brightness; startLevel = Double(UIScreen.main.brightness)
                    } else if value.startLocation.x > size.width * 2 / 3 {
                        adjusting = .volume; startLevel = Double(AVAudioSession.sharedInstance().outputVolume)
                    } else { return }
                    levelTask?.cancel()
                    shownLevel = adjusting
                }
                // Dragging the full height of the player covers the whole range.
                level = min(1, max(0, startLevel - Double(value.translation.height / max(160, size.height))))
                if adjusting == .brightness { UIScreen.main.brightness = CGFloat(level) } else { HiddenVolumeView.setVolume(Float(level)) }
            }
            .onEnded { _ in
                guard adjusting != nil else { return }
                adjusting = nil
                levelTask = Task { try? await Task.sleep(nanoseconds: 2_000_000_000); if !Task.isCancelled { shownLevel = nil } }
            }
    }
    private func tapZone(_ seconds: Int) -> some View {
        Color.clear.contentShape(Rectangle())
            .onTapGesture(count: 2) {
                skip(Double(seconds))
                skipFeedback = seconds
                feedbackTask?.cancel()
                feedbackTask = Task { try? await Task.sleep(nanoseconds: 700_000_000); if !Task.isCancelled { skipFeedback = nil } }
            }
            .onTapGesture { visible.toggle(); scheduleHide() }
    }
    private func skip(_ seconds: Double) {
        let now = playback.player.currentTime().seconds
        guard now.isFinite else { return }
        Task { await playback.player.seek(to: CMTime(seconds: max(0, now + seconds), preferredTimescale: 600)) }
        scheduleHide()
    }
    private func scheduleHide() {
        hideTask?.cancel()
        guard visible, !choosingSpeed, playback.phase == .playing, !UIAccessibility.isVoiceOverRunning else { return }
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled { visible = false }
        }
    }
}

extension VideoResize {
    var gravity: AVLayerVideoGravity { self == .fit ? .resizeAspect : self == .zoom ? .resizeAspectFill : .resize }
}

/// An off-screen system volume view: setting its slider changes the volume without the system HUD,
/// the documented way for apps to offer their own volume control.
struct HiddenVolumeView: UIViewRepresentable {
    private static weak var slider: UISlider?
    static func setVolume(_ value: Float) {
        guard let slider else { return }
        slider.setValue(value, animated: false)
        slider.sendActions(for: .valueChanged)
    }
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: CGRect(x: -100, y: -100, width: 1, height: 1))
        // Only its slider is used; the route button and labels stay out of sight and out of VoiceOver.
        view.setRouteButtonImage(UIImage(), for: .normal)
        view.accessibilityElementsHidden = true
        Self.slider = view.subviews.compactMap { $0 as? UISlider }.first
        return view
    }
    func updateUIView(_ view: MPVolumeView, context: Context) {
        if Self.slider == nil { Self.slider = view.subviews.compactMap { $0 as? UISlider }.first }
    }
}
