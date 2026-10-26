// SPDX-License-Identifier: GPL-3.0-or-later
import AVFoundation
import Combine
import DriftLoomPlayback
import Foundation
import UIKit
import Network

@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()
    static let fileSessionID = "net.driftloom.app.download.files"
    static let hlsSessionID = "net.driftloom.app.download.hls"
    let library: DownloadLibrary
    private let bridge: DownloadDelegate
    private var files: URLSession!
    private var hls: AVAssetDownloadURLSession!
    private var wifiFiles: URLSession!
    private var wifiHLS: AVAssetDownloadURLSession!
    private let networkMonitor = NWPathMonitor()
    private var networkConnected = false
    private var networkCellular = false
    private var subscriptions = Set<AnyCancellable>()
    private var preparations: [UUID: Task<Void, Never>] = [:]
    private var completions: [String: () -> Void] = [:]
    private var connected = false
    private var validations = 0
    private var finishedSessions = Set<String>()
    private var partProgress: [String: [String: Double]] = [:]
    @Published var operationError: String?
    @Published private(set) var reconnecting = true

    private init() {
        library = DownloadLibrary(fileURL: libraryFileURL().deletingLastPathComponent().appendingPathComponent("downloads.json"))
        bridge = DownloadDelegate()
        bridge.owner = self
        var suffix = ""
#if DEBUG || DRIFTLOOM_DEVICE_TESTING
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--library-smoke-run"), arguments.indices.contains(index + 1),
           arguments[index + 1].range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil { suffix = ".test." + arguments[index + 1] }
#endif
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.fileSessionID + suffix)
        DownloadNetwork.any.configure(configuration)
        files = URLSession(configuration: configuration, delegate: bridge, delegateQueue: nil)
        let hlsConfiguration = URLSessionConfiguration.background(withIdentifier: Self.hlsSessionID + suffix)
        DownloadNetwork.any.configure(hlsConfiguration)
        hls = AVAssetDownloadURLSession(configuration: hlsConfiguration, assetDownloadDelegate: bridge, delegateQueue: nil)
        let wifiConfiguration = URLSessionConfiguration.background(withIdentifier: Self.fileSessionID + ".wifi" + suffix)
        DownloadNetwork.wifiOnly.configure(wifiConfiguration)
        wifiFiles = URLSession(configuration: wifiConfiguration, delegate: bridge, delegateQueue: nil)
        let wifiHLSConfiguration = URLSessionConfiguration.background(withIdentifier: Self.hlsSessionID + ".wifi" + suffix)
        DownloadNetwork.wifiOnly.configure(wifiHLSConfiguration)
        wifiHLS = AVAssetDownloadURLSession(configuration: wifiHLSConfiguration, assetDownloadDelegate: bridge, delegateQueue: nil)
#if DEBUG || DRIFTLOOM_DEVICE_TESTING
        let forcedOffline = ProcessInfo.processInfo.arguments.contains("--download-smoke-no-network")
#else
        let forcedOffline = false
