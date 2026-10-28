// SPDX-License-Identifier: GPL-3.0-or-later
import Combine
import Foundation

/// A crash or hang that iOS reported through MetricKit, summarized for a GitHub issue. MetricKit hands these
/// over on the launch after they happen; DriftLoom keeps them until the person reports or dismisses them.
public struct DiagnosticReport: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case crash, hang }
    public let id: String
    public let kind: Kind
    public let date: Date
    /// Such as "EXC_BREAKPOINT (SIGTRAP)" or "Hang 3.2 s".
    public let summary: String
    public let details: [ProblemReport.Detail]
    /// The crashed (or main) thread, innermost first: "DriftLoom +0x1a2b3c". Symbolicated later against the dSYM.
    public let frames: [String]

    public init(id: String, kind: Kind, date: Date, summary: String, details: [ProblemReport.Detail], frames: [String]) {
        self.id = id; self.kind = kind; self.date = date; self.summary = summary; self.details = details; self.frames = frames
    }

    public var problemReport: ProblemReport {
        var text = summary
        if !frames.isEmpty { text += "\n\n" + frames.joined(separator: "\n") }
        // The first frame in DriftLoom's own code says most about where it happened.
        let own = frames.first { $0.hasPrefix("DriftLoom") }
        return ProblemReport(area: kind == .crash ? "Crash" : "Hang", error: text, context: details,
                             headline: summary + (own.map { " in \($0)" } ?? ""))
    }

    /// The app ended while on screen and iOS gave no details: likely a crash, or iOS ending it for not responding.
    public static func unexpectedExit(at date: Date, appVersion: String) -> DiagnosticReport {
        DiagnosticReport(id: "exit|\(Int(date.timeIntervalSince1970))", kind: .crash, date: date,
                         summary: "Quit while in use (no crash details from iOS)",
                         details: [.init("When", ISO8601DateFormatter().string(from: date)), .init("Crashed version", appVersion)], frames: [])
    }
    var isUnexpectedExit: Bool { id.hasPrefix("exit|") }

    /// Hangs shorter than this aren't worth asking about; iOS reports many brief ones.
    public static let minimumHang: TimeInterval = 2

    /// Reports from an `MXDiagnosticPayload.jsonRepresentation()`.
    public static func reports(fromPayload data: Data) -> [DiagnosticReport] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let date = (root["timeStampEnd"] as? String).flatMap(parseDate) ?? Date()
        var reports: [DiagnosticReport] = []
        for crash in root["crashDiagnostics"] as? [[String: Any]] ?? [] {
            let meta = crash["diagnosticMetaData"] as? [String: Any] ?? [:]
            var summary = [exceptionName(meta["exceptionType"]), signalName(meta["signal"])].compactMap { $0 }
                .enumerated().map { $0.offset == 1 ? "(\($0.element))" : $0.element }.joined(separator: " ")
            if summary.isEmpty { summary = "Crash" }
            var extra: [ProblemReport.Detail] = []
            if let reason = meta["terminationReason"] as? String, !reason.isEmpty { extra.append(.init("Termination", reason)) }
            if let reason = (meta["exceptionReason"] as? [String: Any])?["composedMessage"] as? String { extra.append(.init("Exception", reason)) }
            reports.append(report(.crash, date: date, summary: summary, meta: meta, extra: extra, tree: crash["callStackTree"]))
        }
        for hang in root["hangDiagnostics"] as? [[String: Any]] ?? [] {
            let meta = hang["diagnosticMetaData"] as? [String: Any] ?? [:]
            let duration = seconds(meta["hangDuration"])
            if let duration, duration < minimumHang { continue }
            let summary = duration.map { String(format: "Hang %.1f s", $0) } ?? "Hang"
            reports.append(report(.hang, date: date, summary: summary, meta: meta, extra: [], tree: hang["callStackTree"]))
        }
        return reports
    }

    private static func report(_ kind: Kind, date: Date, summary: String, meta: [String: Any], extra: [ProblemReport.Detail], tree: Any?) -> DiagnosticReport {
        var details: [ProblemReport.Detail] = [.init("When", ISO8601DateFormatter().string(from: date))]
        if let version = meta["appVersion"] as? String { details.append(.init("Crashed version", "\(version) (\(meta["appBuildVersion"] as? String ?? "?"))")) }
        if let os = meta["osVersion"] as? String { details.append(.init("Crashed on", os + ((meta["deviceType"] as? String).map { ", \($0)" } ?? ""))) }
        let (frames, binaries) = stack(tree)
        details += extra
        details += binaries.map { .init("Binary", $0) }
        let id = [kind.rawValue, String(Int(date.timeIntervalSince1970)), summary, frames.prefix(3).joined()].joined(separator: "|")
        return DiagnosticReport(id: id, kind: kind, date: date, summary: summary, details: details, frames: frames)
    }

    /// The attributed thread (the one that crashed), else the first; following each frame's first caller.
    static func stack(_ tree: Any?, limit: Int = 25) -> (frames: [String], binaries: [String]) {
        let stacks = (tree as? [String: Any])?["callStacks"] as? [[String: Any]] ?? []
        guard let thread = stacks.first(where: { $0["threadAttributed"] as? Bool == true }) ?? stacks.first,
              var frame = (thread["callStackRootFrames"] as? [[String: Any]])?.first else { return ([], []) }
        var frames: [String] = [], binaries: [String] = []
        while frames.count < limit {
            let name = frame["binaryName"] as? String ?? "?"
            let offset = (frame["offsetIntoBinaryTextSegment"] as? NSNumber)?.uint64Value ?? 0
            frames.append("\(name) +0x\(String(offset, radix: 16))")
            if let uuid = frame["binaryUUID"] as? String {
                let entry = "\(name) \(uuid)"
                if !binaries.contains(entry), name.hasPrefix("DriftLoom") || binaries.count < 4 { binaries.append(entry) }
            }
            guard let next = (frame["subFrames"] as? [[String: Any]])?.first else { break }
            frame = next
        }
        return (frames, binaries)
    }

    static func seconds(_ value: Any?) -> TimeInterval? {
        if let number = value as? NSNumber { return number.doubleValue }
        guard let text = value as? String, let number = Double(text.split(separator: " ").first ?? "") else { return nil }
        return text.contains("ms") ? number / 1000 : text.contains("min") ? number * 60 : number
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.date(from: text)
    }

    static func exceptionName(_ value: Any?) -> String? {
        guard let code = (value as? NSNumber)?.intValue else { return nil }
        let names = [1: "EXC_BAD_ACCESS", 2: "EXC_BAD_INSTRUCTION", 3: "EXC_ARITHMETIC", 4: "EXC_EMULATION", 5: "EXC_SOFTWARE",
                     6: "EXC_BREAKPOINT", 10: "EXC_CRASH", 11: "EXC_RESOURCE", 12: "EXC_GUARD"]
        return names[code] ?? "Exception \(code)"
    }
    static func signalName(_ value: Any?) -> String? {
        guard let code = (value as? NSNumber)?.intValue, code != 0 else { return nil }
        let names = [4: "SIGILL", 5: "SIGTRAP", 6: "SIGABRT", 8: "SIGFPE", 9: "SIGKILL", 10: "SIGBUS", 11: "SIGSEGV", 13: "SIGPIPE"]
        return names[code] ?? "signal \(code)"
    }
}

