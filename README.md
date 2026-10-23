# DriftLoom

DriftLoom is a personal fork of [NewPipe](https://github.com/TeamNewPipe/NewPipe),
based on version 0.29.1. This repository preserves the upstream Git history and
GPL-3.0-or-later license, contributor credits, and third-party library identities.

## Current status

- Android app rebranded as DriftLoom, including application IDs, resources, and source namespaces.
- YouTube HTTP 403 recovery: retry eligible videos with the available HLS stream once per queue item.
- Regression coverage for the playback recovery is included in the Android instrumentation tests.
- Initial iOS playback: paste a YouTube URL, resolve streams locally, and play HLS or a compatible
  combined audio/video stream through AVPlayer. A forbidden stream can be refreshed once while
  preserving playback position. The shared Compose settings/about foundation is retained.
- iOS search, subscriptions, downloads, queues, and background/lock-screen controls are not yet ported.

The earlier playback fix was verified on an Android phone before this rebrand.
The rename itself does not imply a new device test or an installed update.
The initial iOS implementation is tested separately as described below.

## Build Android

Use JDK 21 and an Android SDK with the compile SDK specified in
`buildSrc/src/main/kotlin/ProjectConfig.kt`.

```sh
./gradlew :app:assembleDebug --no-configuration-cache
./gradlew :app:assembleRelease --no-configuration-cache
```

Release builds use optimization and resource shrinking. Signing keys must be supplied
locally and must never be committed. The release application ID is `org.schabi.driftloom`.
Upstream automatic updates require the upstream signing certificate and are unavailable
for locally signed DriftLoom builds.

## Build and test iOS

Use Xcode 26.6 or a compatible newer version, JDK 21, and the Android SDK required to configure
this multiplatform Gradle project. Open `iosApp/iosApp.xcodeproj`, select the `iosApp` scheme,
and choose an iPhone simulator. The host requires iOS 18.5 or later to match the bundled native
framework. A physical-device build also needs your Apple development team and signing setup.

Xcode builds `:shared:embedAndSignAppleFrameworkForXcode` and links the local
`iosApp/Playback` Swift package. The first build downloads Kotlin/Native dependencies.

```sh
swift test --package-path iosApp/Playback
swift run --package-path iosApp/Playback PlaybackProbe \
  'https://www.youtube.com/watch?v=11-9ZaYiTPE' --seek-60
```

The tests use a loopback HTTP server for real 403/404 failures and need no external network
access after dependency resolution. The optional probe uses
real YouTube requests, starts native playback, seeks to 60 seconds, and verifies progress past
65 seconds. Without `--seek-60`, it verifies the first three seconds instead. Availability can
vary with YouTube restrictions or extractor changes.

For an app-level simulator smoke check, launch a Debug build with
`--playback-smoke-url https://www.youtube.com/watch?v=11-9ZaYiTPE` and inspect the
`DriftLoomSmoke` log result. This path is compiled out of Release builds and does not activate
without the flag. Normal startup performs no extraction.

The iOS resolver uses [YouTubeKit](https://github.com/alexeichhorn/YouTubeKit), pinned to a
specific revision in `Package.swift` and the lockfiles. Only local extraction is enabled;
its optional remote service is disabled. MIT attribution is included in the app's licenses
screen. The `StreamResolving` interface allows replacing the extractor independently of the UI.

## Development

The project includes the Android app (`app`), shared Kotlin/Compose module (`shared`),
iOS host (`iosApp`), and desktop host (`desktopApp`). Repository:
[sk3llo/DriftLoom](https://github.com/sk3llo/DriftLoom).

NewPipeExtractor and other upstream dependencies retain their original artifact coordinates
and Java package names so published libraries continue to resolve correctly. Historical
upstream links and legal attribution also retain their original names.

## License and attribution

Licensed under [GPL-3.0-or-later](LICENSE). DriftLoom is an independent fork of NewPipe;
it is not an official Team NewPipe release. Existing artwork and contributor copyright
notices are retained from upstream. See [NewPipe](https://github.com/TeamNewPipe/NewPipe)
for the original project and its contributors.
