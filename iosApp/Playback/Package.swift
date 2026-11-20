// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DriftLoomPlayback",
    defaultLocalization: "en",
    platforms: [.iOS(.v15), .macOS(.v14)],
    products: [
        .library(name: "DriftLoomPlayback", targets: ["DriftLoomPlayback"]),
        // Download progress shared by the app and its Live Activity widget extension.
        .library(name: "DriftLoomActivity", targets: ["DriftLoomActivity"]),
        .executable(name: "PlaybackProbe", targets: ["PlaybackProbe"]),
        .executable(name: "BrowseProbe", targets: ["BrowseProbe"])
    ],
    dependencies: [
        // Vendored with a small change that keeps dubbed audio tracks; see Vendor/YouTubeKit/Package.swift.
        .package(path: "Vendor/YouTubeKit")
    ],
    targets: [
        .target(name: "DriftLoomPlayback", dependencies: ["YouTubeKit", "DriftLoomActivity"], resources: [.process("Localizable.xcstrings")]),
        .target(name: "DriftLoomActivity", resources: [.process("Localizable.xcstrings")]),
        .executableTarget(name: "PlaybackProbe", dependencies: ["DriftLoomPlayback"]),
        .executableTarget(name: "BrowseProbe", dependencies: ["DriftLoomPlayback"]),
        .testTarget(name: "DriftLoomPlaybackTests", dependencies: ["DriftLoomPlayback"])
    ]
)
