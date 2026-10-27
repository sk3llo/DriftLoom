// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

/// One running download as the progress UIs see it.
public struct ActiveDownload: Equatable, Sendable {
    public enum Phase: String, Codable, Sendable { case waiting, preparing, downloading }
    public let id: UUID
    public let title: String
    public let progress: Double
    public let phase: Phase
    public init(id: UUID, title: String, progress: Double, phase: Phase) {
        self.id = id; self.title = title; self.progress = max(0, min(1, progress.isFinite ? progress : 0)); self.phase = phase
    }
}

/// What the in-app strip and the Live Activity show: the first active download and the overall progress.
public struct DownloadSummary: Codable, Hashable, Sendable {
    public enum State: String, Codable, Sendable { case active, finished, failed }
    public var title: String
    public var detail: String
    /// 0…1 across all active downloads; nil while nothing has started transferring.
    public var progress: Double?
    public var count: Int
    public var state: State
    public init(title: String, detail: String, progress: Double?, count: Int, state: State) {
        self.title = title; self.detail = detail; self.progress = progress; self.count = count; self.state = state
    }

    /// nil when nothing is downloading.
    public static func active(_ downloads: [ActiveDownload]) -> DownloadSummary? {
        guard let first = downloads.first else { return nil }
        let transferring = downloads.filter { $0.phase == .downloading }
        let progress = transferring.isEmpty ? nil : downloads.map(\.progress).reduce(0, +) / Double(downloads.count)
        let status: String
        switch first.phase {
        case .waiting: status = L("Waiting for network")
        case .preparing: status = L("Preparing")
        case .downloading: status = "\(Int((first.progress * 100).rounded(.down)))%"
        }
        let more = downloads.count > 1 ? " · " + L("\(downloads.count - 1) more") : ""
        return DownloadSummary(title: first.title, detail: status + more, progress: progress, count: downloads.count, state: .active)
    }
    public static func finished(_ title: String, failed: Bool) -> DownloadSummary {
        DownloadSummary(title: title, detail: failed ? L("Download failed") : L("Downloaded"), progress: failed ? nil : 1, count: 0,
                        state: failed ? .failed : .finished)
    }
}

#if canImport(ActivityKit) && os(iOS)
@available(iOS 16.1, *)
public struct DownloadActivityAttributes: ActivityAttributes {
    public typealias ContentState = DownloadSummary
    public init() {}
}
#endif
