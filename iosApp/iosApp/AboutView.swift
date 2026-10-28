// SPDX-License-Identifier: GPL-3.0-or-later
import DriftLoomPlayback
import SwiftUI

/// Keep app information available without linking a higher-minimum-OS UI framework.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        AppNavigation {
            List {
                Section {
                    Text("DriftLoom").font(.title.weight(.semibold))
                    Text("A little room to explore.").foregroundStyle(.secondary)
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                    Text("Requires iOS 15 or later.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Your library") {
                    Text("Saved videos, subscriptions, and watch history stay on this device. Manage and clear history in Library.")
                }
                Section("Project and credits") {
                    NavigationLink { UserGuideView() } label: { Label("User guide", systemImage: "book") }
                        .accessibilityIdentifier("aboutUserGuide")
                    ReportProblemButton("Report a problem") { ProblemReport(area: "General") }
                    Link("DriftLoom source code", destination: URL(string: "https://github.com/sk3llo/DriftLoom")!)
                    Link("Based on NewPipe", destination: URL(string: "https://github.com/TeamNewPipe/NewPipe")!)
                    Text("An independent fork of NewPipe, licensed under GPL-3.0-or-later. Thanks to the NewPipe contributors.")
                        .font(.footnote)
                    NavigationLink("Open-source licenses") {
                        ScrollView { Text(notices).font(.footnote).padding() }
                            .navigationTitle("Licenses")
                    }
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() }.accessibilityIdentifier("closeSheet") }
        }
    }
    private var notices: String {
        Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? String(localized: "License information is unavailable.")
    }
}
