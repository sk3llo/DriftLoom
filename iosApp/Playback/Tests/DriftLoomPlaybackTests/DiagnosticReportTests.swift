// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import DriftLoomPlayback

final class DiagnosticReportTests: XCTestCase {
    /// Shaped like MXDiagnosticPayload.jsonRepresentation() on iOS 15.
    static let payload = """
    {"timeStampBegin":"2026-10-28 10:00:00 +0000","timeStampEnd":"2026-10-28 10:59:00 +0000",
     "crashDiagnostics":[{"version":"1.0.0","diagnosticMetaData":{"appVersion":"1.0","appBuildVersion":"42","osVersion":"iPhone OS 15.8.2 (19H384)",
       "deviceType":"iPhone9,3","platformArchitecture":"arm64","exceptionType":6,"exceptionCode":1,"signal":5,
       "terminationReason":"Namespace SIGNAL, Code 5 Trace/BPT trap: 5"},
      "callStackTree":{"callStackPerThread":true,"callStacks":[
        {"threadAttributed":false,"callStackRootFrames":[{"binaryName":"libsystem_kernel.dylib","binaryUUID":"K","offsetIntoBinaryTextSegment":1,"address":1,"sampleCount":1}]},
        {"threadAttributed":true,"callStackRootFrames":[{"binaryName":"libswiftCore.dylib","binaryUUID":"S-UUID","offsetIntoBinaryTextSegment":4096,"address":2,"sampleCount":1,
          "subFrames":[{"binaryName":"DriftLoom","binaryUUID":"D-UUID","offsetIntoBinaryTextSegment":170812,"address":3,"sampleCount":1,
            "subFrames":[{"binaryName":"DriftLoom","binaryUUID":"D-UUID","offsetIntoBinaryTextSegment":4660,"address":4,"sampleCount":1}]}]}]}]}}],
     "hangDiagnostics":[
       {"diagnosticMetaData":{"appVersion":"1.0","appBuildVersion":"42","hangDuration":"3.25 sec"},"callStackTree":{"callStacks":[{"threadAttributed":true,"callStackRootFrames":[{"binaryName":"DriftLoom","binaryUUID":"D-UUID","offsetIntoBinaryTextSegment":255}]}]}},
       {"diagnosticMetaData":{"hangDuration":"400 ms"},"callStackTree":{"callStacks":[]}}]}
    """

    func testCrashAndLongHangAreSummarized() throws {
        let reports = DiagnosticReport.reports(fromPayload: Data(Self.payload.utf8))
        XCTAssertEqual(reports.map(\.kind), [.crash, .hang], "The 0.4 s hang is too brief to ask about")
        let crash = reports[0]
        XCTAssertEqual(crash.summary, "EXC_BREAKPOINT (SIGTRAP)")
        XCTAssertEqual(crash.frames, ["libswiftCore.dylib +0x1000", "DriftLoom +0x29b3c", "DriftLoom +0x1234"], "The crashed thread, innermost first")
        XCTAssertTrue(crash.details.contains(.init("Crashed version", "1.0 (42)")))
        XCTAssertTrue(crash.details.contains(.init("Crashed on", "iPhone OS 15.8.2 (19H384), iPhone9,3")))
        XCTAssertTrue(crash.details.contains(.init("Binary", "DriftLoom D-UUID")), "The UUID matches the dSYM for symbolication")
        XCTAssertTrue(crash.details.contains(.init("Termination", "Namespace SIGNAL, Code 5 Trace/BPT trap: 5")))
        XCTAssertEqual(reports[1].summary, "Hang 3.2 s")

        let issue = crash.problemReport
        XCTAssertEqual(issue.title, "[iOS] Crash: EXC_BREAKPOINT (SIGTRAP) in DriftLoom +0x29b3c")
        XCTAssertTrue(issue.body(environment: []).contains("DriftLoom +0x29b3c"))
    }

    func testDurationsAndNames() {
        XCTAssertEqual(DiagnosticReport.seconds("250 ms"), 0.25)
        XCTAssertEqual(DiagnosticReport.seconds("2 sec"), 2)
        XCTAssertEqual(DiagnosticReport.exceptionName(1), "EXC_BAD_ACCESS")
        XCTAssertEqual(DiagnosticReport.signalName(11), "SIGSEGV")
        XCTAssertNil(DiagnosticReport.signalName(0))
        XCTAssertTrue(DiagnosticReport.reports(fromPayload: Data("not json".utf8)).isEmpty)
    }

    @MainActor func testEndingWhileOnScreenIsNotedAndReplacedByDetails() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let inbox = DiagnosticInbox(file: nil)
        // Noted shortly before the sample payload's crash.
        let crashTime = try XCTUnwrap(DiagnosticReport.reports(fromPayload: Data(Self.payload.utf8)).first?.date).addingTimeInterval(-600)
        // Going to the background clears the note, so a normal exit isn't reported.
        inbox.noteForeground(true, now: crashTime, appVersion: "1.0 (1)", defaults: defaults)
        inbox.noteForeground(false, appVersion: "1.0 (1)", defaults: defaults)
        inbox.checkLastRun(appVersion: "1.0 (1)", defaults: defaults)
        XCTAssertTrue(inbox.pending.isEmpty)
        // Ending while on screen leaves it set.
        inbox.noteForeground(true, now: crashTime, appVersion: "1.0 (1)", defaults: defaults)
        inbox.checkLastRun(appVersion: "1.0 (1)", defaults: defaults)
        XCTAssertEqual(inbox.pending.map(\.summary), ["Quit while in use (no crash details from iOS)"])
        XCTAssertEqual(inbox.pending.first?.problemReport.title, "[iOS] Crash: Quit while in use (no crash details from iOS)")
        inbox.checkLastRun(appVersion: "1.0 (1)", defaults: defaults)
        XCTAssertEqual(inbox.pending.count, 1, "Checked once")
        // MetricKit's report for it arrives later and takes its place.
        inbox.add(DiagnosticReport.reports(fromPayload: Data(Self.payload.utf8)).filter { $0.kind == .crash })
        XCTAssertEqual(inbox.pending.map(\.summary), ["EXC_BREAKPOINT (SIGTRAP)"])
    }

    @MainActor func testInboxOffersEachReportOnceAcrossLaunches() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file) }
        let reports = DiagnosticReport.reports(fromPayload: Data(Self.payload.utf8))
        let inbox = DiagnosticInbox(file: file)
        inbox.add(reports); inbox.add(reports)
        XCTAssertEqual(inbox.pending.count, 2, "The same payload delivered twice is offered once")
        inbox.finish(inbox.pending[0])
        let relaunched = DiagnosticInbox(file: file)
        XCTAssertEqual(relaunched.pending.count, 1, "Pending reports survive a relaunch")
        relaunched.add(reports)
        XCTAssertEqual(relaunched.pending.count, 1, "A reported or dismissed one never comes back")
    }
}
