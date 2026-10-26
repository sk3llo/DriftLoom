// SPDX-License-Identifier: GPL-3.0-or-later
#if DEBUG || DRIFTLOOM_DEVICE_TESTING
import DriftLoomPlayback
import Foundation

/// Opt-in device checks for kiosks and NewPipe import. Compiled out of normal Release builds.
@MainActor
func runKioskSmokeCheck() async {
    guard ProcessInfo.processInfo.arguments.contains("--kiosk-smoke") else { return }
    for kiosk in YouTubeKiosk.allCases {
        do {
            let page = try await YouTubeBrowsingClient().page(for: .kiosk(kiosk))
            NSLog("DriftLoomKioskSmoke: %@ %@ items=%d", page.items.isEmpty ? "FAIL" : "PASS", kiosk.rawValue, page.items.count)
        } catch { NSLog("DriftLoomKioskSmoke: FAIL %@ %@", kiosk.rawValue, error.localizedDescription) }
    }
    NSLog("DriftLoomKioskSmoke: DONE")
}

/// --import-smoke NAME: preview and merge Documents/NAME into the isolated smoke library,
/// applying NewPipe settings too, then report what changed.
@MainActor
func runImportSmokeCheck(library: LibraryStore, playlists: PlaylistStore, groups: SubscriptionGroups, positions: PlaybackPositions,
                         preferences: AppPreferences, pinnedTabs: PinnedHomeTabs) async {
    let arguments = ProcessInfo.processInfo.arguments
    guard let flag = arguments.firstIndex(of: "--import-smoke"), arguments.indices.contains(flag + 1), arguments.contains("--library-smoke-run"),
          arguments[flag + 1].range(of: "^[A-Za-z0-9_.-]{1,64}$", options: .regularExpression) != nil else { return }
    let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(arguments[flag + 1])
    do {
        let plan = try LibraryTransfer.preview(Data(contentsOf: file))
        NSLog("DriftLoomImportSmoke: PREVIEW %@", plan.summary)
        for change in plan.settings?.changes ?? [] { NSLog("DriftLoomImportSmoke: SETTING %@", change) }
        try LibraryTransfer.apply(plan, library: library, playlists: playlists, groups: groups, positions: positions)
        if let settings = plan.settings { LibraryTransfer.applySettings(settings, preferences: preferences, library: library, pinnedTabs: pinnedTabs) }
        NSLog("DriftLoomImportSmoke: PASS subscriptions=%d history=%d playlists=%d theme=%@ tabs=%@", library.subscriptions.count, library.history.count,
              playlists.playlists.count, preferences.appearance, preferences.homeSections.map(\.rawValue).joined(separator: ","))
    } catch { NSLog("DriftLoomImportSmoke: FAIL %@", error.localizedDescription) }
}
#endif
