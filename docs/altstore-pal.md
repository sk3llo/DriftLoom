# Publishing on AltStore PAL

AltStore PAL is an alternative app marketplace for iPhone and iPad. Apple still has to **notarize** each build,
and only users in the EU (and, per AltStore, Japan and Brazil) on **iOS 17.4 or later** can install from it.
Everyone else keeps using the sideloading guide in [install-ios.md](install-ios.md).

## What it needs

- A paid Apple Developer Program membership (the individual account that already signs DriftLoom works).
- The **Alternative Terms Addendum for Apps in the EU**, accepted in App Store Connect → Business. A free app
  pays no Core Technology Commission, since it only applies to digital sales.
- In the EU, App Store Connect asks whether you're a **trader** under the Digital Services Act. A trader's name,
  address, phone and email are shown to users; a free app with no business behind it can usually declare
  non-trader. Decide this before submitting.
- A public HTTPS host for the Alternative Distribution Package (ADP) and the `source.json`. GitHub Releases on the
  private repository won't work, because AltStore can't download from it.

## One-time setup

1. In [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list),
   register the three bundle IDs: `net.driftloom.app.DriftLoom`, `.Share` and `.Widgets`.
2. In App Store Connect, create the app with bundle ID `net.driftloom.app.DriftLoom`, and fill in the privacy
   details: no data collected, no tracking (matches `iosApp/iosApp/PrivacyInfo.xcprivacy`).
3. Accept the Alternative Terms Addendum.
4. Register with AltStore as a developer, using the **UUID from your App Store Connect profile** (not the team ID;
   registering with the team ID fails silently). Put the token AltStore gives you into App Store Connect →
   Users and Access → Integrations → Marketplaces, to authorize AltStore to distribute your app.
5. Create an App Store Connect API key (Users and Access → Integrations → App Store Connect API) for uploads
   from CI.

## Each release

1. Build and upload: archive the `iosApp` scheme in Release with distribution signing and upload it to App Store
   Connect (Xcode Organizer, or `xcodebuild -exportArchive` with the API key). Each upload needs a higher
   `CURRENT_PROJECT_VERSION`.
2. In App Store Connect, submit the build **for notarization**, not for App Review. Notarization checks security
   and basic functionality; it can take a day or more.
3. Download the ADP for the notarized version. It contains `manifest.json`, an extensionless `signature` file
   and one or more `.ipa` variants.
4. Upload the ADP to the host **unchanged**: the folder layout and file hashes must stay exactly as Apple
   delivered them. Serve `.ipa` and `signature` as `application/octet-stream`, and make sure the server doesn't
   answer unknown files with an HTML fallback page.
5. Add the version to `source.json` (see [altstore-source.json](altstore-source.json)): `marketplaceID` is the app's
   Apple ID from App Store Connect, and each entry in `versions` points `downloadURL` at that release's
   `manifest.json`.
6. Users add the source with `altstore://source?url=<source.json URL>`; AltStore then installs and updates DriftLoom.

## Open questions

- Notarization could still object to downloading YouTube videos. Apple describes notarization as a security and
  functionality check, but the first submission is the real test.
- Notarization can be revoked later, which stops the app from launching on installed devices.
- Where to host the ADP and `source.json` while the repository is private.
