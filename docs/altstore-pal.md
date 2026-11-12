# Publishing on AltStore PAL

**Deferred:** DriftLoom currently uses the public [SideStore/AltStore Classic source](classic-source.md).
That route does not require a paid publisher account. This document retains the optional PAL setup reference.

The repository is prepared for **1.0.1 (build 2)**. No App Store Connect app record, marketplace authorization,
signed distribution package or notarization approval is supplied by the repository. An unsigned GitHub IPA
cannot be used as a PAL package.

PAL serves eligible users in the EU, Japan and Brazil. OS/device requirements differ by region; check
[Apple's eligibility](https://support.apple.com/118110) and
[AltStore's instructions](https://faq.altstore.io/developers/distribute-with-altstore-pal).
The app itself still supports iOS 15; PAL installation has higher requirements. Other users can
[sideload](install-ios.md).

Before switching an existing sideload install to PAL, export a library backup. Signing/app identity can differ,
so data does not automatically migrate. Import and verify the backup in PAL before removing the old app;
downloads and settings are not included. See [backup before reinstalling](install-ios.md#back-up-before-reinstalling).

## One-time account setup

1. Enroll in the paid Apple Developer Program and accept the current Developer Program License Agreement.
   In the EU, **Attachment 14 superseded the Alternative Terms Addendum on 1 October 2026**. Apple's current
   Core Technology Commission is 5% on covered digital transactions, replacing the per-install fee. DriftLoom
   has no paid app, purchases or subscriptions; check reporting obligations and revisit the terms before adding
   monetization. Japan/Brazil have separate regional terms. [Apple's EU terms](https://developer.apple.com/support/apps-in-the-eu/).
2. Register these explicit App IDs in Certificates, Identifiers & Profiles:
   - `net.driftloom.app.DriftLoom`
   - `net.driftloom.app.DriftLoom.Share`
   - `net.driftloom.app.DriftLoom.Widgets`
3. Register **`group.net.driftloom.app.shared`** and enable it for the main app and Share extension.
   The widget does not need this App Group. Regenerate provisioning profiles after changing capabilities.
4. Create the iOS app in App Store Connect using the main bundle ID. Record its numeric **Apple ID** from
   App Information. This differs from the signing Team ID and the AltStore Developer UUID.
5. Register the **Developer UUID from App Store Connect → Edit Profile** with
   [AltStore's API](https://faq.altstore.io/developers/rest-api). Add the returned token under App Store Connect →
   Users and Access → Integrations → Marketplaces, select DriftLoom and enable notifications.
6. Complete age rating, app information, review contact, support/contact details, screenshots and privacy details.
   Use the [public privacy policy](https://github.com/sk3llo/DriftLoom/blob/main/PRIVACY.md), including its direct
   service requests and user-submitted GitHub reports. Determine trader status from the developer's actual
   activities; a free price alone does not determine that status.

## Verify and archive

```sh
swift test --package-path iosApp/Playback -c release --build-system native
python3 -m unittest discover -s scripts/tests -v
scripts/build-ios-pal.sh --unsigned
```

The unsigned archive is for verification only. Checks cover stable bundle IDs, matching app/extension versions,
App Group configuration, privacy manifest, and absence of test flags or unsupported extension app-opening code.
CI also tests the shared-link confirmation UI; releases require these checks.

After registering the App IDs and App Group, create a signed archive:

```sh
DRIFTLOOM_TEAM_ID=YOUR_10_CHARACTER_TEAM_ID scripts/build-ios-pal.sh
open build/ios-pal/DriftLoom-PAL.xcarchive
```

This uses `iosApp/Configuration/PAL.xcconfig` and archives in Release without uploading. The signing Team ID
does not change PAL's registered bundle IDs. Normal Xcode development retains its optional team-specific suffix;
free-account sideload builds omit the App Group capability.

In Xcode Organizer, distribute the signed archive to **App Store Connect**. The optional
`iosApp/Configuration/ExportOptions-PAL.plist` uses `destination=export`, so it does not auto-upload.
Increase `CURRENT_PROJECT_VERSION` in `Config.xcconfig` for each subsequent upload.

## Notarization

1. Select the build in App Store Connect and set Review Type to **Notarization**. Submit the required metadata
   and review notes. [Apple's instructions](https://developer.apple.com/help/app-store-connect/managing-alternative-distribution/submit-for-notarization/).
2. Start with [pal-review-notes.md](pal-review-notes.md); provide the actual contact details in App Store Connect.
   Do not claim Apple approval or service authorization that has not been obtained.
3. After notarization and AltStore processing, download the **Alternative Distribution Package (ADP)** via
   [AltStore's API](https://faq.altstore.io/developers/rest-api#download-adp). Preserve `manifest.json`, `signature`
   and every IPA variant unchanged. Neither the unsigned CI archive nor the sideload IPA can replace the ADP.

## Hosting and source generation

Use a public HTTPS static host that preserves directories and bytes. Put the complete ADP under a versioned
directory, and host `source.json` separately. The public repository supplies the icon/screenshots. For a flat
host such as GitHub Releases, AltStore also supports `assetURLs`; this generator assumes the original ADP directory
structure instead. See [AltStore's source format](https://faq.altstore.io/developers/make-a-source).

When the actual ADP, Apple app ID, developer display name and hosting address are available:

```sh
python3 scripts/prepare-altstore-source.py \
  --adp-dir /path/to/unchanged-adp \
  --base-url "$DRIFTLOOM_ADP_BASE_URL" \
  --marketplace-id "$DRIFTLOOM_APPLE_APP_ID" \
  --developer-name "$DRIFTLOOM_DEVELOPER_NAME" \
  --release-date YYYY-MM-DD \
  --output build/altstore-pal/source.json
```

The generator reads real version/build/minimum OS/size and collects signed entitlements and privacy descriptions
from the app and extensions. PAL's download URL points to the ADP manifest. It rejects placeholder hosts,
invalid app IDs, incomplete packages and unsigned variants. No publishable placeholder source is committed.

For Classic/SideStore, use `--ipa /path/to/DriftLoom-1.0.1.ipa` instead of `--adp-dir`, omit `--marketplace-id`,
and set `--base-url` to the directory containing the hosted IPA. The two channels have distinct source identifiers.

Before announcing PAL:

- Verify the source, icon, screenshots, manifest, signature and every IPA variant download anonymously via HTTPS.
- Compare hosted bytes against the original ADP. Serve IPA/signature as `application/octet-stream`; missing paths
  must return 404 rather than an HTML fallback page.
- Add the source to PAL and install on eligible physical devices. Test updates without library loss, shared links
  across launches, offline downloads, background audio and Picture in Picture.
- Keep the source URL/identifier stable for updates, retaining older version entries when needed.
- Publish after notarization and a successful real PAL install. The generator does not verify Apple's approval
  or hosted-file availability. Users add `altstore://source?url=` followed by the URL-encoded source URL.

Optional: [make the source discoverable](https://faq.altstore.io/developers/source-discoverability).

## Sharing and remaining verification

PAL sharing saves links in the App Group. It never forces the app open. On the next launch/foreground,
**Open**, **Later** and **Discard** let the user choose what happens. Later preserves the link across restarts;
Open/Discard removes only that link. Multiple shares are kept separately.

Free-account sideload builds offer **Copy link** instead. Open DriftLoom yourself and paste in Search or the
Home link box. Both paths use supported extension APIs.

Notarization approval remains Apple's decision, including any questions about media functionality or third-party
rights. Local checks do not establish permission from YouTube/SoundCloud. Hardware coverage and the iPad
full-screen gesture limitation remain recorded in [development.md](development.md).
