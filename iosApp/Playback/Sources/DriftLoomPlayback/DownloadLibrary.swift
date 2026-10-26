// SPDX-License-Identifier: GPL-3.0-or-later
import Combine
import Foundation
import YouTubeKit

public struct DownloadChoice: Identifiable, Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case hls, video, audio }
    public let id: String
    public let name: String
    public let kind: Kind
    public init(id: String, name: String, kind: Kind) { self.id = id; self.name = name; self.kind = kind }
}
public struct DownloadSource: Sendable {
    public let url: URL
    public let choice: DownloadChoice
}
public struct YouTubeDownloadResolver: Sendable {
    public init() {}
    public func choices(videoID: String) async throws -> [DownloadChoice] {
        do { return try await findChoices(videoID: videoID) } catch { throw PlaybackError.readable(error) }
    }
    private func findChoices(videoID: String) async throws -> [DownloadChoice] {
        let request = try VideoRequest(input: videoID)
        let video = YouTube(videoID: request.videoID, methods: [.local])
        var choices: [DownloadChoice] = []
        if (try? await video.livestreams.contains(where: { $0.streamType == .hls })) == true {
            choices.append(DownloadChoice(id: "hls", name: "Video · automatic quality (HLS)", kind: .hls))
        }
        if let streams = try? await video.streams {
            choices += streams.filter { $0.isNativelyPlayable && ($0.includesVideoAndAudioTrack || !$0.includesVideoTrack) }
                .compactMap { stream in
                    guard let id = Self.formatID(stream) else { return nil }
                    return DownloadChoice(id: id, name: stream.includesVideoTrack ? "Video · \(stream.videoResolution ?? 0)p" : "Audio · \((stream.bitrate ?? 0) / 1000) kbps", kind: stream.includesVideoTrack ? .video : .audio)
                }
        }
        try Task.checkCancellation()
        guard !choices.isEmpty else { throw PlaybackError.noPlayableStream }
        return choices
    }
    private static func formatID(_ stream: YouTubeKit.Stream) -> String? {
        URLComponents(url: stream.url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "itag" }?.value
    }
    public func source(videoID: String, choice: DownloadChoice) async throws -> DownloadSource {
        do { return try await findSource(videoID: videoID, choice: choice) } catch { throw PlaybackError.readable(error) }
    }
    private func findSource(videoID: String, choice: DownloadChoice) async throws -> DownloadSource {
        let request = try VideoRequest(input: videoID)
        let video = YouTube(videoID: request.videoID, methods: [.local])
        if choice.kind == .hls, let hls = try await video.livestreams.first(where: { $0.streamType == .hls }) {
            return DownloadSource(url: hls.url, choice: choice)
        }
        guard let stream = try await video.streams.first(where: { Self.formatID($0) == choice.id && $0.isNativelyPlayable && ($0.includesVideoAndAudioTrack || !$0.includesVideoTrack) }) else { throw PlaybackError.noPlayableStream }
        return DownloadSource(url: stream.url, choice: choice)
    }
}

public struct DownloadRecord: Codable, Identifiable, Equatable, Sendable {
    public enum State: String, Codable, Sendable { case preparing, downloading, completed, cancelled, failed }
    public let id: UUID
    public let item: BrowseItem
    public let choice: DownloadChoice
    public var transferID: UUID?
    public var state: State
    public var progress: Double
    public var localPath: String?
    public var error: String?
    public var network: DownloadNetwork?
    public var waitingForNetwork: Bool?
    /// Requested subtitle language (base code) and whether an automatic track is acceptable.
    public var subtitleLanguage: String?
    public var subtitlePath: String?
    public var subtitleError: String?
    public init(item: BrowseItem, choice: DownloadChoice, subtitleLanguage: String? = nil) {
        id = UUID(); self.item = item; self.choice = choice; state = .preparing; progress = 0; self.subtitleLanguage = subtitleLanguage
    }
}

/// Only job metadata is persisted. Signed media URLs and cookies stay in memory.
@MainActor
public final class DownloadLibrary: ObservableObject {
    @Published public private(set) var records: [DownloadRecord] = []
    @Published public private(set) var error: String?
    @Published public private(set) var isWritable = true
    public let fileURL: URL
    private struct Document: Codable { var version = 1; var records: [DownloadRecord] }
    public init(fileURL: URL) {
        self.fileURL = fileURL
        do {
            let data = try Data(contentsOf: fileURL)
            guard data.count < 8_000_000 else { throw CocoaError(.fileReadCorruptFile) }
            let document = try JSONDecoder().decode(Document.self, from: data)
            guard document.version == 1, document.records.count <= 5000,
                  Set(document.records.map(\.id)).count == document.records.count,
                  document.records.allSatisfy(Self.valid) else { throw CocoaError(.fileReadCorruptFile) }
            records = document.records
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile { }
        catch { isWritable = false; self.error = "Your download list couldn't be read and has been left untouched." }
    }
    private static func valid(_ record: DownloadRecord) -> Bool {
        guard record.item.kind == .video, (try? VideoRequest(input: record.item.contentID).videoID) == record.item.contentID,
              record.progress.isFinite, (0...1).contains(record.progress) else { return false }
        for path in [record.localPath, record.subtitlePath].compactMap({ $0 }) {
            guard !path.hasPrefix("/"), !path.split(separator: "/").contains(".."), !path.contains(":") else { return false }
        }
        if let language = record.subtitleLanguage, language.isEmpty || language.count > 20 { return false }
        return true
    }
    @discardableResult public func add(_ record: DownloadRecord) -> Bool {
        guard Self.valid(record), records.count < 5000, !records.contains(where: { $0.id == record.id }) else { return false }
        return save([record] + records)
    }
    @discardableResult public func update(_ record: DownloadRecord) -> Bool {
        guard Self.valid(record), let index = records.firstIndex(where: { $0.id == record.id }) else { return false }
        var next = records; next[index] = record; return save(next)
    }
    @discardableResult public func remove(_ id: UUID) -> Bool { save(records.filter { $0.id != id }) }
    public func dismissError() { error = nil }
    private func save(_ records: [DownloadRecord]) -> Bool {
        guard isWritable else { return false }
        do {
            let data = try JSONEncoder().encode(Document(records: records))
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            var options: Data.WritingOptions = .atomic
#if os(iOS)
            options.insert(.completeFileProtectionUntilFirstUserAuthentication)
#endif
            try data.write(to: fileURL, options: options)
            self.records = records; error = nil; return true
        } catch { self.error = "Your download list couldn't be saved. Previous data is unchanged."; return false }
    }
}

public enum DownloadPaths {
    /// Normalize both sides before deriving a relative path: iOS may report /var and /private/var aliases.
    public static func relativePath(for location: URL, home: URL) -> String? {
        guard location.isFileURL, home.isFileURL else { return nil }
        let root = home.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        let path = location.standardizedFileURL.resolvingSymlinksInPath().path
        guard path.hasPrefix(root) else { return nil }
        return String(path.dropFirst(root.count))
    }
}
