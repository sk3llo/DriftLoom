// SPDX-License-Identifier: GPL-3.0-or-later
import AVFoundation
import Combine
import DriftLoomPlayback
import Foundation
import UIKit

@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()
    static let fileSessionID = "net.driftloom.app.download.files"
    static let hlsSessionID = "net.driftloom.app.download.hls"
    let library: DownloadLibrary
    private let bridge: DownloadDelegate
    private var files: URLSession!
    private var hls: AVAssetDownloadURLSession!
    private var subscriptions = Set<AnyCancellable>()
    private var preparations: [UUID: Task<Void, Never>] = [:]
    private var completions: [String: () -> Void] = [:]
    private var connected = false
    private var validations = 0
    private var finishedSessions = Set<String>()
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
        configuration.sessionSendsLaunchEvents = true; configuration.isDiscretionary = false
        files = URLSession(configuration: configuration, delegate: bridge, delegateQueue: nil)
        let hlsConfiguration = URLSessionConfiguration.background(withIdentifier: Self.hlsSessionID + suffix)
        hlsConfiguration.sessionSendsLaunchEvents = true; hlsConfiguration.isDiscretionary = false
        hls = AVAssetDownloadURLSession(configuration: hlsConfiguration, assetDownloadDelegate: bridge, delegateQueue: nil)
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
        let fileTasks = await allTasks(files)
        let hlsTasks = await allTasks(hls)
        let tasks = fileTasks + hlsTasks
        let descriptions = Set(tasks.compactMap(\.taskDescription))
        for task in tasks where matching(task.taskDescription) == nil { task.cancel() }
        for var record in records where record.state == .preparing || record.state == .downloading {
            if !descriptions.contains(description(record)) {
                record.state = .failed; record.error = "Download interrupted. Retry to obtain a fresh stream."
                _ = library.update(record)
            }
        }
        connected = true; reconnecting = false
    }
    @discardableResult func start(item: BrowseItem, choice: DownloadChoice) -> UUID? {
        guard connected, library.isWritable else { return nil }
        let record = DownloadRecord(item: item, choice: choice)
        guard library.add(record) else { return nil }
        retry(record.id); return record.id
    }
    func retry(_ id: UUID) {
        guard connected, var record = records.first(where: { $0.id == id }), record.state != .completed else { return }
        preparations[id]?.cancel()
        record.transferID = UUID(); record.state = .preparing; record.error = nil; record.progress = 0; record.localPath = nil
        guard library.update(record) else { return }
        let transfer = description(record)
        preparations[id] = Task { [weak self] in
            do {
                let source = try await YouTubeDownloadResolver().source(videoID: record.item.contentID, choice: record.choice)
                try Task.checkCancellation()
                guard let self, var current = self.matching(transfer), current.state == .preparing else { return }
                let task: URLSessionTask
                if source.choice.kind == .hls {
                    let asset = AVURLAsset(url: source.url)
                    let duration = try await asset.load(.duration)
                    try Task.checkCancellation()
                    guard duration.isNumeric, duration.seconds > 0 else { throw BrowseError.unavailable("Live streams cannot be saved as offline downloads.") }
                    guard self.matching(transfer)?.state == .preparing else { return }
                    guard let download = self.hls.makeAssetDownloadTask(asset: asset, assetTitle: record.item.title, assetArtworkData: nil, options: nil) else { throw PlaybackError.noPlayableStream }
                    task = download
                } else { task = self.files.downloadTask(with: source.url) }
                task.taskDescription = transfer; current.state = .downloading
                guard self.library.update(current) else { task.cancel(); return }
                task.resume()
            } catch is CancellationError { }
            catch { self?.failed(transfer, message: error.localizedDescription) }
            if self?.records.first(where: { $0.id == id })?.transferID == record.transferID { self?.preparations[id] = nil }
        }
    }
    func cancel(_ id: UUID) {
        guard var record = records.first(where: { $0.id == id }), record.state != .completed else { return }
        preparations[id]?.cancel(); preparations[id] = nil
        let transfer = description(record)
        record.state = .cancelled; record.error = nil; record.transferID = nil
        guard library.update(record) else { return }
        Task {
            let tasks = await allTasks(files)
            let assets = await allTasks(hls)
            for task in tasks + assets where task.taskDescription == transfer { task.cancel() }
        }
    }
    func remove(_ id: UUID) {
        guard let record = records.first(where: { $0.id == id }) else { return }
        if record.state != .completed { cancel(id) }
        if let url = localURL(record) {
            do { try FileManager.default.removeItem(at: url) }
            catch { return }
        }
        _ = library.remove(id)
    }
    func localURL(_ record: DownloadRecord) -> URL? {
        guard record.state == .completed, let path = record.localPath else { return nil }
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        let url = home.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        guard url.path.hasPrefix(home.path + "/"),
              (path.hasPrefix("Library/Application Support/DriftLoom/Media/") || (path.hasPrefix("Library/com.apple.UserManagedAssets.") && path.split(separator: "/").count == 3 && url.pathExtension == "movpkg")),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        if record.choice.kind == .hls, AVURLAsset(url: url).assetCache?.isPlayableOffline != true { return nil }
        return url
    }
    private func description(_ record: DownloadRecord) -> String { record.id.uuidString + ":" + (record.transferID?.uuidString ?? "") }
    private func matching(_ transfer: String?) -> DownloadRecord? {
        guard let transfer else { return nil }
        return records.first { description($0) == transfer && ($0.state == .preparing || $0.state == .downloading) }
    }
    fileprivate func progress(_ transfer: String?, value: Double) {
        guard value.isFinite, var record = matching(transfer) else { return }
        let progress = max(0, min(1, value))
        guard progress - record.progress >= 0.02 else { return }
        record.progress = progress; _ = library.update(record)
    }
    fileprivate func failed(_ transfer: String?, message: String) {
        guard var record = matching(transfer) else { return }
        record.state = .failed; record.error = message; _ = library.update(record)
    }
    fileprivate func completed(_ transfer: String?, location: URL, hls: Bool) async {
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
            if !library.update(record) { try? FileManager.default.removeItem(at: location) }
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
        let destination = directory.appendingPathComponent(id.uuidString + "-" + UUID().uuidString + ".mp4")
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
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        DownloadManager.shared.backgroundEvents(identifier: identifier, completion: completionHandler)
    }
}
