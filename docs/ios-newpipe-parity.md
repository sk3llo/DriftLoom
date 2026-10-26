# iOS NewPipe parity rework

Reference: the Android NewPipe 0.29.1-based implementation in this repository. Keep the
DriftLoom name, legal attribution, and iOS 15 minimum. Treat the Android layouts, menus,
and user journeys as the specification. The iOS app is not yet a full NewPipe port.

## Implementation order and current checkpoint

| Stage | Implemented in this checkpoint | Still required for full parity |
| --- | --- | --- |
| Navigation and browsing | Main drawer; subscriptions/feed/bookmarks/history home tabs; tab visibility/order; compact result rows and action menus; search history; server-side type/date/duration/sort filters; content language/region; available channel tabs, avatar/description/subscription controls; pagination; persisted channel/remote-playlist/local-playlist home tabs with one combined, interleaved order; optional live suggestions; official regional YouTube music chart; opt-in Live, Gaming, Podcasts and Movie trailers kiosks from the same YouTube sources NewPipe's extractor uses |  remaining metadata and visual comparison |
| Video details and mini-player | Inline native player; owner/subscription row; save/share/playlist/speed actions; related/description/comments tabs, replies, views/date; minimizing and returning without discarding search state | Remaining stream metadata; remaining detail actions; full visual parity |
| Queue and playback controls | Stable queue entries including duplicate videos; reorder/remove/play-next/enqueue; previous/next; finite shuffle; repeat; playlist play-all; resume positions; speed; HLS resolution caps; in-asset captions; YouTube subtitle tracks (manual and auto-generated) with a remembered language, text size and fullscreen overlay; opt-in YouTube machine translation into any offered language; background configuration and system remote commands; explicit native AVKit PiP capability; persisted queue/order/repeat/shuffle/speed/resolution without autoplay; extracted native format selection; separate video-only + audio formats above the best combined stream, played as an AVComposition (H.264, or AV1 only where hardware decodes it) | Automatic adaptive switching between separate formats; subtitle styling beyond size; exhaustive interruption/headphone/lock-screen/PiP tests |
| Subscriptions and playlists | Date-sorted RSS feed with bounded concurrent requests, deduplication, and partial-error reporting; local playlist CRUD/reorder; remote playlist bookmarks; existing library preserved; persisted subscription groups and membership; group filtering in subscriptions/feed; date and watched-video filters; native backup and supported Android group migration | Additional feed sources and controls; group icons and remaining Android settings migration |
| Downloads | Available HLS/muxed/audio format discovery; versioned job records; cancellation/retry with fresh URLs; iOS background transfer reconnection; delete controls; completed HLS cache validation and local playback verified on iPhone 7; Wi-Fi-only/any-network policy per job with waiting and relaunch recovery; storage usage; subtitles saved with a download for offline playback; separate video+audio downloads (two transfers, parts kept across relaunch, combined by passthrough export into one MP4) | broader file/audio and interrupted/background transfer tests |
| Settings, migration, services | Theme, home configuration, history controls, resume switch, content language/region; native library JSON backup; reviewed merge imports; atomic recovery journal and retained pre-import copies; NewPipe subscription JSON and ZIP/SQLite migration of supported YouTube library records | Full app preferences/queue/media backup;  remaining player/download settings; services beyond YouTube and SoundCloud (PeerTube, Bandcamp, media.ccc.de); SoundCloud entries in NewPipe backups |

## Storage and compatibility

- Existing library.json remains version 1, with its original saved videos, subscriptions, and history.
- New playlists.json is independently versioned; corrupt/newer files block writes and remain untouched.
- Playlist entries have independent UUIDs, so repeated videos can be moved/deleted individually.
- Search history, theme/home preferences, and bounded resume metadata use local preferences.
- Disabling watch-history recording also disables recording/resuming positions for new playback.
- Removing watch-history entries removes their resume positions.
- Resolved media URLs are not persisted in these stores or download job records.
- Queue metadata restores paused; fresh extraction occurs only when playback is requested.
- Downloads validate a completed local asset before exposing offline playback. HLS cache locations are
  normalized against the app container before persistence; files outside managed locations are rejected.
- Imports merge into current library data and keep current privacy preferences. A recovery journal rolls
  back library, playlists, and included subscription groups if writing fails or the app exits partway through an import. A retained copy is
  saved in PreImportBackups before changes.
- ZIP import reads only newpipe.db or driftloom.db, validates CRC and bounded decompression, and uses
  read-only SQLite with fixed SQL, row/text limits, and a VM instruction budget. Android Java-serialized
  preferences are never deserialized. Supported database shapes were tested with version-9 schema fixtures.
