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

/// --soundcloud-smoke: client ID discovery, search, profile, playlist, related and trending on the device.
@MainActor
func runSoundCloudSmokeCheck() async {
    guard ProcessInfo.processInfo.arguments.contains("--soundcloud-smoke") else { return }
    let client = YouTubeBrowsingClient()
    do {
        let tracks = try await client.page(for: .soundCloudSearch("lofi hip hop", .tracks))
        NSLog("DriftLoomSoundCloudSmoke: PASS search tracks=%d first=%@", tracks.items.count, tracks.items.first?.contentID ?? "-")
        let users = try await client.page(for: .soundCloudSearch("lofi", .users))
        for user in users.items.prefix(6) {
            if let page = try? await client.page(for: user.destination!), !page.items.isEmpty {
                NSLog("DriftLoomSoundCloudSmoke: PASS profile %@ tracks=%d", page.title, page.items.count); break
            }
        }
        if let playlist = try await client.page(for: .soundCloudSearch("lofi", .playlists)).items.first?.destination {
            NSLog("DriftLoomSoundCloudSmoke: PASS playlist tracks=%d", try await client.page(for: playlist).items.count)
        }
        if let first = tracks.items.first {
            NSLog("DriftLoomSoundCloudSmoke: PASS related=%d", try await client.page(for: .related(first.contentID)).items.count)
        }
        NSLog("DriftLoomSoundCloudSmoke: PASS trending=%d", try await client.page(for: .soundCloudTrending).items.count)
    } catch { NSLog("DriftLoomSoundCloudSmoke: FAIL %@", error.localizedDescription) }
    NSLog("DriftLoomSoundCloudSmoke: DONE")
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

#if DEBUG || DRIFTLOOM_DEVICE_TESTING
import AVFoundation

/// --autoplay-smoke: play a video from the queue near its end and require a related video to follow.
/// Also reports the resolution cap in effect, so `-wifiMaximumHeight 360` can be checked.
@MainActor
func runAutoplaySmokeCheck(_ queue: PlaybackQueue) async {
    guard ProcessInfo.processInfo.arguments.contains("--autoplay-smoke") else { return }
    let playback = queue.playback
    playback.player.isMuted = true
    queue.start([BrowseItem(contentID: "dQw4w9WgXcQ", kind: .video, title: "Smoke")])
    for _ in 0..<60 {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        if playback.player.currentItem?.status == .readyToPlay, playback.player.currentItem?.duration.seconds.isFinite == true { break }
    }
    guard let item = playback.player.currentItem, item.duration.seconds.isFinite else { NSLog("DriftLoomAutoplaySmoke: FAIL no playable item"); return }
    let limit = item.preferredMaximumResolution
    NSLog("DriftLoomAutoplaySmoke: cap=%d preferredMaximumResolution=%.0fx%.0f autoplay=%d", playback.maximumHeight, limit.width, limit.height, queue.autoplaysRelated ? 1 : 0)
    await playback.player.seek(to: CMTime(seconds: item.duration.seconds - 4, preferredTimescale: 600))
    playback.resume()
    for _ in 0..<45 {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        if queue.entries.count > 1, let id = playback.videoID, id != "dQw4w9WgXcQ" {
            NSLog("DriftLoomAutoplaySmoke: PASS related video %@ (%@) follows; queue=%d", id, queue.entries.last?.item.title ?? "", queue.entries.count)
            return
        }
    }
    NSLog("DriftLoomAutoplaySmoke: FAIL no related video followed (queue=%d)", queue.entries.count)
}
#endif
