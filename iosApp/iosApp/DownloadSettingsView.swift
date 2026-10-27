// SPDX-License-Identifier: GPL-3.0-or-later
import DriftLoomPlayback
import SwiftUI

struct DownloadSettingsView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @ObservedObject private var manager = DownloadManager.shared
    @State private var usage: DownloadStorageUsage?
    @State private var refresh = UUID()
    private var storageKey: [String] { manager.records.map { $0.id.uuidString + $0.state.rawValue + ($0.localPath ?? "") } + [refresh.uuidString] }
    var body: some View {
        List {
            Section("Download network") {
                ForEach(DownloadNetwork.allCases) { network in
                    Button { preferences.setDownloadNetwork(network) } label: {
                        HStack {
                            Text(network.title).foregroundStyle(.primary)
                            Spacer()
                            if preferences.downloadNetwork == network { Image(systemName: "checkmark") }
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.accessibilityIdentifier("downloadNetwork-" + network.rawValue)
                        .accessibilityValue(preferences.downloadNetwork == network ? "Selected" : "Not selected")
                }
                Text("Applies to new downloads and retries. Existing transfers keep their chosen network. Finding formats and video details uses your current connection.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Downloaded media storage") {
                if let usage {
                    Text(usage.incomplete ? String(localized: "At least \(ByteCountFormatter.string(fromByteCount: usage.bytes, countStyle: .file))") : ByteCountFormatter.string(fromByteCount: usage.bytes, countStyle: .file))
                        .accessibilityIdentifier("downloadStorageUsage")
                    Text("\(manager.records.filter { $0.state == .completed }.count) completed downloads").font(.caption).foregroundStyle(.secondary)
                } else { ProgressView("Measuring storage…") }
                Button("Recalculate storage") { refresh = UUID() }
                Text("Includes completed media on this device. Active transfers and iOS temporary files are excluded. Delete downloads from Downloads to free space.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Downloads and storage").navigationBarTitleDisplayMode(.inline).navigationBarHidden(false)
        .task(id: storageKey) {
            usage = nil
            let value = await DownloadStorage.measure(manager.storageURLs)
            if !Task.isCancelled { usage = value }
        }
    }
}
