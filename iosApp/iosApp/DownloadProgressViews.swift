// SPDX-License-Identifier: GPL-3.0-or-later
#if canImport(ActivityKit)
import ActivityKit
#endif
import Combine
import DriftLoomPlayback
import SwiftUI

/// A thin bar above the mini-player while downloads run; tapping opens Downloads.
struct DownloadProgressStrip: View {
    @ObservedObject private var manager = DownloadManager.shared
    var body: some View {
        if let summary = DownloadSummary.of(manager.records) {
            Button { NotificationCenter.default.post(name: .driftLoomOpenDownloads, object: nil) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle").foregroundColor(AppStyle.accent)
                        Text(summary.title).font(.caption.weight(.medium)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(summary.detail).font(.caption2.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if let progress = summary.progress { ProgressView(value: progress).tint(AppStyle.accent) }
                    else { ProgressView(value: 0).tint(.secondary) }
                }.padding(.horizontal, 12).padding(.vertical, 6).background(Color(.secondarySystemBackground))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Downloading \(summary.title), \(summary.detail)")
            .accessibilityIdentifier("downloadStrip")
        }
    }
}

#if canImport(ActivityKit)
/// Mirrors running downloads into one Live Activity (lock screen and Dynamic Island) on iOS 16.1+.
/// Background transfers can't wake the app for every progress step, so the activity shows the last
/// known progress while the app is suspended and is finished when iOS reports the transfer's end.
@available(iOS 16.1, *)
@MainActor
final class DownloadActivityController {
    static let shared = DownloadActivityController()
    private var activity: Activity<DownloadActivityAttributes>?
    private var shown: DownloadSummary?
    private var lastTitle = ""
    private var subscription: AnyCancellable?

    func start() {
        // Activities left over from a previous launch would otherwise stay on the lock screen.
        for stale in Activity<DownloadActivityAttributes>.activities { Task { await stale.end(dismissalPolicy: .immediate) } }
        subscription = DownloadManager.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
    }

    private func refresh() {
        let records = DownloadManager.shared.records
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if let summary = DownloadSummary.of(records) {
            lastTitle = summary.title
            if let activity {
                guard changed(summary) else { return }
                shown = summary
                Task { await activity.update(using: summary) }
            } else {
                shown = summary
                activity = try? Activity.request(attributes: DownloadActivityAttributes(), contentState: summary, pushType: nil)
            }
        } else if let activity {
            // Show how the last download ended for a moment, then remove the activity.
            let failed = records.contains { $0.item.title == lastTitle && $0.state == .failed }
            let final = DownloadSummary.finished(lastTitle, failed: failed)
            self.activity = nil; shown = nil
            Task { await activity.end(using: final, dismissalPolicy: .after(Date().addingTimeInterval(8))) }
        }
    }
    /// Skip updates for progress changes too small to see.
    private func changed(_ summary: DownloadSummary) -> Bool {
        guard let shown else { return true }
        if summary.title != shown.title || summary.count != shown.count || (summary.progress == nil) != (shown.progress == nil) { return true }
        if summary.detail != shown.detail, summary.progress == nil { return true }
        return abs((summary.progress ?? 0) - (shown.progress ?? 0)) >= 0.03
    }
}
#endif
