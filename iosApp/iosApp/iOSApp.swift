import SwiftUI

@main
struct iOSApp: App {
    @UIApplicationDelegateAdaptor(DownloadAppDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}