#endif
        networkMonitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied && !forcedOffline, cellular = path.usesInterfaceType(.cellular)
            Task { @MainActor in
                self?.networkConnected = available; self?.networkCellular = cellular
                self?.resumeWaitingDownloads()
            }
        }
        networkMonitor.start(queue: DispatchQueue(label: "DriftLoom.downloadNetwork"))
        library.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        Task { await reconnect() }
    }
    var records: [DownloadRecord] { library.records }
    func backgroundEvents(identifier: String, completion: @escaping () -> Void) { completions[identifier] = completion }
    func finishedEvents(identifier: String) { finishedSessions.insert(identifier); flushCompletions() }
    private func flushCompletions() {
        guard validations == 0 else { return }
        for identifier in finishedSessions { completions.removeValue(forKey: identifier)?() }
        finishedSessions.removeAll()
    }
    private func allTasks(_ session: URLSession) async -> [URLSessionTask] {
        await withCheckedContinuation { continuation in session.getAllTasks { continuation.resume(returning: $0) } }
    }
    private func reconnect() async {
        var tasks: [URLSessionTask] = []
        for session in [files!, hls!, wifiFiles!, wifiHLS!] { tasks += await allTasks(session) }
        let descriptions = Set(tasks.compactMap { TransferParts.base($0.taskDescription) })
        for task in tasks where matching(task.taskDescription) == nil { task.cancel() }
        for var record in records where record.state == .preparing || record.state == .downloading {
            if record.state == .preparing && record.waitingForNetwork == true { continue }
            // Both parts finished but the app stopped before combining them: combine now.
            if record.partPaths?.count == 2 {
                Task { await mergeParts(description(record)) }; continue
            }
            if !descriptions.contains(description(record)) {
                discardParts(&record)
                record.state = .failed; record.error = "Download interrupted. Retry to obtain a fresh stream."
                _ = library.update(record)
            }
        }
        connected = true; reconnecting = false; resumeWaitingDownloads()
    }
    @discardableResult func start(item: BrowseItem, choice: DownloadChoice, subtitleLanguage: String? = nil) -> UUID? {
        guard connected, library.isWritable else { return nil }
        let record = DownloadRecord(item: item, choice: choice, subtitleLanguage: subtitleLanguage)
        guard library.add(record) else { return nil }
        DownloadNotifier.shared.requestAuthorizationIfNeeded()
        retry(record.id); return record.id
    }
    func retry(_ id: UUID) {
        guard connected, var record = records.first(where: { $0.id == id }), record.state != .completed else { return }
        preparations[id]?.cancel(); preparations[id] = nil
        discardParts(&record)
        record.transferID = UUID(); record.state = .preparing; record.error = nil; record.progress = 0; record.localPath = nil
        record.network = AppPreferences(defaults: makeAppDefaults()).downloadNetwork
        record.waitingForNetwork = !(record.network ?? .any).permits(connected: networkConnected, cellular: networkCellular)
        guard library.update(record), record.waitingForNetwork != true else { return }
        prepare(record)
    }
    private func resumeWaitingDownloads() {
        guard connected else { return }
        for var record in records where record.state == .preparing && record.waitingForNetwork == true && preparations[record.id] == nil {
            guard (record.network ?? .any).permits(connected: networkConnected, cellular: networkCellular) else { continue }
            record.waitingForNetwork = false
            if library.update(record) { prepare(record) }
        }
    }
    private func prepare(_ record: DownloadRecord) {
        let id = record.id
        let transfer = description(record)
        preparations[id] = Task { [weak self] in
            do {
                let source = try await YouTubeDownloadResolver().source(videoID: record.item.contentID, choice: record.choice)
                try Task.checkCancellation()
                await self?.saveSubtitles(record, transfer: transfer)
                guard let self, var current = self.matching(transfer), current.state == .preparing else { return }
                if record.item.isSoundCloud {
                    // A foreground transfer: SoundCloud's segments are joined into one file as they arrive.
                    current.state = .downloading
                    guard self.library.update(current) else { return }
                    // Keep going briefly in the background; if iOS ends that time, stop cleanly so the
                    // job, its Live Activity and its notification say what happened instead of stalling.
                    var background = UIBackgroundTaskIdentifier.invalid
                    background = UIApplication.shared.beginBackgroundTask(withName: "SoundCloud download") { [weak self] in
                        self?.preparations[id]?.cancel(); self?.preparations[id] = nil
                        self?.failed(transfer, message: "Interrupted while DriftLoom was in the background. Retry to continue.")
                        UIApplication.shared.endBackgroundTask(background); background = .invalid
                    }
                    defer { if background != .invalid { UIApplication.shared.endBackgroundTask(background) } }
                    let configuration = URLSessionConfiguration.ephemeral
                    configuration.allowsCellularAccess = record.network != .wifiOnly
                    configuration.waitsForConnectivity = true; configuration.httpCookieStorage = nil; configuration.urlCache = nil
                    let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DriftLoom/Media")
                    let file = try await SoundCloudDownload.save(playlist: source.url, directory: directory, baseName: id.uuidString + "-" + UUID().uuidString,
                                                                 session: URLSession(configuration: configuration)) { [weak self] value in
                        Task { @MainActor in self?.progress(transfer, value: value) }
                    }
                    await self.completed(transfer, location: file, hls: false)
                    if self.records.first(where: { $0.id == id })?.transferID == record.transferID { self.preparations[id] = nil }
                    return
                }
                var tasks: [URLSessionTask] = []
                if source.choice.kind == .merged, let audioURL = source.audioURL {
                    let session = record.network == .wifiOnly ? self.wifiFiles! : self.files!
                    for (part, url) in [(TransferParts.video, source.url), (TransferParts.audio, audioURL)] {
                        var request = URLRequest(url: url); request.allowsCellularAccess = record.network != .wifiOnly
                        let task = session.downloadTask(with: request)
                        task.taskDescription = TransferParts.description(transfer, part: part)
                        tasks.append(task)
                    }
                } else if source.choice.kind == .hls {
                    let asset = AVURLAsset(url: source.url, options: [AVURLAssetAllowsCellularAccessKey: record.network != .wifiOnly])
                    let duration = try await asset.load(.duration)
                    try Task.checkCancellation()
                    guard duration.isNumeric, duration.seconds > 0 else { throw BrowseError.unavailable("Live streams cannot be saved as offline downloads.") }
                    guard self.matching(transfer)?.state == .preparing else { return }
                    let session = record.network == .wifiOnly ? self.wifiHLS! : self.hls!
                    guard let download = session.makeAssetDownloadTask(asset: asset, assetTitle: record.item.title, assetArtworkData: nil, options: nil) else { throw PlaybackError.noPlayableStream }
                    download.taskDescription = transfer; tasks = [download]
                } else {
                    let session = record.network == .wifiOnly ? self.wifiFiles! : self.files!
                    var request = URLRequest(url: source.url); request.allowsCellularAccess = record.network != .wifiOnly
                    let task = session.downloadTask(with: request)
                    task.taskDescription = transfer; tasks = [task]
                }
                current.state = .downloading
                guard self.library.update(current) else { tasks.forEach { $0.cancel() }; return }
                tasks.forEach { $0.resume() }
            } catch is CancellationError { }
            catch { self?.failed(transfer, message: error.localizedDescription) }
            if self?.records.first(where: { $0.id == id })?.transferID == record.transferID { self?.preparations[id] = nil }
        }
    }
    func cancel(_ id: UUID) {
        guard var record = records.first(where: { $0.id == id }), record.state != .completed else { return }
        preparations[id]?.cancel(); preparations[id] = nil
        let transfer = description(record)
        record.state = .cancelled; record.error = nil; record.transferID = nil; record.waitingForNetwork = false
        guard library.update(record) else { return }
        Task {
            for session in [files!, hls!, wifiFiles!, wifiHLS!] {
                for task in await allTasks(session) where TransferParts.base(task.taskDescription) == transfer { task.cancel() }
            }
        }
        if var current = records.first(where: { $0.id == id }), current.partPaths != nil { discardParts(&current); _ = library.update(current) }
    }
    func remove(_ id: UUID) {
        operationError = nil
        guard let record = records.first(where: { $0.id == id }) else { return }
        if record.state != .completed { cancel(id) }
        if let url = managedURL(record) {
            do { try FileManager.default.removeItem(at: url) }
            catch { operationError = "The downloaded media couldn't be deleted. Try again after playback stops."; return }
        }
        if let url = subtitleURL(record) { try? FileManager.default.removeItem(at: url) }
        var parts = record; discardParts(&parts)
        _ = library.remove(id)
    }
    var storageURLs: [URL] { records.compactMap(managedURL) + records.compactMap(subtitleURL) }
    /// Saved subtitles for a completed download of this video, if any.
    func localSubtitles(videoID: String) -> (SubtitleTrack, [SubtitleCue])? {
        records.lazy.filter { $0.item.contentID == videoID && $0.state == .completed }
            .compactMap(subtitleURL).compactMap(SubtitleFiles.load).first
    }
    private func subtitleURL(_ record: DownloadRecord) -> URL? {
        guard let path = record.subtitlePath, path.hasPrefix("Library/Application Support/DriftLoom/Media/"), path.hasSuffix(".subtitles.json") else { return nil }
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        let url = home.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        guard DownloadPaths.relativePath(for: url, home: home) == path, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }
    /// Best effort: a subtitle failure is reported on the job but never blocks the media download.
    private func saveSubtitles(_ record: DownloadRecord, transfer: String) async {
        guard let language = record.subtitleLanguage else { return }
        var outcome: (path: String?, error: String?) = (nil, nil)
        do {
            let client = YouTubeSubtitleClient()
            let translates = AppPreferences(defaults: makeAppDefaults()).translatesSubtitles
            guard let track = try await client.catalog(videoID: record.item.contentID).preferred(language: language, allowTranslation: translates) else {
                throw BrowseError.unavailable("Subtitles in this language aren't available for this video.")
            }
            let cues = try await client.cues(for: track)
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DriftLoom/Media")
            let url = directory.appendingPathComponent(record.id.uuidString + ".subtitles.json")
            try SubtitleFiles.save(track, cues: cues, to: url)
            var local = url; var values = URLResourceValues(); values.isExcludedFromBackup = true
            try? local.setResourceValues(values)
            outcome.path = DownloadPaths.relativePath(for: url, home: URL(fileURLWithPath: NSHomeDirectory()))
        } catch is CancellationError { return }
        catch { outcome.error = error.localizedDescription }
        guard var current = matching(transfer) else { return }
        current.subtitlePath = outcome.path; current.subtitleError = outcome.error
        _ = library.update(current)
    }
    func localURL(_ record: DownloadRecord) -> URL? {
        guard let url = managedURL(record) else { return nil }
        if record.choice.kind == .hls, AVURLAsset(url: url).assetCache?.isPlayableOffline != true { return nil }
        return url
    }
    private func managedURL(_ record: DownloadRecord) -> URL? {
        guard record.state == .completed, let path = record.localPath else { return nil }
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        let url = home.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        guard url.path.hasPrefix(home.path + "/"), DownloadPaths.relativePath(for: url, home: home) == path,
              (path.hasPrefix("Library/Application Support/DriftLoom/Media/") || (path.hasPrefix("Library/com.apple.UserManagedAssets.") && path.split(separator: "/").count == 3 && url.pathExtension == "movpkg")),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }
    private func description(_ record: DownloadRecord) -> String { record.id.uuidString + ":" + (record.transferID?.uuidString ?? "") }
    private func matching(_ taskDescription: String?) -> DownloadRecord? {
        guard let transfer = TransferParts.base(taskDescription) else { return nil }
        return records.first { description($0) == transfer && ($0.state == .preparing || $0.state == .downloading) }
    }
    fileprivate func progress(_ transfer: String?, value: Double) {
        guard value.isFinite, var record = matching(transfer) else { return }
        var progress = max(0, min(1, value))
        if let part = TransferParts.part(transfer), let base = TransferParts.base(transfer) {
            partProgress[base, default: [:]][part] = progress
            progress = TransferParts.combined(partProgress[base] ?? [:])
        }
        guard progress - record.progress >= 0.02 else { return }
        record.progress = progress; _ = library.update(record)
    }
    fileprivate func failed(_ transfer: String?, message: String) {
        guard var record = matching(transfer) else { return }
        if TransferParts.part(transfer) != nil, let base = TransferParts.base(transfer) {
            // One stream failed: stop the other and drop anything already saved.
            Task { for session in [files!, wifiFiles!] { for task in await allTasks(session) where TransferParts.base(task.taskDescription) == base { task.cancel() } } }
            partProgress[base] = nil
        }
        discardParts(&record)
        record.state = .failed; record.error = message
        if library.update(record) { DownloadNotifier.shared.failed(record) }
    }
    /// Delete saved part files of a merged download and forget them on the record.
    private func discardParts(_ record: inout DownloadRecord) {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        for path in record.partPaths?.values ?? [:].values where path.hasPrefix("Library/Application Support/DriftLoom/Media/") {
            try? FileManager.default.removeItem(at: home.appendingPathComponent(path))
        }
        record.partPaths = nil
    }
    /// Combine both finished parts into one MP4, then validate it like any other download.
    private func mergeParts(_ transfer: String) async {
        guard let record = matching(transfer), let parts = record.partPaths,
              let videoPath = parts[TransferParts.video], let audioPath = parts[TransferParts.audio] else { return }
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let output = home.appendingPathComponent("Library/Application Support/DriftLoom/Media")
            .appendingPathComponent(record.id.uuidString + "-" + UUID().uuidString + ".mp4")
        validations += 1
        defer { validations -= 1; flushCompletions() }
        do {
            try await MergedMedia.export(video: home.appendingPathComponent(videoPath), audio: home.appendingPathComponent(audioPath), to: output)
        } catch {
            failed(transfer, message: "The video and audio couldn't be combined. Retry the download."); return
        }
        guard var current = matching(transfer) else { try? FileManager.default.removeItem(at: output); return }
        discardParts(&current); _ = library.update(current)
        partProgress[transfer] = nil
        await completed(transfer, location: output, hls: false)
    }
    fileprivate func completed(_ transfer: String?, location: URL, hls: Bool) async {
        if let part = TransferParts.part(transfer), let base = TransferParts.base(transfer) {
            guard var record = matching(base), let path = DownloadPaths.relativePath(for: location, home: URL(fileURLWithPath: NSHomeDirectory())) else {
                try? FileManager.default.removeItem(at: location); return
            }
            record.partPaths = (record.partPaths ?? [:]).merging([part: path]) { _, new in new }
            guard library.update(record) else { try? FileManager.default.removeItem(at: location); return }
            if record.partPaths?.count == 2 { await mergeParts(base) }
            return
        }
        validations += 1
        defer { validations -= 1; flushCompletions() }
        guard var record = matching(transfer) else {
            try? FileManager.default.removeItem(at: location); return
        }
        guard let relativePath = DownloadPaths.relativePath(for: location, home: URL(fileURLWithPath: NSHomeDirectory())) else {
            failed(transfer, message: "Downloaded media location is unavailable."); return
        }
        let asset = AVURLAsset(url: location)
        do {
            let playable = try await asset.load(.isPlayable)
            guard playable, !hls || asset.assetCache?.isPlayableOffline == true else { throw PlaybackError.noPlayableStream }
            guard matching(transfer) != nil else { try? FileManager.default.removeItem(at: location); return }
            record.localPath = relativePath
            record.state = .completed; record.progress = 1; record.error = nil
            var local = location; var values = URLResourceValues(); values.isExcludedFromBackup = true
            try? local.setResourceValues(values)
            if library.update(record) { DownloadNotifier.shared.finished(record) }
            else { try? FileManager.default.removeItem(at: location) }
        } catch { try? FileManager.default.removeItem(at: location); failed(transfer, message: "The downloaded media couldn't be verified for offline playback. Retry the download.") }
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, AVAssetDownloadDelegate, @unchecked Sendable {
    weak var owner: DownloadManager?
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let transfer = downloadTask.taskDescription
        guard let transfer, let rawID = transfer.split(separator: ":").first, let id = UUID(uuidString: String(rawID)),
              let http = downloadTask.response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            Task { @MainActor in self.owner?.failed(transfer, message: "The server refused the download. Retry to refresh the stream.") }; return
        }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DriftLoom/Media")
        let destination = directory.appendingPathComponent(id.uuidString + "-" + UUID().uuidString + (TransferParts.part(transfer).map { "." + $0 + ".part" } ?? "") + (TransferParts.part(transfer) == TransferParts.audio ? ".m4a" : ".mp4"))
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: location, to: destination)
            Task { @MainActor in await self.owner?.completed(transfer, location: destination, hls: false) }
        } catch { Task { @MainActor in self.owner?.failed(transfer, message: "The downloaded file couldn't be saved. Check available storage.") } }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let value = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in self.owner?.progress(downloadTask.taskDescription, value: value) }
    }
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didFinishDownloadingTo location: URL) {
        Task { @MainActor in await self.owner?.completed(assetDownloadTask.taskDescription, location: location, hls: true) }
    }
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didLoad timeRange: CMTimeRange, totalTimeRangesLoaded loadedTimeRanges: [NSValue], timeRangeExpectedToLoad: CMTimeRange) {
        let duration = timeRangeExpectedToLoad.duration.seconds
        guard duration.isFinite, duration > 0 else { return }
        let loaded = loadedTimeRanges.reduce(0) { $0 + $1.timeRangeValue.duration.seconds }
        Task { @MainActor in self.owner?.progress(assetDownloadTask.taskDescription, value: loaded / duration) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { Task { @MainActor in self.owner?.failed(task.taskDescription, message: error.localizedDescription) } }
    }
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        guard let id = session.configuration.identifier else { return }
        Task { @MainActor in self.owner?.finishedEvents(identifier: id) }
    }
}

final class DownloadAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        DownloadNotifier.shared.install()
        if #available(iOS 16.1, *) { DownloadActivityController.shared.start() }
        return true
    }
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        DownloadManager.shared.backgroundEvents(identifier: identifier, completion: completionHandler)
    }
}
