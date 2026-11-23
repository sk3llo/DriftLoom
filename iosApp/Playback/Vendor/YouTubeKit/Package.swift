// swift-tools-version:5.9
// YouTubeKit by Alexander Eichhorn (MIT, see LICENSE), vendored from
// https://github.com/alexeichhorn/YouTubeKit at e5b7d0396ce12bf3444f0d209e8436c83373b7af.
// DriftLoom change: dubbed audio streams are kept (one per itag and language) so the player can
// offer every audio track; DriftLoomPlayback picks the original by default.

import PackageDescription

let package = Package(
    name: "YouTubeKit",
    products: [
        .library(
            name: "YouTubeKit",
            targets: ["YouTubeKit"]),
    ],
    targets: [
        .target(
            name: "YouTubeKit",
            dependencies: [],
            resources: [.process("Resources")]),
    ]
)
