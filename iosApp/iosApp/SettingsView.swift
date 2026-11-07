// SPDX-License-Identifier: GPL-3.0-or-later
import DriftLoomPlayback
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var library: LibraryStore
    @State private var clearTarget: String?
    @State private var notificationsDenied = false
    /// The language or region list that is open, so a launch flag can open it too.
    @State private var openChoice: String?
    @State private var choiceSearch = ""
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

                    NavigationLink(tag: "language", selection: $openChoice) {
                        LocaleChoiceList(title: "Content language", prompt: "Search languages", choices: LocaleChoiceList.languages,
                                         selected: preferences.contentLocale.language) {
                            preferences.setContentLocale(language: $0, country: preferences.contentLocale.country)
                        }
                    } label: {
                        LabeledValue("Content language", value: LocaleChoiceList.name(of: preferences.contentLocale.language, in: LocaleChoiceList.languages))
                    }.accessibilityIdentifier("contentLanguage")
                    NavigationLink(tag: "region", selection: $openChoice) {
                        LocaleChoiceList(title: "Content region", prompt: "Search countries", choices: LocaleChoiceList.regions,
                                         selected: preferences.contentLocale.country, search: choiceSearch) {
                            preferences.setContentLocale(language: preferences.contentLocale.language, country: $0)
                        }
                    } label: {
                        LabeledValue("Content region", value: LocaleChoiceList.name(of: preferences.contentLocale.country, in: LocaleChoiceList.regions))
                    }.accessibilityIdentifier("contentRegion")
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
                Section("Help") {
                    NavigationLink(tag: "guide", selection: $openChoice) { UserGuideView() } label: { Label("User guide", systemImage: "book") }
                        .accessibilityIdentifier("openUserGuide")
                    ReportProblemButton("Report a problem") { ProblemReport(area: "General") }
                }
                Section {
                    NavigationLink { AboutView() } label: { Label("About", systemImage: "info.circle") }
                        .accessibilityIdentifier("openAbout")
                } footer: { Text("Independent NewPipe fork · GPL-3.0-or-later") }
            }
            .navigationTitle("Settings")
