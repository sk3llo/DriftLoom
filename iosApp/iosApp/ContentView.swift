import AVKit
import ComposeApp
import DriftLoomPlayback
import SwiftUI
import UIKit

struct ComposeView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        MainViewControllerKt.mainViewController()
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

struct ContentView: View {
    @StateObject private var playback = PlaybackSession()
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            PlaybackView(playback: playback)
                .tabItem { Label("Watch", systemImage: "play.rectangle") }.tag(0)
            ComposeView()
                .ignoresSafeArea(edges: .top)
                .tabItem { Label("About", systemImage: "info.circle") }.tag(1)
        }
        .tint(.teal)
        .task {
#if DEBUG
            await runPlaybackSmokeCheck(playback)
#endif
        }
        .onOpenURL { url in
            selectedTab = 0
            playback.open(url.absoluteString)
        }
    }
}

private struct PlaybackView: View {
    @ObservedObject var playback: PlaybackSession
    @State private var input = ""
    @State private var showsLicenses = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("A little room to explore.")
                        .font(.title2.weight(.semibold))
                    Text("Paste a YouTube link to start watching.")
                        .foregroundStyle(.secondary)
                    HStack(alignment: .top) {
                        TextField("YouTube video link", text: $input)
                            .textContentType(.URL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.go)
                            .onSubmit(openVideo)
                            .accessibilityIdentifier("videoURL")
                        Button(action: openVideo) { Image(systemName: "arrow.right") }
                            .buttonStyle(.borderedProminent)
                            .accessibilityLabel("Open video")
                            .accessibilityIdentifier("openVideo")
                            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if playback.player.currentItem != nil {
                        VideoPlayer(player: playback.player)
                            .aspectRatio(16 / 9, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .accessibilityIdentifier("videoPlayer")
                        Text(playback.title).font(.headline)
                    }
                    status
                    if playback.didRecover {
                        Label("Stream refreshed. Continuing playback.", systemImage: "arrow.clockwise")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if playback.phase == .idle {
                        ContentUnavailableView("Your next discovery starts here",
                                               systemImage: "play.rectangle.on.rectangle",
                                               description: Text("Videos open in the built-in player."))
                    }
                }
                .padding()
            }
            .navigationTitle("DriftLoom")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if playback.phase != .idle {
                        Button("Stop", systemImage: "stop.circle", action: playback.stop)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsLicenses = true } label: { Image(systemName: "doc.text") }
                        .accessibilityLabel("Open-source licenses")
                }
            }
            .sheet(isPresented: $showsLicenses) {
                NavigationStack {
                    ScrollView {
                        Text(licenseText)
                            .font(.footnote).padding()
                    }
                    .navigationTitle("Open-source licenses")
                    .toolbar { Button("Done") { showsLicenses = false } }
                }
            }
        }
    }

    @ViewBuilder private var status: some View {
        switch playback.phase {
        case .resolving: ProgressView("Opening video…")
        case .loading: ProgressView("Loading stream…")
        case let .failed(message):
            VStack(alignment: .leading, spacing: 12) {
                Label(message, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("playbackError")
                Button("Try again", action: openVideo).buttonStyle(.bordered)
            }
        case .playing: Label("Playing", systemImage: "play.fill").foregroundStyle(.secondary)
        case .paused: Label("Paused", systemImage: "pause.fill").foregroundStyle(.secondary)
        case .idle: EmptyView()
        }
    }

    private var licenseText: String {
        Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "License information is unavailable."
    }

    private func openVideo() {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        dismissKeyboard()
        playback.open(input)
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
