// SPDX-License-Identifier: GPL-3.0-or-later
import DriftLoomPlayback
import SwiftUI

struct DownloadPicker: View {
    let item: BrowseItem
    @ObservedObject private var manager = DownloadManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var choices: [DownloadChoice] = []
    @State private var loading = true
    @State private var error: String?
    @State private var subtitleTracks: [SubtitleTrack] = []
    @State private var subtitleLanguage: String?
    @EnvironmentObject private var preferences: AppPreferences
    private var subtitleLanguages: [String] {
        var seen = Set<String>()
        return subtitleTracks.map { SubtitleSelection.baseLanguage($0.displayLanguage) }.filter { seen.insert($0).inserted }
    }
    var body: some View {
        AppNavigation {
            List {
                Text(item.title).font(.headline)
                if !subtitleLanguages.isEmpty {
                    Picker("Subtitles", selection: $subtitleLanguage) {
                        Text("None").tag(String?.none)
                        ForEach(subtitleLanguages, id: \.self) { code in
                            Text(Locale.current.localizedString(forLanguageCode: code) ?? code).tag(Optional(code))
                        }
                    }.accessibilityIdentifier("downloadSubtitles")
                }
                if loading { ProgressView("Finding download formats…") }
                if let error { Text(error).foregroundStyle(.secondary) }
                ForEach(choices) { choice in
                    Button(choice.name) {
                        if manager.start(item: item, choice: choice, subtitleLanguage: subtitleLanguage) != nil { dismiss() }
                        else { error = manager.library.error ?? String(localized: "Downloads are reconnecting. Try again shortly.") }
                    }.disabled(manager.reconnecting || !manager.library.isWritable)
                }
                Text("Downloads use device storage. Available formats depend on this video. You can cancel or retry in Downloads.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("Download").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() }.accessibilityIdentifier("closeSheet") } }
            .task {
                if let catalog = try? await YouTubeSubtitleClient().catalog(videoID: item.contentID) {
                    subtitleTracks = catalog.tracks
                    subtitleLanguage = catalog.preferred(language: preferences.subtitleLanguage, allowTranslation: preferences.translatesSubtitles)
                        .map { SubtitleSelection.baseLanguage($0.displayLanguage) }
                    // A translated preference isn't among the native languages; list it so the picker can show it.
                    if let language = subtitleLanguage, !subtitleLanguages.contains(language), let source = catalog.translationSource,
                       let target = catalog.translations.first(where: { SubtitleSelection.baseLanguage($0.code) == language }) {
                        subtitleTracks.append(source.translated(to: target))
                    }
                }
            }
            .task {
                do { choices = try await YouTubeDownloadResolver().choices(videoID: item.contentID) }
                catch { self.error = error.localizedDescription }
                loading = false
            }
        }
    }
}

struct DownloadsView: View {
    let onPlay: (BrowseItem) -> Void
    @ObservedObject private var manager = DownloadManager.shared
    @State private var deleting: DownloadRecord?
    var body: some View {
        List {
            NavigationLink("Downloads and storage") { DownloadSettingsView() }.accessibilityIdentifier("openDownloadSettings")
            if let error = manager.operationError { Text(error).font(.footnote).foregroundStyle(.secondary) }
            if let error = manager.library.error { Text(error).foregroundStyle(.secondary) }
            if manager.records.isEmpty { Text("Download a video from its playback options to watch it offline.").foregroundStyle(.secondary) }
            ForEach(manager.records) { record in
                VStack(alignment: .leading, spacing: 8) {
                    Text(record.item.title).font(.headline)
                    Text(record.choice.name).font(.caption).foregroundStyle(.secondary)
                    if let network = record.network { Text(network.title).font(.caption2).foregroundStyle(.secondary) }
                    if let language = record.subtitleLanguage {
                        let name = Locale.current.localizedString(forLanguageCode: language) ?? language
                        Text(record.subtitlePath != nil ? String(localized: "Subtitles: \(name)") : record.subtitleError.map { String(localized: "Subtitles unavailable: \($0)") } ?? String(localized: "Subtitles: \(name) (pending)"))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if record.state == .downloading || record.state == .preparing {
                        ProgressView(value: record.progress)
                        Text(record.waitingForNetwork == true ? (record.network == .wifiOnly ? "Waiting for Wi-Fi…" : "Waiting for a connection…") : record.state == .preparing ? "Preparing…" : "\(Int(record.progress * 100))%").font(.caption)
                        Button("Cancel download") { manager.cancel(record.id) }
                    } else if record.state == .completed {
                        if manager.localURL(record) != nil {
                            Button("Play offline") { onPlay(record.item) }
                        } else { Text("The downloaded file is missing. Remove this entry and download it again.").font(.footnote) }
                    } else {
                        Text(record.error ?? String(localized: "Cancelled")).font(.footnote).foregroundStyle(.secondary)
                        Button("Retry download") { manager.retry(record.id) }
                    }
                }.padding(.vertical, 4)
                .swipeActions { Button("Delete", role: .destructive) { deleting = record } }
            }
        }
        .navigationTitle("Downloads").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete downloaded media?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let deleting { manager.remove(deleting.id) }; deleting = nil }
        } message: { Text("This removes the download from this device.") }
    }
}
