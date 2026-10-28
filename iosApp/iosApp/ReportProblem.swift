// SPDX-License-Identifier: GPL-3.0-or-later
import DriftLoomPlayback
import SwiftUI
import UIKit

extension ProblemReport {
    /// The app, device and settings, for the issue's details table. No library, history or account data.
    static var environment: [Detail] {
        let info = Bundle.main.infoDictionary
        var system = utsname(); uname(&system)
        let model = withUnsafeBytes(of: &system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        let locale = ContentLocale.current()
        return [
            Detail("App", "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"),
            Detail("iOS", UIDevice.current.systemVersion),
            Detail("Device", model),
            Detail("App language", Bundle.main.preferredLocalizations.first ?? "?"),
            Detail("Content", "\(locale.language)-\(locale.country)"),
        ]
    }

    /// What a page was, for a browsing error.
    static func describe(_ route: BrowseRoute?) -> [Detail] {
        switch route {
        case let .search(query)?, let .filteredSearch(query, _)?, let .advancedSearch(query, _)?: return [Detail("Search", query)]
        case let .soundCloudSearch(query, _)?: return [Detail("SoundCloud search", query)]
        case let .channel(id)?, let .channelTab(id, _)?:
            return [Detail("Channel", SoundCloudID.isSoundCloud(id) ? id : "https://www.youtube.com/channel/\(id)")]
        case let .playlist(id)?: return [Detail("Playlist", SoundCloudID.isSoundCloud(id) ? id : "https://www.youtube.com/playlist?list=\(id)")]
        case let .related(id)?: return [Detail("Related to", videoLink(id))]
        case let .mix(playlist, seed)?: return [Detail("Mix", "https://www.youtube.com/watch?v=\(seed)&list=\(playlist)")]
        case let .kiosk(kiosk)?: return [Detail("Page", kiosk.rawValue)]
        case .trendingMusic?: return [Detail("Page", "Trending music")]
        case .soundCloudTrending?: return [Detail("Page", "SoundCloud trending")]
        case nil: return []
        }
    }

    func copyToPasteboard() {
        UIPasteboard.general.string = title + "\n\n" + body(environment: ProblemReport.environment)
    }

    static func videoLink(_ id: String) -> String { SoundCloudID.isSoundCloud(id) ? id : "https://youtu.be/\(id)" }
}

/// "Report", next to an error or in Settings. It explains first that the report opens as a GitHub issue in the
/// browser and is posted only if submitted there; people without a GitHub account can copy the details instead.
struct ReportProblemButton: View {
    let title: LocalizedStringKey
    let report: () -> ProblemReport
    @State private var asking = false
    @State private var copied = false
    @Environment(\.openURL) private var openURL

    init(_ title: LocalizedStringKey = "Report", report: @escaping () -> ProblemReport) {
        self.title = title; self.report = report
    }

    var body: some View {
        Button { asking = true } label: { Label(title, systemImage: "exclamationmark.bubble") }
            .accessibilityIdentifier("reportProblem")
            .confirmationDialog("Report a problem", isPresented: $asking, titleVisibility: .visible) {
                Button("Open GitHub") { openURL(report().issueURL(environment: ProblemReport.environment)) }
                Button("Copy details") { report().copyToPasteboard(); copied = true }
            } message: {
                Text("A new issue opens on GitHub with the error, the app version and your device model. Nothing is sent until you submit it there, and the issue is public.")
            }
            .alert("Details copied", isPresented: $copied) {} message: { Text("Paste them into an email or a GitHub issue.") }
    }
}
