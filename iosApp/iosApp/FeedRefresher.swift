// SPDX-License-Identifier: GPL-3.0-or-later
import BackgroundTasks
import DriftLoomPlayback
import Foundation
import UserNotifications

extension Notification.Name {
    static let driftLoomOpenFeed = Notification.Name("DriftLoom.openFeed")
    /// Object: a YouTube video ID or SoundCloud track ID to play.
    static let driftLoomPlayVideo = Notification.Name("DriftLoom.playVideo")
}

/// Checks subscriptions for new uploads in the background (BGAppRefreshTask) and notifies.
/// iOS decides when the task runs, based on how the app is used and on Background App Refresh.
@MainActor
final class FeedRefresher {
    static let shared = FeedRefresher()
    static let taskID = "net.driftloom.app.feedRefresh"
    private let stateKey = "feedCheckState"

    /// Must run before the app finishes launching.
    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskID, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            Task { @MainActor in FeedRefresher.shared.handle(task) }
        }
    }
    var isEnabled: Bool { AppPreferences(defaults: makeAppDefaults()).notifiesNewVideos }

    func schedule() {
        guard isEnabled else { cancel(); return }
        let request = BGAppRefreshTaskRequest(identifier: Self.taskID)
        request.earliestBeginDate = Date().addingTimeInterval(30 * 60)
        do { try BGTaskScheduler.shared.submit(request) } catch {
#if DEBUG || DRIFTLOOM_DEVICE_TESTING
            NSLog("DriftLoomFeedSmoke: SCHEDULE-FAILED %@", error.localizedDescription)
#endif
            return
        }
#if DEBUG || DRIFTLOOM_DEVICE_TESTING
        NSLog("DriftLoomFeedSmoke: SCHEDULED %@", request.earliestBeginDate.map { "\($0)" } ?? "-")
#endif
    }
    func cancel() { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskID) }

    private func handle(_ task: BGAppRefreshTask) {
        schedule()
        let work = Task { @MainActor in
            let posted = await check()
            task.setTaskCompleted(success: posted >= 0)
        }
        task.expirationHandler = { work.cancel() }
    }

    /// Fetch, compare with the last check, post notifications. Returns how many new videos were found (-1 when skipped).
    @discardableResult func check() async -> Int {
        guard isEnabled else { return -1 }
        let defaults = makeAppDefaults()
        let library = LibraryStore(fileURL: libraryFileURL())
        let channels = library.subscriptions.map(\.item.contentID)
        guard !channels.isEmpty else { return 0 }
        let state = defaults.data(forKey: stateKey).flatMap { try? JSONDecoder().decode(FeedCheckState.self, from: $0) } ?? FeedCheckState()
        let fetched = await FeedCheck.fetch(channelIDs: channels)
        guard !Task.isCancelled, !fetched.videos.isEmpty else { return 0 }
        let result = FeedCheck.evaluate(fetched.videos, state: state)
        if let data = try? JSONEncoder().encode(result.state) { defaults.set(data, forKey: stateKey) }
        let center = UNUserNotificationCenter.current()
        for message in FeedCheck.messages(for: result.newVideos) {
            let content = UNMutableNotificationContent()
            content.title = message.title; content.body = message.body; content.sound = .default
            content.threadIdentifier = "DriftLoom.feed"
            content.userInfo = message.videoID.map { ["feedVideo": $0] } ?? ["feed": true]
            try? await center.add(UNNotificationRequest(identifier: "feed-" + (message.videoID ?? UUID().uuidString), content: content, trigger: nil))
        }
#if DEBUG || DRIFTLOOM_DEVICE_TESTING
        NSLog("DriftLoomFeedSmoke: checked channels=%d videos=%d failed=%d new=%d", channels.count, fetched.videos.count, fetched.failed, result.newVideos.count)
#endif
        return result.newVideos.count
    }

#if DEBUG || DRIFTLOOM_DEVICE_TESTING
    /// --feed-check-smoke runs a check now; --feed-check-forget N first drops the N newest videos from the
    /// recorded state so the next check (now, or iOS's background one) announces them.
    func runSmokeCheck() async {
        let arguments = ProcessInfo.processInfo.arguments
        let defaults = makeAppDefaults()
        if arguments.contains("--feed-notifications-on") { AppPreferences(defaults: defaults).setNotifiesNewVideos(true) }
        // --feed-check-channel UC…: subscribe the isolated test library to a frequently uploading channel.
        if arguments.contains("--library-smoke-run"), let flag = arguments.firstIndex(of: "--feed-check-channel"), arguments.indices.contains(flag + 1) {
            let library = LibraryStore(fileURL: libraryFileURL())
            let channel = BrowseItem(contentID: arguments[flag + 1], kind: .channel, title: "Feed test channel")
            if !library.isSubscribed(channel.contentID) { _ = library.toggleSubscription(channel) }
        }
        if let flag = arguments.firstIndex(of: "--feed-check-forget"), arguments.indices.contains(flag + 1), let count = Int(arguments[flag + 1]),
           let data = defaults.data(forKey: stateKey), var state = try? JSONDecoder().decode(FeedCheckState.self, from: data) {
            state.seen.removeLast(min(count, state.seen.count))
            defaults.set(try? JSONEncoder().encode(state), forKey: stateKey)
        }
        // Without --feed-check-smoke only the state is prepared, for a check iOS runs in the background.
        guard arguments.contains("--feed-check-smoke") else { return }
        let found = await check()
        NSLog("DriftLoomFeedSmoke: %@ new=%d", found >= 0 ? "PASS" : "FAIL disabled", found)
    }
#endif
}
