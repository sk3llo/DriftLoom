// SPDX-License-Identifier: GPL-3.0-or-later
import AVFoundation
import Combine
import DriftLoomPlayback
import MediaPlayer

@MainActor
final class NowPlayingController {
    private let playback: PlaybackSession
    private let observedPlayer: AVPlayer
    private let queue: PlaybackQueue
    private var commands: [(MPRemoteCommand, Any)] = []
    private var subscriptions = Set<AnyCancellable>()
    private var timeObserver: Any?
    private var interruptionWasPlaying = false

    init(playback: PlaybackSession, queue: PlaybackQueue) {
        self.playback = playback; self.queue = queue; observedPlayer = playback.player
        let center = MPRemoteCommandCenter.shared()
        bind(center.playCommand) { $0.playback.resume() }
        bind(center.pauseCommand) { $0.playback.player.pause() }
        bind(center.togglePlayPauseCommand) { $0.playback.togglePlayPause() }
        bind(center.stopCommand) { $0.queue.stop() }
        bind(center.nextTrackCommand) { $0.queue.next() }
        bind(center.previousTrackCommand) { $0.queue.previous() }
        let seek = center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent,
                  event.positionTime.isFinite, event.positionTime >= 0 else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.playback.player.seek(to: CMTime(seconds: position, preferredTimescale: 600))
                self.update()
            }
            return .success
        }
        commands.append((center.changePlaybackPositionCommand, seek))
        playback.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in self?.update() }.store(in: &subscriptions)
        queue.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in self?.update() }.store(in: &subscriptions)
        timeObserver = playback.player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 1), queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.update() }
        }
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification).receive(on: RunLoop.main)
            .sink { [weak self] notification in self?.interruption(notification) }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification).receive(on: RunLoop.main)
            .sink { [weak self] notification in
                if let value = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                   AVAudioSession.RouteChangeReason(rawValue: value) == .oldDeviceUnavailable { self?.playback.player.pause() }
            }.store(in: &subscriptions)
        update()
    }
    deinit {
        if let timeObserver { observedPlayer.removeTimeObserver(timeObserver) }
        for (command, token) in commands { command.removeTarget(token) }
    }
    private func bind(_ command: MPRemoteCommand, action: @escaping @MainActor (NowPlayingController) -> Void) {
        let token = command.addTarget { [weak self] _ in
            guard self != nil else { return .commandFailed }
            Task { @MainActor [weak self] in if let self { action(self); self.update() } }
            return .success
        }
        commands.append((command, token))
    }
    private func update() {
        let center = MPRemoteCommandCenter.shared()
        let available = playback.videoID != nil
        center.playCommand.isEnabled = available
        center.pauseCommand.isEnabled = available
        center.togglePlayPauseCommand.isEnabled = available
        center.stopCommand.isEnabled = available
        center.nextTrackCommand.isEnabled = available && queue.canGoNext
        center.previousTrackCommand.isEnabled = available && queue.canGoPrevious
        guard available else {
            center.changePlaybackPositionCommand.isEnabled = false
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: playback.title,
            MPMediaItemPropertyArtist: playback.sourceItem?.subtitle ?? "YouTube",
            MPNowPlayingInfoPropertyPlaybackRate: playback.phase == .playing ? playback.playbackRate : 0
        ]
        let elapsed = playback.player.currentTime().seconds
        let duration = playback.player.currentItem?.duration.seconds ?? .nan
        if elapsed.isFinite { info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed }
        if duration.isFinite, duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        center.changePlaybackPositionCommand.isEnabled = duration.isFinite && duration > 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    private func interruption(_ notification: Notification) {
        guard let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: value) else { return }
        if type == .began {
            interruptionWasPlaying = playback.phase == .playing
            playback.player.pause()
        } else {
            let options = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
            if interruptionWasPlaying, options.contains(.shouldResume) {
                try? AVAudioSession.sharedInstance().setActive(true)
                playback.resume()
            }
            interruptionWasPlaying = false
        }
    }
}
