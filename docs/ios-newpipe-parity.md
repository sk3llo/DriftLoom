# iOS NewPipe parity rework

Reference: the Android NewPipe 0.29.1-based implementation in this repository. Keep the
DriftLoom name, legal attribution, and iOS 15 minimum. Treat the Android layouts, menus,
and user journeys as the specification. The iOS app is not yet a full NewPipe port.

## Implementation order and current checkpoint

| Stage | Implemented in this checkpoint | Still required for full parity |
| --- | --- | --- |
| Navigation and browsing | Main drawer; subscriptions/feed/bookmarks/history home tabs; tab visibility/order; compact result rows and action menus; search history; server-side type/date/duration/sort filters; content language/region; available channel tabs, avatar/description/subscription controls; pagination; persisted channel/remote-playlist home tabs; optional live suggestions; official regional YouTube music chart | Local-playlist home tabs and interleaved tab ordering; other kiosk sources; remaining metadata and visual comparison |
| Video details and mini-player | Inline native player; owner/subscription row; save/share/playlist/speed actions; related/description/comments tabs, replies, views/date; minimizing and returning without discarding search state | Remaining stream metadata; remaining detail actions; full visual parity |
| Queue and playback controls | Stable queue entries including duplicate videos; reorder/remove/play-next/enqueue; previous/next; finite shuffle; repeat; playlist play-all; resume positions; speed; HLS resolution caps; in-asset captions; background configuration and system remote commands; explicit native AVKit PiP capability; persisted queue/order/repeat/shuffle/speed/resolution without autoplay; extracted native format selection | Separate adaptive video/audio selection and merging; external subtitle extraction; exhaustive interruption/headphone/lock-screen/PiP tests |
| Subscriptions and playlists | Date-sorted RSS feed with bounded concurrent requests, deduplication, and partial-error reporting; local playlist CRUD/reorder; remote playlist bookmarks; existing library preserved | Subscription groups; additional feed controls; group migration and feed settings |
| Downloads | Available HLS/muxed/audio format discovery; versioned job records; cancellation/retry with fresh URLs; iOS background transfer reconnection; delete controls; completed HLS cache validation and local playback verified on iPhone 7 | External subtitles; separate video/audio merging; storage usage and network settings; broader file/audio and interrupted/background transfer tests |
| Settings, migration, services | Theme, home configuration, history controls, resume switch, content language/region; native library JSON backup; reviewed merge imports; atomic recovery journal and retained pre-import copies; NewPipe subscription JSON and ZIP/SQLite migration of supported YouTube library records | Full app preferences/queue/media backup; Android preferences, groups and positions migration; remaining player/download settings; additional services |

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
  back both library files if writing fails or the app exits partway through an import. A retained copy is
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

The package suite currently contains 71 tests, including real-media pause/seek preservation on format
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

Continue with external subtitles, subscription groups, remaining custom tab controls, and download
controls, then introduce additional services behind explicit service-aware models. Do not label whole
milestones or full NewPipe parity complete while the gaps above remain. Validate format/codec and
background behavior on hardware before claiming support.

Apple background download sessions continue while the app is suspended. Force-quitting cancels active
transfers; reopening must show a recoverable job and retry with a fresh URL. See
[Apple's background asset download lifecycle](https://developer.apple.com/documentation/avfoundation/avassetdownloadurlsession).
