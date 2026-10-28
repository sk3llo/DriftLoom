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

    /// The issue text. `environment` is the app, device and settings, in table order.
    public func body(environment: [Detail], errorLimit: Int = 2000) -> String {
        var lines = ["### What happened", "", "<!-- What were you doing, and what did you expect? Steps to reproduce help a lot. -->", ""]
        if let error, !error.isEmpty {
            let text = error.count > errorLimit ? error.prefix(errorLimit) + "…" : Substring(error)
            lines += ["### Error", "", "```", String(text).replacingOccurrences(of: "```", with: "'''"), "```", ""]
        }
        lines += ["### Details", "", "| | |", "|---|---|", "| Area | \(cell(area)) |"]
        lines += (context + environment).map { "| \(cell($0.name)) | \(cell($0.value)) |" }
        lines += ["", "<sub>Sent from DriftLoom's Report button. Everything above is public once submitted; remove anything you don't want to share.</sub>"]
        return lines.joined(separator: "\n")
    }

    public func issueURL(environment: [Detail]) -> URL {
        var limit = 2000
        while true {
            var components = URLComponents(url: Self.repository.appendingPathComponent("issues/new"), resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "title", value: title), URLQueryItem(name: "body", value: body(environment: environment, errorLimit: limit))]
            // URLComponents leaves "+" and "&"-free text as is; encode "+" so GitHub doesn't read it as a space.
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
            let url = components.url!
            if url.absoluteString.count <= Self.maximumURLLength || limit <= 100 { return url }
            limit /= 2
        }
    }

    private func cell(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
    }
}
