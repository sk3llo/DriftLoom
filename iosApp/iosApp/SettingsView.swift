// SPDX-License-Identifier: GPL-3.0-or-later
import DriftLoomPlayback
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var library: LibraryStore
    @State private var clearTarget: String?
    @State private var notificationsDenied = false
    private func resolutionPicker(_ title: LocalizedStringKey, mobile: Bool) -> some View {
        Picker(title, selection: Binding(get: { mobile ? preferences.mobileMaximumHeight : preferences.wifiMaximumHeight },
                                         set: { preferences.setMaximumHeight($0, mobile: mobile) })) {
            ForEach(PlaybackSession.resolutionChoices, id: \.self) { height in
                Text(height == 0 ? String(localized: "Auto") : String(localized: "Up to \(String(height))p")).tag(height)
            }
        }
    }
    @Environment(\.openURL) private var openURL
    /// The language DriftLoom is shown in, named in that language's own terms for the current interface.
    private var interfaceLanguage: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        let name = Locale.current.localizedString(forLanguageCode: code) ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }
    var body: some View {
        AppNavigation {
            List {
                Section {
                    Picker("Theme", selection: Binding(get: { preferences.appearance }, set: preferences.setAppearance)) {
                        ForEach(["System", "Light", "Dark"], id: \.self) { Text(LocalizedStringKey($0)).tag($0) }
                    }
                    // iOS keeps each app's language in the Settings app; this row shows it and opens that page.
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } label: {
                        HStack {
                            Text("Language").foregroundColor(.primary)
                            Spacer()
                            Text(interfaceLanguage).foregroundColor(.secondary)
                            Image(systemName: "arrow.up.forward.app").foregroundColor(.secondary).accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    // Plain, so iOS 15 doesn't paint the row in the accent colour like a link.
                    .buttonStyle(.plain)
                    .accessibilityValue(interfaceLanguage).accessibilityHint("Opens DriftLoom in the Settings app")
                    .accessibilityIdentifier("interfaceLanguage")
                    NavigationLink("Home tabs") { HomeTabsSettings() }.accessibilityIdentifier("openHomeTabs")
                } header: { Text("Appearance") } footer: {
                    Text("Choose English, Ukrainian or Portuguese under Language in the Settings app. If Language isn't there, add another language to the iPhone first in General → Language & Region.")
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
                    Toggle("Autoplay related videos", isOn: Binding(get: { preferences.autoplaysRelated }, set: preferences.setAutoplaysRelated))
                        .accessibilityIdentifier("autoplayRelated")
                    resolutionPicker("Resolution on Wi-Fi", mobile: false).accessibilityIdentifier("wifiResolution")
                    resolutionPicker("Resolution on mobile data", mobile: true).accessibilityIdentifier("mobileResolution")
                    Text("When the last video in the queue ends, a related one plays next. The resolution applies to new videos; choosing one in the player changes only the current video.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Playback continues in the mini-player while you browse. Close it to stop playback.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Toggle("New videos from subscriptions", isOn: Binding(get: { preferences.notifiesNewVideos }, set: { enabled in
                        preferences.setNotifiesNewVideos(enabled)
                        Task {
                            if enabled, await DownloadNotifier.shared.requestAuthorization() == false { notificationsDenied = true }
                            FeedRefresher.shared.schedule()
                        }
                    })).accessibilityIdentifier("notifyNewVideos")
                    if notificationsDenied {
                        Text("Notifications are off for DriftLoom. Turn them on in the Settings app.").font(.footnote).foregroundColor(.red)
                    }
                } header: { Text("Notifications") } footer: {
                    Text("DriftLoom checks your subscriptions in the background and tells you about new videos. iOS decides when checks run, based on how often you use the app; Background App Refresh must be on.")
                }
                Section("Subtitles") {
                    Picker("Show subtitles in", selection: Binding(get: { preferences.subtitleLanguage }, set: preferences.setSubtitleLanguage)) {
                        Text("Off").tag(String?.none)
                        ForEach(Locale.isoLanguageCodes.sorted(), id: \.self) { code in
                            Text(Locale.current.localizedString(forLanguageCode: code) ?? code).tag(Optional(code))
                        }
                    }.accessibilityIdentifier("subtitleLanguage")
                    Toggle("Auto-translate when unavailable", isOn: Binding(get: { preferences.translatesSubtitles }, set: preferences.setTranslatesSubtitles))
                        .accessibilityIdentifier("translateSubtitles")
                    Picker("Text size", selection: Binding(get: { preferences.subtitleSize }, set: preferences.setSubtitleSize)) {
                        ForEach(SubtitleSize.allCases) { Text($0.title).tag($0) }
                    }
                    Text("YouTube subtitles in this language turn on automatically, preferring ones written by the uploader over auto-generated ones. Choosing subtitles in the player updates this setting. Auto-translation uses YouTube's machine translation, which YouTube may limit at times.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Downloads") {
                    NavigationLink("Downloads and storage") { DownloadSettingsView() }.accessibilityIdentifier("openDownloadSettings")
                }
                Section("Your data") {
                    NavigationLink("Backup and import") { LibraryTransferView() }.accessibilityIdentifier("openBackup")
                }
                Section("About") {
                    Text("DriftLoom · iOS 15 and later")
                    Text("Independent NewPipe fork · GPL-3.0-or-later").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
#if DEBUG || DRIFTLOOM_DEVICE_TESTING
            // --settings-smoke language: then use the Language row, as a tap would.
            .task {
                let arguments = ProcessInfo.processInfo.arguments
                guard let flag = arguments.firstIndex(of: "--settings-smoke"), arguments.indices.contains(flag + 1), arguments[flag + 1] == "language" else { return }
                NSLog("DriftLoomSettingsSmoke: language row shows %@", interfaceLanguage)
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
#endif
            .toolbar { Button("Done") { dismiss() }.accessibilityIdentifier("closeSheet") }
            .confirmationDialog(clearTarget == "watch" ? "Clear watch history?" : "Clear search history?",
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

struct HomeTabsSettings: View {
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var pinnedTabs: PinnedHomeTabs
    @EnvironmentObject private var playlists: PlaylistStore
    private var arrangement: [HomeTabKey] {
        pinnedTabs.arrangement(sections: preferences.homeSections, localPlaylistIDs: Set(playlists.playlists.map(\.id)))
    }
    var body: some View {
        List {
            Section {
                ForEach(arrangement, id: \.self) { key in row(key).deleteDisabled(isSection(key)) }
                    .onMove { offsets, destination in
                        var keys = arrangement
                        keys.move(fromOffsets: offsets, toOffset: destination)
                        pinnedTabs.setOrder(keys)
                        // Keep the section preference in the same relative order for the drawer and backups.
                        preferences.setHomeSections(keys.compactMap { if case let .section(section) = $0 { return section }; return nil })
                    }
                    .onDelete { offsets in
                        for key in offsets.filter({ arrangement.indices.contains($0) }).map({ arrangement[$0] }) {
                            switch key {
                            case let .pinned(id): pinnedTabs.remove(id)
                            case let .local(id): pinnedTabs.removeLocal(id)
                            case .section: break
                            }
                        }
                    }
                    .moveDisabled(!pinnedTabs.isWritable)
            } header: { Text("Home tabs · drag to reorder") } footer: {
                Text("Pin channels and online playlists with Add to home in their menu, and local playlists from the playlist's options. Swipe to remove a pinned tab.")
            }
            Section("Show on home") {
                ForEach(HomeSection.allCases) { section in
                    Toggle(section.title, isOn: Binding(get: { preferences.homeSections.contains(section) }, set: { enabled in
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
    private func isSection(_ key: HomeTabKey) -> Bool { if case .section = key { return true }; return false }
    @ViewBuilder private func row(_ key: HomeTabKey) -> some View {
        switch key {
        case let .section(section): Label(section.title, systemImage: section.symbol).accessibilityIdentifier("homeTab-" + key.rawValue)
        case let .pinned(id):
            if let tab = pinnedTabs.tabs.first(where: { $0.id == id }) {
                Label(tab.item.title, systemImage: tab.item.kind == .channel ? "person.crop.circle" : "rectangle.stack").accessibilityIdentifier("homeTab-" + key.rawValue)
            }
        case let .local(id):
            Label(playlists.playlists.first { $0.id == id }?.name ?? String(localized: "Playlist"), systemImage: "music.note.list").accessibilityIdentifier("homeTab-local")
        }
    }
}
