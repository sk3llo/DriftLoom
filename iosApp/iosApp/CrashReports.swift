// SPDX-License-Identifier: GPL-3.0-or-later
import DriftLoomPlayback
import MetricKit
import SwiftUI

/// MetricKit has its own `DiagnosticReport` since the iOS 27 SDK; in this file the name means DriftLoom's.
private typealias DiagnosticReport = DriftLoomPlayback.DiagnosticReport

/// Receives crash and hang reports from iOS. MetricKit delivers them on the launch after they happen (iOS 15),
/// and nothing leaves the device unless the person chooses to report one.
final class CrashReportCollector: NSObject, MXMetricManagerSubscriber {
    static let shared = CrashReportCollector()

    func start() {
        MXMetricManager.shared.add(self)
        NSLog("DriftLoomDiagnostics: subscribed to MetricKit, %d past payloads", MXMetricManager.shared.pastDiagnosticPayloads.count)
        // Payloads iOS delivered before this launch subscribed.
        receive(MXMetricManager.shared.pastDiagnosticPayloads)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) { receive(payloads) }

    private func receive(_ payloads: [MXDiagnosticPayload]) {
        let reports = payloads.flatMap { DiagnosticReport.reports(fromPayload: $0.jsonRepresentation()) }
        guard !reports.isEmpty else { return }
        NSLog("DriftLoomDiagnostics: received %@", reports.map(\.summary).joined(separator: "; "))
        Task { @MainActor in DiagnosticInbox.shared.add(reports) }
    }
}

/// On launch, offers the newest unreported crash or hang once: report it on GitHub, copy it, or let it go.
struct CrashReportPrompt: ViewModifier {
    @ObservedObject var inbox: DiagnosticInbox
    @State private var shown: DiagnosticReport?
    @State private var offeredThisLaunch = false
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    private static let appVersion = ProblemReport.environment.first?.value ?? "?"
    /// UI tests end the app while it's on screen, which would look like a crash; only --exit-check-smoke tests that.
    private static var notesExits: Bool {
#if DEBUG || DRIFTLOOM_DEVICE_TESTING
        let arguments = ProcessInfo.processInfo.arguments
        return !arguments.contains("--library-smoke-run") || arguments.contains("--exit-check-smoke")
#else
        return true
#endif
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                if Self.notesExits { inbox.checkLastRun(appVersion: Self.appVersion) }
                offer()
            }
            .onChange(of: scenePhase) { phase in if Self.notesExits { inbox.noteForeground(phase == .active, appVersion: Self.appVersion) } }
            .onChange(of: inbox.pending) { _ in offer() }
            .alert(shown?.kind == .hang ? "DriftLoom stopped responding" : "DriftLoom quit unexpectedly",
                   isPresented: Binding(get: { shown != nil }, set: { if !$0 { shown = nil } }), presenting: shown) { report in
                Button("Report on GitHub") { openURL(report.problemReport.issueURL(environment: ProblemReport.environment)); inbox.finish(report) }
                Button("Copy details") { report.problemReport.copyToPasteboard(); inbox.finish(report) }
                Button("Don't report", role: .cancel) { inbox.finish(report) }
            } message: { report in
                Text("This happened \(report.date.formatted(date: .abbreviated, time: .shortened)). Reporting it as a GitHub issue helps get it fixed. You'll see the report before anything is sent, and it holds only the technical details, not your library.")
            }
    }

    private func offer() {
        guard !offeredThisLaunch, shown == nil, let newest = inbox.pending.first else { return }
        offeredThisLaunch = true
        // Let launch settle so the alert doesn't race the first screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { shown = newest }
    }
}

#if DEBUG || DRIFTLOOM_DEVICE_TESTING
/// --diagnostic-smoke: offer a sample crash report. --crash-smoke: crash on purpose, so MetricKit
/// reports a real one on the next launch.
@MainActor func runDiagnosticSmoke() {
    let arguments = ProcessInfo.processInfo.arguments
    if arguments.contains("--diagnostic-smoke") {
        let sample = """
        {"timeStampEnd":"2026-10-28 10:59:00 +0000","crashDiagnostics":[{"diagnosticMetaData":{"appVersion":"1.0","appBuildVersion":"1",
        "osVersion":"iPhone OS 15.8.2 (19H384)","deviceType":"iPhone9,3","exceptionType":6,"signal":5},"callStackTree":{"callStacks":[{"threadAttributed":true,
        "callStackRootFrames":[{"binaryName":"DriftLoom","binaryUUID":"SAMPLE","offsetIntoBinaryTextSegment":4096}]}]}}]}
        """
        DiagnosticInbox.shared.add(DiagnosticReport.reports(fromPayload: Data(sample.utf8)).map {
            DiagnosticReport(id: UUID().uuidString, kind: $0.kind, date: $0.date, summary: $0.summary, details: $0.details, frames: $0.frames)
        })
    }
    // --diagnostic-smoke-clear: drop pending reports left by device checks.
    if arguments.contains("--diagnostic-smoke-clear") {
        DiagnosticInbox.shared.pending.forEach(DiagnosticInbox.shared.finish)
        DiagnosticInbox.shared.noteForeground(false, appVersion: "")
    }
    if arguments.contains("--crash-smoke") {
        NSLog("DriftLoomDiagnostics: crashing on purpose")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { fatalError("DriftLoom crash smoke") }
    }
}
#endif
