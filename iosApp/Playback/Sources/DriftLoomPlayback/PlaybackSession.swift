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
    @Published public private(set) var playbackRate: Float = 1
    @Published public private(set) var maximumHeight = 0
    @Published public private(set) var selectedFormat: DownloadChoice?
    @Published public private(set) var subtitleTracks: [SubtitleTrack] = []
    /// Languages YouTube can machine-translate this video's subtitles into.
    @Published public private(set) var subtitleTranslations: [SubtitleLanguage] = []
    private var subtitleCatalog = SubtitleCatalog(tracks: [])
    /// Use an auto-translated track when the preferred language has no subtitles of its own.
    public var translatesSubtitles = false
    @Published public private(set) var selectedSubtitle: SubtitleTrack?
    @Published public private(set) var subtitleText: String?
    @Published public private(set) var subtitleError: String?
    /// Seek-bar preview frames for the current video, when YouTube provides them.
    @Published public private(set) var storyboard: Storyboard?
    /// Language used to pick a track automatically for new videos; nil keeps subtitles off.
    public var preferredSubtitleLanguage: String?
    /// Called when the user picks a track or turns subtitles off, with its base language.
    public var onSubtitleChoice: ((String?) -> Void)?
    /// Offline subtitles saved with a download, keyed by video ID.
    public var localSubtitles: ((String) -> (SubtitleTrack, [SubtitleCue])?)?
    public var localMedia: ((String) -> URL?)?
    public var remembersPositions = true
    public var resumesPositions = true
    private let positions: PlaybackPositions?
    private var positionObserver: Any?
    private var subtitleObserver: Any?
    private var subtitleTimeline: SubtitleTimeline?
    private var subtitleTask: Task<Void, Never>?
    private var subtitleGeneration = UUID()
    private let subtitles: (any SubtitleLoading)?

    private let resolver: any StreamResolving
    private var currentRequest: VideoRequest?
    private var generation = UUID()
    private var resolveTask: Task<Void, Never>?
    private var recoveryPolicy = PlaybackRecoveryPolicy()
    private var failureTask: Task<Void, Never>?
    private var itemObservation: NSKeyValueObservation?
    private var playerObservation: NSKeyValueObservation?
    private var failureObserver: NSObjectProtocol?

    public init(resolver: any StreamResolving = YouTubeStreamResolver(), positions: PlaybackPositions? = nil,
                subtitles: (any SubtitleLoading)? = nil) {
        self.resolver = resolver
        self.positions = positions
        self.subtitles = subtitles
        subtitleObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 4), queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in self?.updateSubtitle(at: time.seconds) }
        }
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        if positions != nil {
            positionObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 5, preferredTimescale: 1), queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.rememberPosition() }
            }
        }
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
        if let positionObserver { player.removeTimeObserver(positionObserver) }
        if let subtitleObserver { player.removeTimeObserver(subtitleObserver) }
        subtitleTask?.cancel()
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
            title = Self.placeholderTitle
            let saved = remembersPositions && resumesPositions ? positions?.seconds(for: request.videoID) ?? 0 : 0
            let position = CMTime(seconds: saved, preferredTimescale: 600)
            if let url = localMedia?(request.videoID), url.isFileURL {
#if os(iOS)
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                try AVAudioSession.sharedInstance().setActive(true)
#endif
                install(ResolvedVideo(title: L("Downloaded video"), streamURL: url, usesHLS: url.pathExtension == "movpkg"), position: position)
            } else { resolve(request, position: position) }
            loadSubtitles(videoID: request.videoID)
        } catch { phase = .failed(error.localizedDescription) }
    }

    public func open(_ item: BrowseItem) {
        guard item.kind == .video else { open(""); return }
        open(item.contentID)
        if videoID == item.contentID { sourceItem = item; if video?.streamURL.isFileURL == true { title = item.title } }
    }

    /// Title shown until the real one is known.
    nonisolated public static var placeholderTitle: String { L("YouTube video") }

    public var currentItemMetadata: BrowseItem? {
        guard let videoID else { return nil }
        return BrowseItem(contentID: videoID, kind: .video,
                          title: title == Self.placeholderTitle ? (sourceItem?.title ?? title) : title,
                          subtitle: sourceItem?.subtitle ?? "",
                          thumbnail: sourceItem?.thumbnail ?? (SoundCloudID.isSoundCloud(videoID) ? nil : URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg")),
                          duration: sourceItem?.duration, channelID: sourceItem?.channelID, webURL: sourceItem?.webURL)
    }

    /// Restore metadata without extraction or unsolicited audio on launch.
    public func prepare(_ item: BrowseItem) {
        guard item.kind == .video, let request = try? VideoRequest(input: item.contentID) else { return }
        stop(); currentRequest = request; videoID = request.videoID; sourceItem = item
        title = item.title; phase = .paused
    }

    public func retry() {
        guard let currentRequest else { return }
        if let sourceItem { open(sourceItem) }
        else { open(currentRequest.videoID) }
    }

    public func resume() {
        guard player.currentItem != nil else { retry(); return }
        player.playImmediately(atRate: playbackRate)
    }
    public func togglePlayPause() {
        if phase == .playing { player.pause() } else { resume() }
    }
    public func setPlaybackRate(_ value: Float) {
        guard [Float(0.25), 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2].contains(value) else { return }
        playbackRate = value
        if phase == .playing { player.rate = value }
    }
    public func selectFormat(_ choice: DownloadChoice?) {
        guard let currentRequest else { return }
        let position = player.currentTime()
        let autoplay = phase == .playing || phase == .loading
        selectedFormat = choice
        clearItemObservers(); player.pause(); player.replaceCurrentItem(with: nil)
        resolve(currentRequest, position: position, autoplay: autoplay)
    }
    public func setMaximumHeight(_ height: Int) {
        guard [0, 360, 480, 720, 1080].contains(height) else { return }
        maximumHeight = height
        player.currentItem?.preferredMaximumResolution = resolutionLimit
    }
    private var resolutionLimit: CGSize {
        maximumHeight == 0 ? .zero : CGSize(width: Double(maximumHeight) * 16 / 9, height: Double(maximumHeight))
    }

    public func stop() {
        rememberPosition()
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
        selectedFormat = nil
        clearSubtitles()
        phase = .idle
    }

    /// Select an external track, or nil to turn subtitles off. The choice is remembered by language.
    public func selectSubtitle(_ track: SubtitleTrack?) {
        onSubtitleChoice?(track.map { SubtitleSelection.baseLanguage($0.displayLanguage) })
        preferredSubtitleLanguage = track.map { SubtitleSelection.baseLanguage($0.displayLanguage) }
        apply(track)
    }

    /// Choose a machine translation of the recommended source track.
    public func selectTranslation(_ language: SubtitleLanguage) {
        guard let source = subtitleCatalog.translationSource else { return }
        selectSubtitle(source.translated(to: language))
    }

    private func loadSubtitles(videoID: String) {
        clearSubtitles()
        if let local = localSubtitles?(videoID) {
            subtitleTracks = [local.0]
            if SubtitleSelection.preferred([local.0], language: preferredSubtitleLanguage) != nil { install(local.0, cues: local.1) }
            return
        }
        // SoundCloud tracks have no subtitles.
        guard let subtitles, !SoundCloudID.isSoundCloud(videoID) else { return }
        let token = subtitleGeneration
        subtitleTask = Task { [weak self] in
            let catalog = (try? await subtitles.catalog(videoID: videoID)) ?? SubtitleCatalog(tracks: [])
            let storyboard = await subtitles.storyboard(videoID: videoID)
            guard !Task.isCancelled, let self, self.subtitleGeneration == token, self.videoID == videoID else { return }
            self.storyboard = storyboard
            self.subtitleCatalog = catalog
            self.subtitleTracks = catalog.tracks
            self.subtitleTranslations = catalog.translations
            self.subtitleTask = nil
            if let track = catalog.preferred(language: self.preferredSubtitleLanguage, allowTranslation: self.translatesSubtitles) { self.apply(track) }
        }
    }

    private func apply(_ track: SubtitleTrack?) {
        subtitleTask?.cancel(); subtitleTask = nil
        subtitleTimeline = nil; subtitleText = nil; subtitleError = nil
        subtitleGeneration = UUID()
        selectedSubtitle = track
        guard let track else { return }
        if track.url.isFileURL, let videoID, let local = localSubtitles?(videoID), local.0.id == track.id {
            install(track, cues: local.1); return
        }
        guard let subtitles else { return }
        let token = subtitleGeneration
        subtitleTask = Task { [weak self] in
            do {
                let cues = try await subtitles.cues(for: track)
                guard !Task.isCancelled, let self, self.subtitleGeneration == token, self.selectedSubtitle == track else { return }
                self.install(track, cues: cues)
            } catch is CancellationError {
            } catch {
                guard let self, self.subtitleGeneration == token, self.selectedSubtitle == track else { return }
                self.subtitleError = error.localizedDescription
            }
        }
    }

    private func install(_ track: SubtitleTrack, cues: [SubtitleCue]) {
        selectedSubtitle = track
        subtitleTimeline = SubtitleTimeline(cues)
        // External subtitles replace any captions embedded in the media to avoid showing both.
        if let item = player.currentItem, let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) {
            item.select(nil, in: group)
        }
        updateSubtitle(at: player.currentTime().seconds)
    }

    /// The subtitle text the overlay shows at a playback time, for the currently loaded track.
    func subtitle(at seconds: Double) -> String? { subtitleTimeline?.text(at: seconds) }

    private func updateSubtitle(at seconds: Double) {
        let text = subtitle(at: seconds)
        if text != subtitleText { subtitleText = text }
    }

    private func clearSubtitles() {
        subtitleTask?.cancel(); subtitleTask = nil; subtitleGeneration = UUID()
        subtitleTimeline = nil; subtitleTracks = []; selectedSubtitle = nil; subtitleText = nil; subtitleError = nil
        subtitleTranslations = []; subtitleCatalog = SubtitleCatalog(tracks: []); storyboard = nil
    }

    private func rememberPosition() {
        guard remembersPositions, let id = videoID, let item = player.currentItem, item.status == .readyToPlay else { return }
        positions?.record(id: id, seconds: player.currentTime().seconds, duration: item.duration.seconds)
    }

    private func resolve(_ request: VideoRequest, position: CMTime, autoplay: Bool = true) {
        generation = UUID()
        let token = generation
        resolveTask?.cancel()
        phase = .resolving
        let choice = selectedFormat
        resolveTask = Task { [weak self, resolver] in
            do {
                let video = try await resolver.resolve(request, choice: choice)
                try Task.checkCancellation()
                // A separate audio stream is combined with the video-only stream for playback.
                let merged: AVAsset? = try await video.audioURL.asyncMap { try await MergedMedia.composition(video: video.streamURL, audio: $0) }
                try Task.checkCancellation()
                guard let self, self.generation == token else { return }
#if os(iOS)
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                try AVAudioSession.sharedInstance().setActive(true)
#endif
                self.install(video, asset: merged, position: position, autoplay: autoplay)
            } catch is CancellationError {
                // A newer request owns the UI now.
            } catch {
                guard let self, self.generation == token else { return }
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    private func install(_ video: ResolvedVideo, asset: AVAsset? = nil, position: CMTime, autoplay: Bool = true) {
        clearItemObservers()
        self.video = video
        title = video.title
        if sourceItem == nil, let item = video.item, item.contentID == videoID { sourceItem = item }
        phase = .loading
        let item = asset.map { AVPlayerItem(asset: $0) } ?? AVPlayerItem(url: video.streamURL)
        item.preferredMaximumResolution = resolutionLimit
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
                    if autoplay { self.resume() }
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
        // Merged playback can fail on either stream, so check the audio URL too.
        let streamURLs = [video?.streamURL, video?.audioURL].compactMap { $0 }.filter { !$0.isFileURL }
        failureTask = Task { [weak self, weak item] in
            // Initial manifest failures can have no AVPlayer error log. Confirm the HTTP
            // status without fetching a media body; do not depend on private CoreMedia codes.
            var status = loggedStatus
            for streamURL in streamURLs where loggedStatus == nil && status != 403 {
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
                    ?? L("Playback stopped. Try opening the video again."))
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

private extension Optional {
    func asyncMap<T>(_ transform: (Wrapped) async throws -> T) async rethrows -> T? {
        guard let value = self else { return nil }
        return try await transform(value)
    }
}