#if DEBUG || DRIFTLOOM_DEVICE_TESTING
            // --settings-smoke language: then use the Language row, as a tap would.
            // --settings-smoke region [search]: open the Content region list, optionally searched.
            .task {
                let arguments = ProcessInfo.processInfo.arguments
                // --guide-smoke [page.md]: open the user guide, optionally at a page (see UserGuideView).
                if arguments.contains("--guide-smoke") { try? await Task.sleep(nanoseconds: 1_000_000_000); openChoice = "guide" }
                if let flag = arguments.firstIndex(of: "--settings-smoke"), arguments.indices.contains(flag + 1), arguments[flag + 1] == "region" {
                    if arguments.indices.contains(flag + 2), !arguments[flag + 2].hasPrefix("--") { choiceSearch = arguments[flag + 2] }
                    try? await Task.sleep(nanoseconds: 1_000_000_000); openChoice = "region"
                }
                guard let flag = arguments.firstIndex(of: "--settings-smoke"), arguments.indices.contains(flag + 1), arguments[flag + 1] == "language" else { return }
                NSLog("DriftLoomSettingsSmoke: language row shows %@", interfaceLanguage)
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
#endif
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
        pinnedTabs.arrangement(sections: HomeSection.shownOnHome(preferences.homeSections), localPlaylistIDs: Set(playlists.playlists.map(\.id)))
    }
    /// Subscriptions, What's new, Bookmarked and History have their own tabs; they keep their place in the saved
    /// section list for backups and the Android app.
    private var otherSections: [HomeSection] { preferences.homeSections.filter { !$0.isBrowse } }
    var body: some View {
        List {
            Section {
                ForEach(arrangement, id: \.self) { key in row(key).deleteDisabled(isSection(key)) }
                    .onMove { offsets, destination in
                        var keys = arrangement
                        keys.move(fromOffsets: offsets, toOffset: destination)
                        pinnedTabs.setOrder(keys)
                        // Keep the section preference in the same relative order for backups and the Android app.
                        preferences.setHomeSections(keys.compactMap { if case let .section(section) = $0 { return section }; return nil } + otherSections)
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
                ForEach(HomeSection.allCases.filter(\.isBrowse)) { section in
                    Toggle(section.title, isOn: Binding(get: { HomeSection.shownOnHome(preferences.homeSections).contains(section) }, set: { enabled in
                        let shown = HomeSection.shownOnHome(preferences.homeSections)
                        preferences.setHomeSections((enabled ? shown + [section] : shown.filter { $0 != section }) + otherSections)
                    }))
                    .disabled(HomeSection.shownOnHome(preferences.homeSections) == [section])
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

/// A setting's name with its current value on the right, as Picker rows show it.
private struct LabeledValue: View {
    let title: LocalizedStringKey
    let value: String
    init(_ title: LocalizedStringKey, value: String) { self.title = title; self.value = value }
    var body: some View {
        HStack { Text(title); Spacer(); Text(value).foregroundStyle(.secondary) }
    }
}

/// Hundreds of languages or regions, named in the interface language, with search. The names are worked out
/// once and sorted by name, not on every redraw like a Picker's, so long scrolls stay smooth on older iPhones.
struct LocaleChoiceList: View {
    /// `english` lets "ukr" find Україна whatever the interface language.
    struct Choice: Identifiable, Equatable { let id: String; let name: String; let english: String }
    let title: LocalizedStringKey
    let prompt: LocalizedStringKey
    let choices: [Choice]
    let selected: String
    let onSelect: (String) -> Void
    @State private var search: String
    @Environment(\.dismiss) private var dismiss

    init(title: LocalizedStringKey, prompt: LocalizedStringKey, choices: [Choice], selected: String, search: String = "", onSelect: @escaping (String) -> Void) {
        self.title = title; self.prompt = prompt; self.choices = choices; self.selected = selected; self.onSelect = onSelect
        _search = State(initialValue: search)
    }

    /// Two-letter ISO 639-1 codes: what YouTube's hl accepts, without hundreds of historical languages.
    static let languages: [Choice] = sorted(Locale.isoLanguageCodes.filter { $0.count == 2 }) { $0.localizedString(forLanguageCode: $1) }
    static let regions: [Choice] = sorted(Locale.isoRegionCodes.filter { $0.count == 2 }) { $0.localizedString(forRegionCode: $1) }
    private static func sorted(_ codes: [String], name: (Locale, String) -> String?) -> [Choice] {
        let english = Locale(identifier: "en")
        return codes.map { Choice(id: $0, name: name(.current, $0) ?? $0, english: name(english, $0) ?? $0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    static func name(of code: String, in choices: [Choice]) -> String { choices.first { $0.id == code }?.name ?? code }

    private var matches: [Choice] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return choices }
        return choices.filter {
            $0.name.localizedStandardContains(query) || $0.english.localizedStandardContains(query) || $0.id.caseInsensitiveCompare(query) == .orderedSame
        }
    }

    var body: some View {
        let matches = matches
        List {
            if search.isEmpty, let current = choices.first(where: { $0.id == selected }) {
                Section("Selected") { row(current) }
            }
            Section {
                ForEach(matches) { row($0) }
                if matches.isEmpty { Text("No matches").foregroundStyle(.secondary) }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: Text(prompt))
        .disableAutocorrection(true)
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ choice: Choice) -> some View {
        Button { onSelect(choice.id); dismiss() } label: {
            HStack {
                Text(choice.name).foregroundColor(.primary)
                Spacer()
                if choice.id == selected { Image(systemName: "checkmark").foregroundColor(AppStyle.accent).accessibilityHidden(true) }
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(choice.id == selected ? .isSelected : [])
        .accessibilityIdentifier("localeChoice-" + choice.id)
    }
}
