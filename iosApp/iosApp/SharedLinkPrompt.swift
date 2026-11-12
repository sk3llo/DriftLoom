// SPDX-License-Identifier: GPL-3.0-or-later
import DriftLoomActivity
import SwiftUI

/// Sharing stores links; only an explicit confirmation in the app opens or plays them.
struct SharedLinkPrompt: ViewModifier {
    let onOpen: (URL) -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var entry: SharedLinkInbox.Entry?
    @State private var error: String?
    @State private var configured = false

    func body(content: Content) -> some View {
        content
            .alert("Open shared link?", isPresented: Binding(get: { entry != nil }, set: { if !$0 { entry = nil } }), presenting: entry) { item in
                Button("Open") { consume(item, open: true) }
                Button("Discard", role: .destructive) { consume(item, open: false) }
                Button("Later", role: .cancel) { }
            } message: { item in Text(item.url.absoluteString) }
            .alert("Shared links", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
            .onChange(of: scenePhase) { if $0 == .active { offer() } }
            .task {
                guard !configured else { return }
                configured = true
#if DEBUG || DRIFTLOOM_DEVICE_TESTING
                seedForTesting()
#endif
                offer()
            }
    }

    private func inbox() -> SharedLinkInbox? {
#if DEBUG || DRIFTLOOM_DEVICE_TESTING
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--shared-inbox-smoke"), args.contains("--library-smoke-run") {
            return SharedLinkInbox(directory: libraryFileURL().deletingLastPathComponent().appendingPathComponent("shared-links"))
        }
#endif
        return SharedLinkInbox.configured()
    }
    private func offer() {
        guard entry == nil, let inbox = inbox() else { return }
        do { entry = try inbox.next() }
        catch { self.error = String(localized: "Couldn't read shared links. Try sharing the link again.") }
    }
    private func consume(_ item: SharedLinkInbox.Entry, open: Bool) {
        guard let inbox = inbox() else { return }
        do { try inbox.remove(item) }
        catch { self.error = String(localized: "Couldn't remove this shared link. Try again."); return }
        if open { onOpen(item.url) }
    }
#if DEBUG || DRIFTLOOM_DEVICE_TESTING
    private func seedForTesting() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--shared-inbox-smoke"), args.contains("--library-smoke-run"), args.contains("--library-smoke-seed"),
           let flag = args.firstIndex(of: "--shared-inbox-url"), args.indices.contains(flag + 1),
           let url = URL(string: args[flag + 1]), let inbox = inbox(), (try? inbox.next()) == nil { _ = try? inbox.save(url) }
    }
#endif
}
