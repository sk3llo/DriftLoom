# Installing DriftLoom on iPhone and iPad

DriftLoom isn't in the App Store, so you install it yourself ("sideloading"). It runs on **iOS 15 or later**.

Each release on the [Releases page](https://github.com/sk3llo/DriftLoom/releases) has a `DriftLoom-<version>.ipa`
file. It isn't signed: the tool you install it with signs it with your own Apple ID, which is what lets iOS run it.

## Why the app has to be refreshed every 7 days

Apple only runs apps signed by a certificate it issued. A **free Apple ID** gets a developer certificate that
lasts **7 days**, so every app signed with it stops opening after a week until it's signed again ("refreshed").
Refreshing keeps your subscriptions, history and downloads. If you miss it, DriftLoom just won't open until you
refresh; nothing is deleted.

A free Apple ID also allows at most **3 sideloaded apps** at once and **10 App IDs per 7 days**. DriftLoom uses
3 App IDs (the app, its Share extension and its Live Activity widget). If you're short of App IDs, AltStore and
SideStore can install it without the extensions; you then lose "DriftLoom" in the share sheet and the
lock-screen download progress, but everything else works.

## Choose a tool

| Tool | What you need | Refreshing |
|---|---|---|
| [AltStore Classic](https://altstore.io) | A Mac or Windows PC running AltServer | Automatic in the background while the iPhone and the computer are on the same Wi-Fi |
| [SideStore](https://sidestore.io) | A computer once, for setup | On the iPhone itself, no computer needed after setup |
| [Sideloadly](https://sideloadly.io) | A Mac or Windows PC | By hand: connect the iPhone and install again every 7 days |

If you don't know which to pick, use **AltStore Classic** with a computer you leave on at home, or **SideStore**
if you don't want to depend on a computer.

## Install with AltStore Classic

1. Install AltServer on your computer and AltStore on your iPhone by following
   [AltStore's guide](https://faq.altstore.io/altstore-classic/your-altstore). It asks for an Apple ID; a separate,
   free one just for sideloading is a good idea.
2. On iOS 16 or later, turn on **Settings → Privacy & Security → Developer Mode** and restart when asked.
3. On the iPhone, download `DriftLoom-<version>.ipa` from the [Releases page](https://github.com/sk3llo/DriftLoom/releases)
   in Safari (it goes to the Files app).
4. Open AltStore → **My Apps** → **+**, and pick the IPA.
5. The first time you open DriftLoom, iOS may ask you to trust the developer: **Settings → General →
   VPN & Device Management**, tap your Apple ID, and tap **Trust**.

To update, install the new IPA the same way. It replaces the old version and keeps your library.

## Install with SideStore or Sideloadly

Follow [SideStore's](https://docs.sidestore.io) or [Sideloadly's](https://sideloadly.io) own instructions, then
add the DriftLoom IPA as above. Steps 2 and 5 (Developer Mode and trusting the developer) apply to them too.

## Avoiding the 7-day refresh

- **Paid Apple Developer account** (US$99 a year): apps you sign with it last a year, with no 3-app limit.
  AltStore, SideStore and Sideloadly all accept a paid account.
- **TrollStore**: installs apps permanently, without refreshing, but only on the iOS versions with the bug it
  relies on (iOS 14.0 to 16.6.1, 16.7 RC and 17.0). See the
  [TrollStore project](https://github.com/opa334/TrollStore) for how to install it; DriftLoom's IPA installs in it as is.
- Services that sell "no-revoke" certificates use enterprise certificates against Apple's rules. Apple revokes
  them without warning, and they see what you install. DriftLoom doesn't recommend them.

## Checking the download

Each IPA comes with a `.sha256` file. On a Mac, `shasum -a 256 DriftLoom-<version>.ipa` should print the same value.

## Back up before reinstalling

Uninstalling the app, or installing it with a different Apple ID, starts with an empty library. Before
switching tools or Apple IDs, use **Settings → Backup and import → Export library backup** in DriftLoom. Downloads and settings aren't in the backup.
