// SPDX-License-Identifier: GPL-3.0-or-later
import DriftLoomPlayback
import Foundation
import UserNotifications

extension Notification.Name {
    static let driftLoomOpenDownloads = Notification.Name("DriftLoom.openDownloads")
}

/// Local notifications when a download finishes or fails. Permission is asked when the first
/// download starts; tapping opens Downloads, and failures offer a Retry action.
@MainActor
final class DownloadNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = DownloadNotifier()
    static let failureCategory = "DriftLoom.downloadFailed", retryAction = "DriftLoom.retry"
    private let center = UNUserNotificationCenter.current()
    private var asked = false

    func install() {
        center.delegate = self
        let retry = UNNotificationAction(identifier: Self.retryAction, title: "Retry", options: [])
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.failureCategory, actions: [retry], intentIdentifiers: [])])
    }
    /// Asked once per launch at most; isolated test runs only ask when explicitly requested.
    func requestAuthorizationIfNeeded() {
        guard !asked else { return }
        asked = true
#if DEBUG || DRIFTLOOM_DEVICE_TESTING
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--library-smoke-run"), !arguments.contains("--download-notifications") { return }
#endif
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    func finished(_ record: DownloadRecord) {
        post(record, title: "Downloaded", body: record.item.title + " is ready to watch offline.", failed: false)
    }
    func failed(_ record: DownloadRecord) {
        post(record, title: "Download failed", body: record.item.title + (record.error.map { " — " + $0 } ?? ""), failed: true)
    }
    private func post(_ record: DownloadRecord, title: String, body: String, failed: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body; content.sound = .default
        content.threadIdentifier = "DriftLoom.downloads"
        content.userInfo = ["download": record.id.uuidString]
        if failed { content.categoryIdentifier = Self.failureCategory }
        // One notification per job: a retry's result replaces the earlier failure.
        let request = UNNotificationRequest(identifier: "download-" + record.id.uuidString, content: content, trigger: nil)
#if DEBUG || DRIFTLOOM_DEVICE_TESTING
        center.getNotificationSettings { settings in
            NSLog("DriftLoomNotificationSmoke: authorization=%d posting %@", settings.authorizationStatus.rawValue, title)
        }
        center.add(request) { error in NSLog("DriftLoomNotificationSmoke: %@ %@", error == nil ? "DELIVERED" : "FAIL", error?.localizedDescription ?? title) }
#else
        center.add(request)
#endif
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = (response.notification.request.content.userInfo["download"] as? String).flatMap(UUID.init(uuidString:))
        let action = response.actionIdentifier
        Task { @MainActor in
            if action == Self.retryAction, let id { DownloadManager.shared.retry(id) }
            else { NotificationCenter.default.post(name: .driftLoomOpenDownloads, object: nil) }
            completionHandler()
        }
    }
}