- iOS 15 uses NavigationView; newer systems use NavigationStack. UI components retain iOS 15 fallbacks.
- Empty menus, disabled feature placeholders, and arbitrary searches presented as trending/feed content
  must not stand in for unimplemented functionality.

## Verification gates

1. Package regression tests in Debug and Release.
2. Actual UI actions: saved data remains accessible; menus and settings work; search opens a video;
   minimizing/reopening returns to the same results; playlist creation survives relaunch and plays its queue.
3. Live YouTube probes for filters, pagination, channel RSS, playlists/Mixes, and related items.
4. Physical iPhone 7 Release verification for playback, seeking, persistence, and background advancement.
5. Normal signed Release built without test flags, installed in place, and launched after verification.
6. Record limitations and failed checks honestly; do not label this checklist complete until the remaining
   parity work is delivered and tested.

## Verification notes and next batch

The package suite currently contains 82 tests, including real-media pause/seek preservation on format
changes, queue restoration, both comment response shapes, ZIP/SQLite migration fixtures, corrupt data,
failed import rollback, and interrupted-import recovery. Live probes verify comments/replies and
combined search filters. HLS download/local playback is tested on hardware; simulator tests cover the
chooser and job UI without claiming a completed simulator HLS download.

On iOS 15, native toolbar accessibility frames moved outside their visible bounds after dismissing
sheets. Home/player controls now live in app headers with explicit hit areas. The physical download
and settings/import journeys are regression checks for that failure.

Live probes also verify suggestions and the official YouTube music chart. Pinned channel/remote-playlist
tabs use a separate versioned home-tabs.json; unreadable files remain untouched. The chart is explicitly
labeled as music from YouTube Charts, rather than general YouTube trending. Suggestions can be disabled.

Subscription groups use subscription-groups.json independently of the existing library. Group members
that are no longer subscribed are ignored by filters without destroying saved membership. Native
version-2 backups include groups; version-1 backups leave existing groups untouched. Three-file
recovery journals use version 2 so earlier builds refuse an interrupted import they cannot recover. Android group icons are not
migrated. Feed date/watched filters apply to the bounded recent RSS results, not the entire channel
archive. Switching groups clears the previous group's videos before the next feed completes.

Subtitles come from the iOS InnerTube client's caption list because web player caption URLs now need a
proof-of-origin token and return empty bodies. Only cue text and track labels are saved with downloads, never
the signed caption URL. External subtitles are drawn by the app over the video (inline and fullscreen) and are
not shown in Picture in Picture. Selecting a YouTube track turns off captions embedded in the media.

Home tab order is stored in home-tabs.json. The file stays at version 1 while it only contains pinned
channels/playlists, so earlier builds can still read it; pinning a local playlist or reordering across groups
writes version 2, which earlier builds refuse and leave untouched. Deleted playlists drop out of the order.

Separate formats: YouTube offers only low resolutions as combined video+audio files. DriftLoom pairs each
higher video-only resolution with the best AAC audio stream. Playback combines them in an AVComposition, so the
chosen resolution is fixed rather than adaptive; automatic playback still prefers HLS. Downloads fetch both
streams as separate transfers, record each finished part on the job, and combine them without re-encoding.
A 403 on either stream triggers the usual single refresh.

NewPipe ZIP imports now carry resume positions from `stream_state` for imported history entries (at most 500,
5 s from the start and 10 s from the end). They are applied only while watch history is recorded and never
replace a position saved on this device.

Auto-translated subtitles request the same caption track with `tlang`. YouTube currently answers those
requests with HTTP 429 from the test network (plain tracks still load); the app then shows a rate-limit message
and keeps playing. Translation is off by default and only used when the chosen language has no track.

Kiosks: Live (YouTube's Live channel tab), Gaming (the Gaming channel's trending tab), Podcasts
(/podcasts) and Movie trailers (YouTube Charts TRENDING_MOVIES). They are opt-in home sections; opening one
from the drawer adds it to home. Kiosk pages currently load one page without continuation.

