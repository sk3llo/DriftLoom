// SPDX-License-Identifier: GPL-3.0-or-later
import DriftLoomPlayback
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var library: LibraryStore
    @State private var clearTarget: String?
    var body: some View {
        AppNavigation {
            List {
                Section("Appearance") {
                    Picker("Theme", selection: Binding(get: { preferences.appearance }, set: preferences.setAppearance)) {
                        ForEach(["System", "Light", "Dark"], id: \.self) { Text($0).tag($0) }
                    }
                    NavigationLink("Home tabs") { HomeTabsSettings() }
                }
                Section("History") {
                    Toggle("Record watch history", isOn: Binding(get: { library.historyEnabled }, set: library.setHistoryEnabled))
                        .disabled(!library.isWritable)
                    Toggle("Record search history", isOn: Binding(get: { preferences.recordsSearchHistory }, set: preferences.setRecordsSearchHistory))
                    Button("Clear watch history", role: .destructive) { clearTarget = "watch" }.disabled(!library.isWritable)
                    Button("Clear search history", role: .destructive) { clearTarget = "search" }
                }
                Section("Playback") {
                    Toggle("Resume playback position", isOn: Binding(get: { preferences.resumesPlayback }, set: preferences.setResumesPlayback))
                    Text("Playback continues in the mini-player while you browse. Close it to stop playback.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("About") {
                    Text("DriftLoom · iOS 15 and later")
                    Text("Independent NewPipe fork · GPL-3.0-or-later").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .confirmationDialog("Clear \(clearTarget == "watch" ? "watch" : "search") history?",
                                isPresented: Binding(get: { clearTarget != nil }, set: { if !$0 { clearTarget = nil } }), titleVisibility: .visible) {
                Button("Clear history", role: .destructive) {
                    if clearTarget == "watch" { library.clearHistory() } else { preferences.clearSearchHistory() }
                    clearTarget = nil
                }
                Button("Cancel", role: .cancel) { clearTarget = nil }
            }
        }
    }
}

private struct HomeTabsSettings: View {
    @EnvironmentObject private var preferences: AppPreferences
    var body: some View {
        List {
            Section("Visible tabs · drag to reorder") {
                ForEach(preferences.homeSections) { section in Label(section.rawValue, systemImage: section.symbol) }
                    .onMove { offsets, destination in
                        var sections = preferences.homeSections
                        sections.move(fromOffsets: offsets, toOffset: destination)
                        preferences.setHomeSections(sections)
                    }
            }
            Section("Show on home") {
                ForEach(HomeSection.allCases) { section in
                    Toggle(section.rawValue, isOn: Binding(get: { preferences.homeSections.contains(section) }, set: { enabled in
                        let current = preferences.homeSections
                        preferences.setHomeSections(enabled ? current + [section] : current.filter { $0 != section })
                    }))
                    .disabled(preferences.homeSections.count == 1 && preferences.homeSections.contains(section))
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Home tabs").navigationBarTitleDisplayMode(.inline)
    }
}
