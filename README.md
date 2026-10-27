# DriftLoom

DriftLoom is a personal fork of [NewPipe](https://github.com/TeamNewPipe/NewPipe),
based on version 0.29.1. This repository preserves the upstream Git history and
GPL-3.0-or-later license, contributor credits, and third-party library identities.

## Current status

- Android app rebranded as DriftLoom, including application IDs, resources, and source namespaces.
- YouTube HTTP 403 recovery: retry eligible videos with the available HLS stream once per queue item.
- Regression coverage for the playback recovery is included in the Android instrumentation tests.
- iOS 15+ native app with NewPipe-style main menu, configurable home tabs, compact rows, and search history.
- YouTube browsing: server-side type/date/duration/sort filters, selectable content language/region, and channel tabs,
  playlist/Mix contents, related videos, and pagination. Subscription feeds use dated channel RSS entries.
- Video details, description, views/date, comments and replies, and a persistent mini-player.
- Editable queues survive relaunch without automatically playing; play-next/enqueue, finite shuffle,
  repeat, speed, resolution limits, and supported extracted playback formats are available.
  YouTube subtitle tracks (uploaded and auto-generated) can be chosen in the player and are drawn over the video,
  including fullscreen; a preferred language turns them on automatically. Captions embedded in the media asset
  still use native controls when no YouTube track list is available.
- Background-audio configuration, Now Playing/remote command integration, and Picture in Picture.
  Physical background playback and starting PiP from the inline player have been verified on an iPhone 7;
  not every system control or PiP scenario has been tested.
- Chapters from the description's timestamps (YouTube's rule: at least three, starting at 0:00, 10 s apart):
  gaps in the seek bar, the chapter name while scrubbing and under the bar, and a tappable list in Description.
- Double-tap the left or right half of the video to skip 10 s back or forward.
- Drag the video or the player's header down to shrink it into the mini-player bar, as in NewPipe; a short drag
  springs back.
