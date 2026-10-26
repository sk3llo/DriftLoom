// SPDX-License-Identifier: GPL-3.0-or-later
import DriftLoomPlayback
import SwiftUI

struct PlaybackFormatPicker: View {
    @ObservedObject var playback: PlaybackSession
    @Environment(\.dismiss) private var dismiss
    @State private var choices: [DownloadChoice] = []
    @State private var loading = true
    @State private var error: String?
    var body: some View {
        AppNavigation {
            List {
                Button("Automatic playback\(playback.selectedFormat == nil ? " ✓" : "")") { playback.selectFormat(nil); dismiss() }
                if loading { ProgressView("Finding available formats…") }
                if let error { Text(error).foregroundStyle(.secondary) }
                ForEach(choices) { choice in
                    Button(choice.name + (playback.selectedFormat?.id == choice.id ? " ✓" : "")) {
                        playback.selectFormat(choice); dismiss()
                    }
                }
                Text("Automatic playback prefers HLS. Fixed formats are listed only when extraction returns a format your device can play. Adaptive quality within HLS remains automatic.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("Playback format").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .task {
                do { if let id = playback.videoID { choices = try await YouTubeDownloadResolver().choices(videoID: id) } }
                catch { self.error = error.localizedDescription }
                loading = false
            }
        }
    }
}
