// SPDX-License-Identifier: GPL-3.0-or-later
@_exported import DriftLoomActivity
import Foundation

public extension DownloadRecord {
    /// This job as a running download, or nil when it isn't in progress.
    var activeDownload: ActiveDownload? {
        let phase: ActiveDownload.Phase
        switch state {
        case .preparing: phase = waitingForNetwork == true ? .waiting : .preparing
        case .downloading: phase = .downloading
        case .completed, .cancelled, .failed: return nil
        }
        return ActiveDownload(id: id, title: item.title, progress: progress, phase: phase)
    }
}

public extension DownloadSummary {
    /// Summary of the records still in progress, newest first as the download list shows them.
    static func of(_ records: [DownloadRecord]) -> DownloadSummary? { active(records.compactMap(\.activeDownload)) }
}