- Comments can be sorted by top or newest (YouTube's own orders, from the first comments page). SoundCloud
  comments have no sort menu.
- iPad: in landscape the player and its details sit beside the Related/Comments/Description/Queue tabs; portrait
  stacks them like the phone. Turning an iPad doesn't force full screen.
- Autoplay (Settings → Playback, on by default): when the last video in the queue ends, the first related video
  not already queued plays next. Repeat modes keep the queue as it is.
- Default resolution caps for Wi-Fi and for mobile data (Settings → Playback, automatic by default); a choice in
  the player's menu changes only the current video.
- Inline player with DriftLoom's own controls, like NewPipe's: play/pause, skip back/forward 10 s, playback speed,
  one seek bar under the video, fullscreen, Picture in Picture (where supported) and AirPlay. Tap the video to show them;
  they hide after 3 s while playing. Fullscreen opens Apple's full player with its native controls;
  turning the phone sideways while watching opens it too, and turning it upright again closes it.
  Download sits in the action row under the title (Save, Share, Queue, Playlist, Download).
- Saved videos, subscriptions, history, local playlists, and remote playlist bookmarks persist locally.
  Resume positions are bounded, tied to history recording, and removed with deleted history.
- Appearance, home-tab visibility, one combined tab order across built-in sections, pinned channels/playlists and
  pinned local playlists, search/watch history controls, subtitle language/size, and resume preferences are implemented.
- Downloads have persisted jobs, cancellation/retry, native HLS/file background transfers, and local playback.
  HLS download completion and offline playback have been verified on a physical iPhone 7.
  Downloads can wait for Wi-Fi (the default) or use mobile data, show the storage they use, and can save
  subtitles in a chosen language for offline playback.
- Library JSON backup/export and reviewed merge imports preserve a pre-import recovery copy.
  NewPipe subscription JSON and ZIP database migration support YouTube subscriptions, history,
  ordered local playlists (including duplicates), and remote playlist bookmarks. Android preferences,
  stream positions, downloaded bytes, and unsupported services are excluded and reported.
- Resolutions above the best combined stream (typically 480p–2160p, limited to codecs the device decodes)
  play and download from YouTube's separate video and audio streams, combined without re-encoding; 1080p merged playback and a merged download were verified on the iPhone 7.
- This is an incremental parity rework, not a complete NewPipe port. Services beyond YouTube and SoundCloud
  and remaining settings and device scenarios still need implementation or verification.
- Opt-in Live, Gaming, Podcasts and Movie trailers kiosks; opt-in auto-translated subtitles (YouTube currently
  rate-limits these from the test network); NewPipe ZIP imports can also apply NewPipe's settings and home tabs
  from `preferences.json`. Real (WAL-mode) NewPipe backups now import; earlier builds rejected them.
- SoundCloud: search (tracks, users, playlists), profiles with paged tracks, playlists of any size, related
  tracks, comments, a trending home section, opening soundcloud.com links, playback with artwork, saving,
  history, local playlists, queues, subscriptions with feed entries, and offline downloads. Access follows
  NewPipe: the public client ID from soundcloud.com's own scripts and SoundCloud's web API (api-v2).
  DRM-only tracks (about 1 in 15 in a sample) and preview-only tracks can't be played and say so.
- Download progress: a strip above the mini-player on every screen, notifications when a download finishes or
  fails (with Retry), and on iOS 16.1+ a Live Activity with a progress bar on the lock screen and in the
  Dynamic Island. iOS 15 devices get the strip and notifications only.
- Seek-bar previews: a seek bar under the video shows YouTube's storyboard frame and time while dragging
  (fetched with the captions in one player request; not in fullscreen, offline or for SoundCloud, where the
  bubble shows only the time).
- New-video notifications (Settings → Notifications, off by default): a background refresh checks
  subscriptions and notifies about recent uploads (one per video, or a summary for more than three); tapping
  plays the video or opens What's new. iOS decides when background refresh runs.
- YouTube Google Takeout import, as in NewPipe: the Takeout ZIP (folder and file names may be translated),
  its subscriptions.csv, or the older subscriptions.json. Only subscriptions are imported; your own channel
  file in the ZIP is ignored. Settings → Backup and import has the steps and a link to Takeout.
- Interface in English, Ukrainian and Portuguese (Brazilian wording, used for every Portuguese region), following
  the iPhone's language or the per-app language in iOS Settings. Counts use each language's plural forms.
  Translations live in string catalogs: `iosApp/iosApp`, `iosApp/DriftLoomShare` and the two package targets.
- Opening links from other apps: "DriftLoom" in the share sheet (Safari, the YouTube and SoundCloud apps, …) and a
  `driftloom://open?url=<link>` URL scheme (also usable from Shortcuts). Videos and tracks play; YouTube channels,
  @handles and playlists, and SoundCloud profiles and playlists open as pages, including on.soundcloud.com links.
  Sharing a link into DriftLoom was confirmed by hand on the iPhone 7 (iOS 15.8.2).
- When YouTube refuses extraction (for example "confirm you're not a bot" on a rate-limited network),
  playback and downloads report that in plain language. DriftLoom does not try to bypass these checks.
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
hard-coded web client version. Browsing defaults to English/Portugal, with content language and
region controls for new requests (separate from the interface language).

Verification on 25 October 2026: all 43 package tests pass in Debug and Release. Three optimized
UI journeys pass on iPhone SE (3rd generation)/iOS 17.5: drawer/settings/subscriptions; search,
video, minimize/reopen, and returning to search; playlist creation, restart persistence, and play-all.
Live probes verified search filters, channel feeds, playlists, Mixes, and related pagination.
On a physical iPhone 7/iOS 15.8.2, optimized playback advanced past 65 seconds, and advanced for
eight seconds while another app was foreground. All three core tap-based UI journeys also passed on
that physical device. The normal signed Release build was installed in place after testing.
Portrait and landscape were checked on the SE simulator. Broader parity and device coverage remain work
in progress. iOS 15.0 simulator execution is unavailable on this Mac's current macOS version.

Verification on 26 October 2026: 63 package tests pass in Debug and Release. Five optimized UI
journeys pass on both iPhone SE (3rd generation)/iOS 17.5 and physical iPhone 7/iOS 15.8.2:
comments, playlist/queue relaunch, download controls, settings/backup navigation, and search/player
restoration. The physical download journey completes an HLS download and opens its local asset;
simulator coverage of downloads stops at chooser/job UI. Separate phone checks verified that the
HLS cache is playable offline and local playback advances, including after cold launch.
NewPipe ZIP migration is covered by stored/deflated SQLite schema fixtures, not a claim that every
historical Android backup version has been tested. The current signed app is built as normal Release
without verification flags; the temporary test runner and isolated download test assets are removed
after testing.

The browsing checkpoint adds persistent channel/remote-playlist home tabs, optional live search
suggestions, and the official regional YouTube music chart. All 71 package tests pass in Debug and
Release. Eight UI journeys pass on the SE simulator. On the physical iPhone 7, seven journeys passed
in the full run, and the search/player journey passed on focused rerun; both the app search button
and keyboard submission were checked separately. These checks do not imply full NewPipe parity.

The subscription checkpoint adds group creation/rename/reorder/removal, channel membership, and group
filtering in subscriptions and What's new. The feed also has date and watched-video filters. Native
version-2 backups include groups; version-1 imports preserve existing groups. Supported Android group
membership/order migrates from ZIP backups, with group icons excluded. All 82 package tests pass in
Debug and Release; all 10 UI journeys pass on the SE simulator. The physical iPhone group journey and
nearby settings, pinned-tab, and search/player checks pass on optimized builds. The live search suite
encountered an unreadable upstream response on an earlier run; the final full simulator run passed.

Verification on 26 October 2026 (subtitles, download settings, home tabs): 103 package tests pass and all
13 UI journeys pass on the iPhone SE (3rd generation) simulator in optimized Release. On the physical
iPhone 7/iOS 15.8.2, Xcode 26.6 refuses to host UI tests ("Logic Testing Unavailable"), so the optimized
DRIFTLOOM_DEVICE_TESTING build was launched with smoke flags through `pymobiledevice3 developer dvt launch`.
Playback advanced past 65 seconds over HLS with English subtitles shown at 61 s; an HLS download saved
English subtitles, and both played from local files, again after a cold relaunch. `--download-smoke-cleanup`
then removed the test download, and the normal Release build was reinstalled. YouTube's bot check refused
the usual fixture video on this network, so device checks used `--download-smoke-video dQw4w9WgXcQ`.

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
