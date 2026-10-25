# DriftLoom

DriftLoom is a personal fork of [NewPipe](https://github.com/TeamNewPipe/NewPipe),
based on version 0.29.1. This repository preserves the upstream Git history and
GPL-3.0-or-later license, contributor credits, and third-party library identities.

## Current status

- Android app rebranded as DriftLoom, including application IDs, resources, and source namespaces.
- YouTube HTTP 403 recovery: retry eligible videos with the available HLS stream once per queue item.
- Regression coverage for the playback recovery is included in the Android instrumentation tests.
- iOS 15+ native app with NewPipe-style main menu, configurable home tabs, compact rows, and search history.
- YouTube browsing: server-side video/channel/playlist filters, channel tabs exposed by the channel,
  playlist/Mix contents, related videos, and pagination. Subscription feeds use dated channel RSS entries.
- Video details, description, persistent mini-player, editable queue, play-next/enqueue, finite shuffle,
  repeat, playback speed, maximum-resolution caps, and captions exposed by the current media asset.
- Background-audio configuration, Now Playing/remote command integration, and AVKit Picture in Picture support.
  Physical background playback has been verified; not every system control or PiP scenario has been tested.
- Saved videos, subscriptions, history, local playlists, and remote playlist bookmarks persist locally.
  Resume positions are bounded, tied to history recording, and removed with deleted history.
- Appearance, home-tab ordering/visibility, search/watch history controls, and resume preferences are implemented.
- This is an incremental parity rework, not a complete NewPipe port. Downloads, comments, full format/caption
  extraction, subscription groups, backup migration, extra services, and remaining settings are still pending.
  See [the rework checklist](docs/ios-newpipe-parity.md).

The earlier playback fix was verified on an Android phone before this rebrand.
The rename itself does not imply a new device test or an installed update.
The iOS implementation is tested separately as described below.

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
open the channel's available tabs; What's New merges their RSS feeds by publication date.
Account sync and backup import remain unimplemented.
Library tests cover persistence, deletion, history limits and preferences, invalid documents,
write rollback, and real local-media playback recording.

For an app-level simulator smoke check, launch a Debug build with
`--playback-smoke-url https://www.youtube.com/watch?v=11-9ZaYiTPE` and inspect the
`DriftLoomSmoke` log result. This path is compiled out of Release builds and does not activate
without the flag. To check the search screen, use
`--browse-smoke-query 'NDLS404 SENSOJI'`. Add `--browse-smoke-play` to load another page and
open a result through the same callback as a row tap, then verify playback past 65 seconds.
Inspect the `DriftLoomBrowseSmoke` and `DriftLoomSmoke` log results. Browsing and playback start through user actions. Opening the subscription-feed home tab also
refreshes subscribed channels; background scheduled feed refresh is not implemented.

To verify library persistence in Debug without touching the normal library, use
`--library-smoke-run UNIQUE_NAME --library-smoke-seed` with the playback smoke URL above.
After playback passes, terminate and relaunch with the same run name and
`--library-smoke-verify`; inspect `DriftLoomLibrarySmoke` for the cold-launch result.
Optional `--library-smoke-section History` or `Subscriptions` selects that home section.
These flags and fixtures are excluded from normal Release builds. For automated physical-device
verification of optimized code, explicitly pass
`SWIFT_ACTIVE_COMPILATION_CONDITIONS=DRIFTLOOM_DEVICE_TESTING` to a Release build. This opts
in to the same isolated checks without enabling DEBUG. Rebuild and install a normal Release
without that condition after verification. Never distribute the verification variant.

Add --background-smoke to a playback smoke run, wait for DriftLoomBackgroundSmoke: READY,
bring another app forward, and check that playback advances in the background. This is an explicit
test operation and is also excluded from normal Release builds.

The shared iosApp scheme includes DriftLoomUITests. Run UI tests on an available simulator
with an isolated library and opt-in checks, for example:

```sh
xcodebuild test -project iosApp/iosApp.xcodeproj -scheme iosApp -configuration Release \
  -destination 'platform=iOS Simulator,name=iPhone SE (3rd generation),OS=17.5' \
  CODE_SIGNING_ALLOWED=NO SWIFT_ACTIVE_COMPILATION_CONDITIONS=DRIFTLOOM_DEVICE_TESTING
```

Each UI journey uses its own test library and preferences; it never edits the normal library.

The iOS resolver uses [YouTubeKit](https://github.com/alexeichhorn/YouTubeKit), pinned to a
specific revision in `Package.swift` and the lockfiles. Only local extraction is enabled;
its optional remote service is disabled. MIT attribution is included in the app's licenses
screen. The `StreamResolving` interface allows replacing the extractor independently of the UI.
Browsing is a separate `Browsing` interface. Its client reads YouTube page data directly and
keeps continuation context in memory; it does not use a third-party browsing server or a
hard-coded web client version. Metadata currently uses English with Portugal as its content
region. Full localization and user-selectable regions remain future work.

Verification on 25 October 2026: all 43 package tests pass in Debug and Release. Three optimized
UI journeys pass on iPhone SE (3rd generation)/iOS 17.5: drawer/settings/subscriptions; search,
video, minimize/reopen, and returning to search; playlist creation, restart persistence, and play-all.
Live probes verified search filters, channel feeds, playlists, Mixes, and related pagination.
On a physical iPhone 7/iOS 15.8.2, optimized playback advanced past 65 seconds, and advanced for
eight seconds while another app was foreground. All three core tap-based UI journeys also passed on
that physical device. The normal signed Release build was installed in place after testing.
Portrait and landscape were checked on the SE simulator. Broader parity and device coverage remain work
in progress. iOS 15.0 simulator execution is unavailable on this Mac's current macOS version.

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
