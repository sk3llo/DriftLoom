// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// A problem report that opens as a new GitHub issue, prefilled so the person only has to say what they did.
/// Nothing is sent from the app: the browser shows the issue, and it's posted only if they submit it there.
public struct ProblemReport: Equatable, Sendable {
    public static let repository = URL(string: "https://github.com/sk3llo/DriftLoom")!
    /// GitHub and browsers cut long links; the error text gives way first.
    static let maximumURLLength = 7000

    public let area: String
    public let error: String?
    /// What was open when it failed, such as ("Video", "https://youtu.be/…"); shown in the issue's details table.
    public let context: [Detail]
    public struct Detail: Codable, Equatable, Sendable {
        public let name: String, value: String
        public init(_ name: String, _ value: String) { self.name = name; self.value = value }
    }

    /// For the title when the error text is long or multi-line, such as a crash's stack.
    public let headline: String?

    public init(area: String, error: String? = nil, context: [Detail] = [], headline: String? = nil) {
        self.area = area; self.error = error; self.context = context; self.headline = headline
    }

    public var title: String {
        let summary = (headline ?? error).map { $0.replacingOccurrences(of: "\n", with: " ") }.map { $0.count > 80 ? $0.prefix(77) + "…" : $0 }
        return "[iOS] \(area)" + (summary.map { ": \($0)" } ?? "")
    }

    /// The issue text, for copying. `environment` is the app, device and settings, in table order.
    public func body(environment: [Detail], errorLimit: Int = 2000) -> String {
        var lines = ["### What happened", "", "<!-- What were you doing, and what did you expect? Steps to reproduce help a lot. -->", ""]
        if let text = errorText(limit: errorLimit) {
            lines += ["### Error", "", "```", text.replacingOccurrences(of: "```", with: "'''"), "```", ""]
        }
        lines += ["### Details", "", details(environment: environment)]
        return lines.joined(separator: "\n")
    }

    /// The details table: area, context, then `environment`.
    public func details(environment: [Detail]) -> String {
        var lines = ["| | |", "|---|---|", "| Area | \(cell(area)) |"]
        lines += (context + environment).map { "| \(cell($0.name)) | \(cell($0.value)) |" }
        lines += ["", "<sub>Sent from DriftLoom's Report button.</sub>"]
        return lines.joined(separator: "\n")
    }

    /// The repository's "Report from the app" issue form (.github/ISSUE_TEMPLATE/app_report.yml), with its
    /// fields filled in by id. The repository allows only template issues, so a plain `body=` link would lose the text.
    public static let issueTemplate = "app_report.yml"

    public func issueURL(environment: [Detail]) -> URL {
        var limit = 2000
        while true {
            var components = URLComponents(url: Self.repository.appendingPathComponent("issues/new"), resolvingAgainstBaseURL: false)!
            var items = [URLQueryItem(name: "template", value: Self.issueTemplate), URLQueryItem(name: "title", value: title)]
            if let text = errorText(limit: limit) { items.append(URLQueryItem(name: "error", value: text)) }
            items.append(URLQueryItem(name: "details", value: details(environment: environment)))
            components.queryItems = items
            // URLComponents leaves "+" and "&"-free text as is; encode "+" so GitHub doesn't read it as a space.
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
            let url = components.url!
            if url.absoluteString.count <= Self.maximumURLLength || limit <= 100 { return url }
            limit /= 2
        }
    }

    private func errorText(limit: Int) -> String? {
        guard let error, !error.isEmpty else { return nil }
        return error.count > limit ? String(error.prefix(limit)) + "…" : error
    }

    private func cell(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
    }
}
