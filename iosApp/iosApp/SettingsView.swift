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
                Section("YouTube content") {
                    Toggle("Show search suggestions", isOn: Binding(get: { preferences.usesSearchSuggestions }, set: preferences.setUsesSearchSuggestions))

                    Picker("Content language", selection: Binding(get: { preferences.contentLocale.language }, set: {
                        preferences.setContentLocale(language: $0, country: preferences.contentLocale.country)
                    })) {
                        ForEach(Locale.isoLanguageCodes.sorted(), id: \.self) { code in Text(Locale.current.localizedString(forLanguageCode: code) ?? code).tag(code) }
                    }
                    Picker("Content region", selection: Binding(get: { preferences.contentLocale.country }, set: {
                        preferences.setContentLocale(language: preferences.contentLocale.language, country: $0)
                    })) {
                        ForEach(Locale.isoRegionCodes.sorted(), id: \.self) { code in Text(Locale.current.localizedString(forRegionCode: code) ?? code).tag(code) }
                    }
                    Text("Used for new YouTube browsing requests. App interface translations are separate.").font(.footnote).foregroundStyle(.secondary)
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
                Section("Your data") {
                    NavigationLink("Backup and import") { LibraryTransferView() }
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
    @EnvironmentObject private var pinnedTabs: PinnedHomeTabs
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
            Section("Pinned channels and playlists") {
                if pinnedTabs.tabs.isEmpty { Text("Use Add to home in a channel or playlist menu.").font(.footnote).foregroundStyle(.secondary) }
                ForEach(pinnedTabs.tabs) { tab in Label(tab.item.title, systemImage: tab.item.kind == .channel ? "person.crop.circle" : "rectangle.stack") }
                    .onMove(perform: pinnedTabs.move)
                    .onDelete { offsets in
                        let ids = offsets.filter { pinnedTabs.tabs.indices.contains($0) }.map { pinnedTabs.tabs[$0].id }
                        ids.forEach(pinnedTabs.remove)
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
