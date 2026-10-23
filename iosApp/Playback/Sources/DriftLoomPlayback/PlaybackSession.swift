// SPDX-License-Identifier: GPL-3.0-or-later
import AVFoundation
import Combine
import Foundation

public enum PlaybackPhase: Equatable {
    case idle, resolving, loading, playing, paused, failed(String)
}

@MainActor
public final class PlaybackSession: ObservableObject {
    public let player = AVPlayer()
    @Published public private(set) var phase: PlaybackPhase = .idle
    @Published public private(set) var title = "DriftLoom"
    @Published public private(set) var video: ResolvedVideo?
    @Published public private(set) var didRecover = false
    @Published public private(set) var videoID: String?
    @Published public private(set) var sourceItem: BrowseItem?

    private let resolver: any StreamResolving
    private var currentRequest: VideoRequest?
    private var generation = UUID()
    private var resolveTask: Task<Void, Never>?
    private var recoveryPolicy = PlaybackRecoveryPolicy()
    private var failureTask: Task<Void, Never>?
    private var itemObservation: NSKeyValueObservation?
    private var playerObservation: NSKeyValueObservation?
    private var failureObserver: NSObjectProtocol?

    public init(resolver: any StreamResolving = YouTubeStreamResolver()) {
        self.resolver = resolver
        playerObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, self.player.currentItem?.status == .readyToPlay else { return }
                switch self.player.timeControlStatus {
                case .playing: self.phase = .playing
                case .paused: self.phase = .paused
                case .waitingToPlayAtSpecifiedRate: self.phase = .loading
                @unknown default: break
                }
            }
        }
    }

    deinit {
        resolveTask?.cancel()
        failureTask?.cancel()
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
    }

    public func open(_ input: String) {
        // Invalid input must also cancel the previous video/resolution.
        stop()
        do {
            let request = try VideoRequest(input: input)
            currentRequest = request
            videoID = request.videoID
            recoveryPolicy = PlaybackRecoveryPolicy()
            didRecover = false
            title = "YouTube video"
            resolve(request, position: .zero)
        } catch { phase = .failed(error.localizedDescription) }
    }

    public func open(_ item: BrowseItem) {
        guard item.kind == .video else { open(""); return }
        open(item.contentID)
        if videoID == item.contentID { sourceItem = item }
    }

    public var currentItemMetadata: BrowseItem? {
        guard let videoID else { return nil }
        return BrowseItem(contentID: videoID, kind: .video,
                          title: title == "YouTube video" ? (sourceItem?.title ?? title) : title,
                          subtitle: sourceItem?.subtitle ?? "",
                          thumbnail: sourceItem?.thumbnail ?? URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg"),
                          duration: sourceItem?.duration, channelID: sourceItem?.channelID)
    }

    public func retry() {
        guard let currentRequest else { return }
        if let sourceItem { open(sourceItem) }
        else { open(currentRequest.watchURL.absoluteString) }
    }

    public func stop() {
        generation = UUID()
        resolveTask?.cancel()
        resolveTask = nil
        clearItemObservers()
        player.pause()
        player.replaceCurrentItem(with: nil)
#if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
#endif
        currentRequest = nil
        videoID = nil
        sourceItem = nil
        title = "DriftLoom"
        didRecover = false
        video = nil
        phase = .idle
    }

    private func resolve(_ request: VideoRequest, position: CMTime) {
        generation = UUID()
        let token = generation
        resolveTask?.cancel()
        phase = .resolving
        resolveTask = Task { [weak self, resolver] in
            do {
                let video = try await resolver.resolve(request)
                try Task.checkCancellation()
                guard let self, self.generation == token else { return }
#if os(iOS)
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                try AVAudioSession.sharedInstance().setActive(true)
#endif
                self.install(video, position: position)
            } catch is CancellationError {
                // A newer request owns the UI now.
            } catch {
                guard let self, self.generation == token else { return }
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    private func install(_ video: ResolvedVideo, position: CMTime) {
        clearItemObservers()
        self.video = video
        title = video.title
        phase = .loading
        let item = AVPlayerItem(url: video.streamURL)
        itemObservation = item.observe(\.status, options: [.new]) { [weak self, weak item] _, _ in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.player.currentItem === item else { return }
                if item.status == .failed { self.failed(item) }
                else if item.status == .readyToPlay {
                    self.phase = .paused
                    if position.isNumeric && position.seconds > 0 {
                        await self.player.seek(to: position)
                    }
                    guard self.player.currentItem === item else { return }
                    self.player.play()
                }
            }
        }
        failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { [weak self, weak item] _ in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.player.currentItem === item else { return }
                self.failed(item)
            }
        }
        player.replaceCurrentItem(with: item)
    }

    private func failed(_ item: AVPlayerItem) {
        guard failureTask == nil else { return }
        let token = generation
        let loggedStatus = item.errorLog()?.events.last(where: { $0.errorStatusCode == 403 })?.errorStatusCode
        let streamURL = video?.streamURL
        failureTask = Task { [weak self, weak item] in
            // Initial manifest failures can have no AVPlayer error log. Confirm the HTTP
            // status without fetching a media body; do not depend on private CoreMedia codes.
            var status = loggedStatus
            if status == nil, let streamURL {
                var request = URLRequest(url: streamURL, cachePolicy: .reloadIgnoringLocalCacheData,
                                         timeoutInterval: 10)
                request.httpMethod = "HEAD"
                if let (_, response) = try? await URLSession.shared.data(for: request) {
                    status = (response as? HTTPURLResponse)?.statusCode
                }
            }
            guard !Task.isCancelled, let self, let item,
                  self.generation == token, self.player.currentItem === item else { return }
            self.failureTask = nil
            if self.recoveryPolicy.shouldRefresh(httpStatus: status), let request = self.currentRequest {
                let position = self.player.currentTime()
                self.clearItemObservers()
                self.player.pause()
                self.player.replaceCurrentItem(with: nil)
                self.didRecover = true
                self.resolve(request, position: position)
            } else {
                self.phase = .failed(item.error?.localizedDescription
                    ?? "Playback stopped. Try opening the video again.")
            }
        }
    }

    private func clearItemObservers() {
        failureTask?.cancel()
        failureTask = nil
        itemObservation = nil
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        failureObserver = nil
    }
}
