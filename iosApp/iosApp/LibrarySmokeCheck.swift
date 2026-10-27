// SPDX-License-Identifier: GPL-3.0-or-later
import DriftLoomPlayback
import Foundation

@MainActor
func makeLibraryStore() -> LibraryStore {
    let url = libraryFileURL()
    let recoveryError: String?
    do { try LibraryTransfer.recover(directory: url.deletingLastPathComponent()); recoveryError = nil }
    catch { recoveryError = "An interrupted import couldn't be recovered. Your files have been preserved; library edits are disabled." }
    let store = LibraryStore(fileURL: url)
    if let recoveryError { store.blockForRecovery(recoveryError) }
    return store
}

@MainActor
func makePlaylistStore() -> PlaylistStore {
    let directory = libraryFileURL().deletingLastPathComponent()
    let recoveryError: String?
    do { try LibraryTransfer.recover(directory: directory); recoveryError = nil }
    catch { recoveryError = "An interrupted import couldn't be recovered. Your files have been preserved; playlist edits are disabled." }
    let store = PlaylistStore(fileURL: directory.appendingPathComponent("playlists.json"))
    if let recoveryError { store.blockForRecovery(recoveryError) }
    return store
}

@MainActor
func makeSubscriptionGroups() -> SubscriptionGroups {
    let directory = libraryFileURL().deletingLastPathComponent()
    let recoveryError: String?
    do { try LibraryTransfer.recover(directory: directory); recoveryError = nil }
    catch { recoveryError = "An interrupted import couldn't be recovered. Group edits are disabled and saved files are preserved." }
    let store = SubscriptionGroups(fileURL: directory.appendingPathComponent("subscription-groups.json"))
    if let recoveryError { store.blockForRecovery(recoveryError) }
    return store
}

@MainActor
func libraryFileURL() -> URL {
#if DEBUG || DRIFTLOOM_DEVICE_TESTING
    let arguments = ProcessInfo.processInfo.arguments
    if let flag = arguments.firstIndex(of: "--library-smoke-run"), arguments.indices.contains(flag + 1),
       arguments[flag + 1].range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil {
        let url = LibraryStore.defaultFileURL.deletingLastPathComponent()
            .appendingPathComponent("SmokeTests", isDirectory: true)
            .appendingPathComponent(arguments[flag + 1], isDirectory: true)
            .appendingPathComponent("library.json")
        return url
    }
#endif
    return LibraryStore.defaultFileURL
}

#if DEBUG || DRIFTLOOM_DEVICE_TESTING
@MainActor
func runLibrarySmokeSetup(_ library: LibraryStore) {
    let arguments = ProcessInfo.processInfo.arguments
    if arguments.contains("--library-smoke-seed") {
        let video = BrowseItem(contentID: "11-9ZaYiTPE", kind: .video, title: "NDLS404 - SENSOJI")
        let channel = BrowseItem(contentID: "UCUb-HI7Kd-Dr1fBvYjV1IYg", kind: .channel, title: "ndls 404")
        if !library.isSaved(video.contentID) { library.toggleSaved(video) }
        if !library.isSubscribed(channel.contentID) { library.toggleSubscription(channel) }
        if library.saved.count == 1, library.subscriptions.count == 1, library.lastError == nil {
            NSLog("DriftLoomLibrarySmoke: PASS saved video and subscription persisted")
        } else { NSLog("DriftLoomLibrarySmoke: FAIL seeding") }
    }
    if arguments.contains("--library-smoke-verify") {
        if library.saved.count == 1, library.subscriptions.count == 1,
           library.history.contains(where: { $0.item.contentID == "11-9ZaYiTPE" }), library.lastError == nil {
            NSLog("DriftLoomLibrarySmoke: PASS saved video, subscription, and real playback history survived relaunch")
        } else { NSLog("DriftLoomLibrarySmoke: FAIL relaunch verification") }
    }
}
#endif