/// Crashes and hangs waiting to be offered for reporting, kept across launches.
@MainActor
public final class DiagnosticInbox: ObservableObject {
    @Published public private(set) var pending: [DiagnosticReport] = []
    /// Oldest first, so the newest survive trimming.
    private var handled: [String] = []
    private let file: URL?

    public static let shared = DiagnosticInbox(file: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("diagnostics.json"))

    struct Saved: Codable { var pending: [DiagnosticReport]; var handled: [String] }

    init(file: URL?) {
        self.file = file
        if let file, let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            pending = saved.pending; handled = saved.handled
        }
    }

    /// Adds reports not seen before, newest first; MetricKit may hand the same payload over again.
    public func add(_ reports: [DiagnosticReport]) {
        let new = reports.filter { !handled.contains($0.id) && !pending.map(\.id).contains($0.id) }
        guard !new.isEmpty else { return }
        // A crash with details from iOS replaces the bare "quit while in use" noted for the same time.
        for crash in new where crash.kind == .crash && !crash.isUnexpectedExit {
            pending.removeAll { $0.isUnexpectedExit && abs($0.date.timeIntervalSince(crash.date)) < 86400 }
        }
        pending = Array((new + pending).sorted { $0.date > $1.date }.prefix(5))
        save()
    }

    /// Notes whether the app is on screen. Finding the note still set at launch means the last run ended in the
    /// foreground without going to the background first: a crash, or iOS ending it for hanging.
    public func noteForeground(_ active: Bool, now: Date = Date(), appVersion: String, defaults: UserDefaults = .standard) {
        if active { defaults.set(now.timeIntervalSince1970, forKey: Self.foregroundKey) } else { defaults.removeObject(forKey: Self.foregroundKey) }
    }
    /// At launch, before noting the new run.
    public func checkLastRun(appVersion: String, defaults: UserDefaults = .standard) {
        guard let seconds = defaults.object(forKey: Self.foregroundKey) as? Double else { return }
        defaults.removeObject(forKey: Self.foregroundKey)
        add([.unexpectedExit(at: Date(timeIntervalSince1970: seconds), appVersion: appVersion)])
    }
    static let foregroundKey = "diagnostics.foregroundSince"

    /// Reported or dismissed: never offered again.
    public func finish(_ report: DiagnosticReport) {
        pending.removeAll { $0.id == report.id }
        if !handled.contains(report.id) { handled.append(report.id) }
        save()
    }

    private func save() {
        guard let file, let data = try? JSONEncoder().encode(Saved(pending: pending, handled: Array(handled.suffix(200)))) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
