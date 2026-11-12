# DriftLoom — notes for notarization review

DriftLoom is a free, independent YouTube and SoundCloud client. It has no sign-in, advertising, purchases,
subscriptions or developer-operated backend. Browsing, extraction and playback connect directly to the selected
service. Library data stays locally. Source and license notices are available in the repository and app.

Search for a publicly accessible video or track and select a result. The player supports background audio,
queues and Picture in Picture where supported. Download offers available formats for offline playback.
Availability depends on the source/network; upstream restrictions are shown as errors. The app does not promise
that every item is playable or downloadable. No service credentials are required.

In the PAL build, share a YouTube or SoundCloud link to DriftLoom from Safari. The extension saves it in the
App Group and confirms. Finish sharing and open DriftLoom manually: Open, Later and Discard let the user
choose what happens. The extension never launches another app or bypasses extension API restrictions.

Notifications are opt-in, scheduled locally and use background feed refresh rather than remote push.
Diagnostic reports open a prefilled GitHub issue for the user to review and submit; nothing is sent automatically.

These notes describe the implementation, without asserting third-party service authorization or notarization
approval. The account holder must provide actual review contact details and answer rights-documentation requests accurately.
