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
  preserving playback position. Native SwiftUI navigation and About screens support iOS 15 onward.
- iOS Discover: direct YouTube search for videos, Shorts, channels, and playlists; channel uploads,
  playlist and Mix contents, related videos, and paginated results. Results open in the native player.
- iOS Library: saved videos, channel subscriptions, and watch history survive app restarts.
  Save from the player or a result menu, subscribe from a channel page, and reopen items from Library.
- iOS downloads, queues, subscription feeds, and background/lock-screen controls are not yet ported.

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

Use Xcode 26.6 or a compatible newer version. Open `iosApp/iosApp.xcodeproj`, select the
`iosApp` scheme, and choose an iPhone or simulator. The app and playback package target
**iOS 15.0 or later**: iPhone 6s/6s Plus, all iPhone SE generations, iPhone 7, and newer models
running a supported OS. Older iPhones that cannot run iOS 15 are unsupported; this is not a
claim of support for every iPhone ever made. Availability of individual videos still depends on
YouTube and its stream formats.

The iOS app links the local `iosApp/Playback` Swift package directly. It no longer embeds the
Compose framework, whose bundled OS requirement blocked older phones. Android and desktop
retain the shared Kotlin module. Building iOS does not require Gradle, Java, or an Android SDK.
Navigation uses NavigationStack on iOS 16+ and NavigationView on iOS 15. Empty/error screens
and labeled buttons use iOS 15 APIs. A physical-device build needs your Apple development team
and signing setup; supply these locally rather than committing account identifiers or profiles.

```sh
swift test --package-path iosApp/Playback
swift run --package-path iosApp/Playback PlaybackProbe \
  'https://www.youtube.com/watch?v=11-9ZaYiTPE' --seek-60
swift run --package-path iosApp/Playback BrowseProbe 'NDLS404 SENSOJI' --play
```

The tests use a loopback HTTP server for real 403/404 failures and need no external network
access after dependency resolution. The optional probe uses
real YouTube requests, starts native playback, seeks to 60 seconds, and verifies progress past
65 seconds. Without `--seek-60`, it verifies the first three seconds instead. Availability can
vary with YouTube restrictions or extractor changes.

The browsing probe verifies live search, continuation requests, channels, playlists when present
in the results, Mix playlists, related-video pagination, and optionally native playback of a result. Browse parser and
store tests cover current/legacy renderer shapes, Shorts, unavailable pages, deduplication,
repeated continuation tokens, retry, and stale search/pagination responses.

The library stores versioned JSON locally in `Application Support/DriftLoom/library.json`.
Writes are atomic; corrupt or newer documents are preserved and block edits until reloaded.
History records playback once it starts, keeps the latest 500 distinct videos, and can be disabled,
removed individually, or cleared. Saved metadata contains no resolved stream URLs. Subscriptions
open the channel's uploads; there is no merged subscription feed, account sync, or backup import yet.
Library tests cover persistence, deletion, history limits and preferences, invalid documents,
write rollback, and real local-media playback recording.

For an app-level simulator smoke check, launch a Debug build with
`--playback-smoke-url https://www.youtube.com/watch?v=11-9ZaYiTPE` and inspect the
`DriftLoomSmoke` log result. This path is compiled out of Release builds and does not activate
without the flag. To check the Discover screen, use
`--browse-smoke-query 'NDLS404 SENSOJI'`. Add `--browse-smoke-play` to load another page and
open a result through the same callback as a row tap, then verify playback past 65 seconds.
Inspect the `DriftLoomBrowseSmoke` and `DriftLoomSmoke` log results. Normal startup performs
no browsing or playback requests until the user searches or opens a video.

To verify library persistence in Debug without touching the normal library, use
`--library-smoke-run UNIQUE_NAME --library-smoke-seed` with the playback smoke URL above.
After playback passes, terminate and relaunch with the same run name and
`--library-smoke-verify`; inspect `DriftLoomLibrarySmoke` for the cold-launch result.
Optional `--library-smoke-section History` or `Subscriptions` selects that Library screen.
These flags and fixtures are excluded from normal Release builds. For automated physical-device
verification of optimized code, explicitly pass
`SWIFT_ACTIVE_COMPILATION_CONDITIONS=DRIFTLOOM_DEVICE_TESTING` to a Release build. This opts
in to the same isolated checks without enabling DEBUG. Rebuild and install a normal Release
without that condition after verification. Never distribute the verification variant.

The iOS resolver uses [YouTubeKit](https://github.com/alexeichhorn/YouTubeKit), pinned to a
specific revision in `Package.swift` and the lockfiles. Only local extraction is enabled;
its optional remote service is disabled. MIT attribution is included in the app's licenses
screen. The `StreamResolving` interface allows replacing the extractor independently of the UI.
Browsing is a separate `Browsing` interface. Its client reads YouTube page data directly and
keeps continuation context in memory; it does not use a third-party browsing server or a
hard-coded web client version. Metadata currently uses English with Portugal as its content
region. Full localization and user-selectable regions remain future work.

Physical-device verification on 25 October 2026: a signed, optimized Release verification build
ran on an iPhone 7 with iOS 15.8.2. Live search, pagination, HLS playback, seeking past 65 seconds,
and saved-video/subscription/history persistence across restart passed. The normal Release build
excludes the opt-in checks. All 30 package tests pass in Debug and Release. Normal Release startup
was also checked on iPhone SE (3rd generation)/iOS 17.5 and iPhone 17 Pro/iOS 26.5 simulators.
Other supported models have not been individually tested; iOS 15.0 simulator execution is
unavailable on this Mac's current macOS version.

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
