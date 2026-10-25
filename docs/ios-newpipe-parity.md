# iOS NewPipe parity rework

Reference: the Android NewPipe 0.29.1-based implementation in this repository. Keep the
DriftLoom name, legal attribution, and iOS 15 minimum. Treat the Android layouts, menus,
and user journeys as the specification. The iOS app is not yet a full NewPipe port.

## Implementation order and current checkpoint

| Stage | Implemented in this checkpoint | Still required for full parity |
| --- | --- | --- |
| Navigation and browsing | Main drawer; subscriptions/feed/bookmarks/history home tabs; tab visibility/order; compact result rows and action menus; search history; server-side type filters; available channel tabs, avatar/description/subscription controls; pagination | Verified kiosk/trending sources; custom channel/playlist home tabs; network suggestions; sort/date/duration filters; remaining metadata and visual comparison |
| Video details and mini-player | Inline native player; owner/subscription row; save/share/playlist/speed actions; related and description tabs; minimizing and returning without discarding search state | Comments/replies; richer stream metadata; remaining detail actions; full visual parity |
| Queue and playback controls | Stable queue entries including duplicate videos; reorder/remove/play-next/enqueue; previous/next; finite shuffle; repeat; playlist play-all; resume positions; speed; HLS resolution caps; in-asset captions; background configuration and system remote commands; native AVKit PiP capability | Exact available-format selection; external subtitle extraction; exhaustive interruption/headphone/lock-screen/PiP tests; persist and restore the whole queue |
| Subscriptions and playlists | Date-sorted RSS feed with bounded concurrent requests, deduplication, and partial-error reporting; local playlist CRUD/reorder; remote playlist bookmarks; existing library preserved | Subscription groups; additional feed controls; import/export; NewPipe backup migration |
| Downloads | Not started | Format selection, cancellable/retryable download jobs, storage management, offline playback, audio/subtitle support, background recovery |
| Settings, migration, services | Theme, home configuration, history controls, resume switch; versioned playlist storage independent of existing library JSON | Content language/region controls; remaining player/download settings; backup/restore and NewPipe database migration; additional services |

## Storage and compatibility

- Existing library.json remains version 1, with its original saved videos, subscriptions, and history.
- New playlists.json is independently versioned; corrupt/newer files block writes and remain untouched.
- Playlist entries have independent UUIDs, so repeated videos can be moved/deleted individually.
- Search history, theme/home preferences, and bounded resume metadata use local preferences.
- Disabling watch-history recording also disables recording/resuming positions for new playback.
- Removing watch-history entries removes their resume positions.
- Resolved media URLs are not persisted in these stores.
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

## Next implementation batch

Finish the remaining playback/metadata gaps, then implement downloads as a separate persistent job
model. Validate real offline playback before exposing the download action. Add backup and migration
only after defining and testing a versioned format and inspecting NewPipe's actual exported schema.
Preserve existing data throughout and retain a recoverable copy when migrating formats.
