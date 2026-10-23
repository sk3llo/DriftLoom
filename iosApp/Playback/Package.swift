// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DriftLoomPlayback",
    platforms: [.iOS("18.2"), .macOS(.v14)],
    products: [
        .library(name: "DriftLoomPlayback", targets: ["DriftLoomPlayback"]),
        .executable(name: "PlaybackProbe", targets: ["PlaybackProbe"])
    ],
    dependencies: [
        .package(url: "https://github.com/alexeichhorn/YouTubeKit.git",
                 revision: "e5b7d0396ce12bf3444f0d209e8436c83373b7af")
    ],
    targets: [
        .target(name: "DriftLoomPlayback", dependencies: ["YouTubeKit"]),
        .executableTarget(name: "PlaybackProbe", dependencies: ["DriftLoomPlayback"]),
        .testTarget(name: "DriftLoomPlaybackTests", dependencies: ["DriftLoomPlayback"])
    ]
)
