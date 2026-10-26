// SPDX-License-Identifier: GPL-3.0-or-later
import ActivityKit
import DriftLoomActivity
import SwiftUI
import WidgetKit

@main
struct DriftLoomWidgets: WidgetBundle {
    var body: some Widget { DownloadActivityWidget() }
}

/// Download progress on the lock screen and in the Dynamic Island.
struct DownloadActivityWidget: Widget {
    private static let accent = Color(red: 205 / 255, green: 32 / 255, blue: 31 / 255)
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DownloadActivityAttributes.self) { context in
            LockScreenView(summary: context.state).padding(16).activityBackgroundTint(Color.black.opacity(0.75)).activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: symbol(context.state)).foregroundColor(Self.accent).font(.title2) }
                DynamicIslandExpandedRegion(.trailing) { Text(percent(context.state)).font(.caption.monospacedDigit()) }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.title).font(.subheadline).lineLimit(1)
                        ProgressView(value: context.state.progress ?? 0).tint(Self.accent)
                        // The percentage is already top right; only show status that adds something.
                        if context.state.progress == nil || context.state.count > 1 || context.state.state != .active {
                            Text(context.state.detail).font(.caption2).foregroundColor(.secondary)
                        }
                    }.padding(.horizontal, 8)
                }
            } compactLeading: {
                Image(systemName: symbol(context.state)).foregroundColor(Self.accent)
            } compactTrailing: {
                if let progress = context.state.progress, context.state.state == .active {
                    ProgressView(value: progress).progressViewStyle(.circular).tint(Self.accent).frame(width: 18, height: 18)
                } else { Text(percent(context.state)).font(.caption2.monospacedDigit()) }
            } minimal: {
                Image(systemName: symbol(context.state)).foregroundColor(Self.accent)
            }
        }
    }
    private func symbol(_ summary: DownloadSummary) -> String {
        switch summary.state { case .active: return "arrow.down.circle"; case .finished: return "checkmark.circle"; case .failed: return "exclamationmark.circle" }
    }
    private func percent(_ summary: DownloadSummary) -> String {
        summary.progress.map { "\(Int(($0 * 100).rounded(.down)))%" } ?? "…"
    }

    private struct LockScreenView: View {
        let summary: DownloadSummary
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: summary.state == .failed ? "exclamationmark.circle.fill" : summary.state == .finished ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                        .foregroundColor(DownloadActivityWidget.accent)
                    Text("DriftLoom").font(.caption.weight(.semibold)).foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Text(summary.detail).font(.caption.monospacedDigit()).foregroundColor(.white.opacity(0.8))
                }
                Text(summary.title).font(.headline).foregroundColor(.white).lineLimit(2)
                ProgressView(value: summary.progress ?? 0).tint(DownloadActivityWidget.accent)
            }
        }
    }
}