NewPipe settings: only `preferences.json` is read (never the Java-serialized `newpipe.settings`). Theme,
content language/region, search/watch history, resume, search suggestions, download network and the main
tab layout (built-in tabs, kiosks, YouTube channels and online playlists, in NewPipe's order) are shown in
the import preview and applied only when the user turns on "Also apply these NewPipe settings". Local
playlist tabs, feed-group tabs and other services' tabs are reported as skipped.

Real NewPipe backups store the database in WAL mode. The importer now converts its private temporary copy to
a rollback-journal header before opening it read-only; before this, every real Android backup failed to
import on iOS (the earlier tests used synthetic databases).

SoundCloud (service ID 1 in NewPipe) is implemented with service-prefixed IDs so existing stores, queues and
downloads keep working: tracks "sc:<id>", users "sc:user:<id>", playlists "sc:playlist:<id>". Libraries that
contain SoundCloud items are refused (and left untouched) by builds from before this change. The web client ID is
read from soundcloud.com's asset scripts as NewPipe does, cached in memory and refreshed once on 401/403.
Playback uses the full-length HLS AAC (or MP3) stream; encrypted (DRM) and preview-only tracks are refused with
a reason. Downloads join the HLS map and segments into one .m4a/.mp3 file in the foreground, because
AVAssetDownloadTask can't store SoundCloud's bare media playlists for offline use; such downloads stop if the app
is closed and can be retried. NewPipe backups' SoundCloud entries are still skipped (they store permalinks,
which would need one lookup per item).

Kiosk paging: YouTube serves the Live, Gaming and Podcasts pages as single pages (53, 50 and 48 items on
26 October 2026) without continuation tokens, and DriftLoom shows all of them; Trending music and Movie trailers
are fixed-size YouTube Charts lists. SoundCloud trending already pages through next_href. There is nothing further
to load, so no paging was added.

Seek-bar previews: the storyboard spec (`storyboards.playerStoryboardSpecRenderer.spec`) comes from the same
iOS InnerTube player response as captions, cached per video, so previews add no YouTube request. Sheets are
cached in memory (40); the 160 px level is used. AVKit's own scrubber can't show custom frames, so DriftLoom adds
its own seek bar under the video; fullscreen keeps AVKit's bar without previews.

New-video notifications: BGAppRefreshTask `net.driftloom.app.feedRefresh`, scheduled when the app goes to the
background (earliest 30 minutes later; iOS chooses the time). It fetches up to 150 subscriptions' RSS/SoundCloud
feeds four at a time. The first check only records the feed; later checks announce unseen uploads from the last
three days. Verified: scheduling is accepted on the iPhone 7 (the simulator rejects BGTaskScheduler), the check and
notifications run on the iPhone 7 and simulator, and tapping opens the video. A run started by iOS itself in the
background was not observed during testing.

Google Takeout: rows count as subscriptions only when column 1 is a channel ID and column 2 is that channel's
youtube.com/channel URL, so translated headers and file names work and the export's own channel.csv (your channel)
or playlist CSVs are never imported as subscriptions. ZIPs up to 50 MB are read in memory (a subscriptions-only
export is a few KB); larger exports should be narrowed in Takeout or the CSV chosen directly.

Shared links: the DriftLoomShare extension (iOS 15+) finds the YouTube or SoundCloud link in what was shared and
opens `driftloom://open?url=<link>`. iOS has no public API for a share extension to open its app, so it asks the
application object in its responder chain to open the URL (a widely used approach that App Review could question);
Safari then shows its usual "Open in DriftLoom?" confirmation. The app resolves YouTube @handles from the channel
page's canonical link with a cookie-less request (a cookie-carrying request is sent to the EU consent page) and
SoundCloud permalinks and on.soundcloud.com links through SoundCloud's resolve API.

Download progress UI: DownloadSummary (in the DriftLoomActivity package library, shared with the
DriftLoomWidgets extension) drives an in-app strip, local notifications (permission asked when the first download
starts; a failure offers Retry; tapping opens Downloads) and, on iOS 16.1+, one Live Activity for all running
downloads. Background URLSession transfers can't report every step while the app is suspended, so the activity
shows the last known progress until iOS reports the end. SoundCloud downloads request background time; if iOS ends
it, the job fails with "Interrupted while DriftLoom was in the background", which ends the activity and notifies.
Verified: Dynamic Island and lock screen on the iPhone 16 Pro simulator (iOS 18), notifications on the SE
simulator and the iPhone 7 (iOS 15.8.2), where the app installs with the iOS 16.1 extension and ignores it.

Download network policy is fixed per job when it starts or is retried; changing the preference does not move
existing transfers. Wi-Fi-only jobs wait while only cellular is available.

Continue by introducing additional services behind explicit service-aware models. Do not label whole
milestones or full NewPipe parity complete while the gaps above remain. Validate format/codec and
background behavior on hardware before claiming support.

Apple background download sessions continue while the app is suspended. Force-quitting cancels active
transfers; reopening must show a recoverable job and retry with a fresh URL. See
[Apple's background asset download lifecycle](https://developer.apple.com/documentation/avfoundation/avassetdownloadurlsession).
