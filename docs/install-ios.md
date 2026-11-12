# Installing DriftLoom on iPhone and iPad

DriftLoom isn't in the App Store, so you install it yourself ("sideloading"). It runs on **iOS 15 or later**.

Each release on the [Releases page](https://github.com/sk3llo/DriftLoom/releases) has a `DriftLoom-<version>.ipa`
file. It isn't signed: the tool you install it with signs it with your own Apple ID, which is what lets iOS run it.

## Install and update from the public source

After setting up SideStore or AltStore Classic, add the same source in either app:

`https://sk3llo.github.io/DriftLoom/source.json`

Open the installer's **Sources** screen, tap **+**, paste that address and confirm. Find **DriftLoom** in Browse
and tap Install. Future published releases appear as updates in the installer; update with the same Apple ID
to keep your library. Installing from the source does not remove the seven-day refresh requirement.

From your iPhone, you can also use [Add to SideStore](sidestore://source?url=https%3A%2F%2Fsk3llo.github.io%2FDriftLoom%2Fsource.json)
or [Add to AltStore Classic](altstore://source?url=https%3A%2F%2Fsk3llo.github.io%2FDriftLoom%2Fsource.json).
[The source page](https://sk3llo.github.io/DriftLoom/) includes both links and the manual address.
The installer must already be installed before these links work. This source is for Classic/SideStore, not PAL.

## Why the app has to be refreshed every 7 days

Apple only runs apps signed by a certificate it issued. A **free Apple ID** gets a developer certificate that
lasts **7 days**, so every app signed with it stops opening after a week until it's signed again ("refreshed").
Refreshing keeps your subscriptions, history and downloads. If you miss it, DriftLoom just won't open until you
refresh; nothing is deleted.

A free Apple ID also allows at most **3 sideloaded apps** at once (the sideloading app itself counts as one) and
**10 App IDs per 7 days**. DriftLoom uses 3 App IDs (the app, its Share extension and its Live Activity widget).
If you're short of App IDs, SideStore and AltStore can install it without the extensions; you then lose
the share-sheet Copy link action and the lock-screen download progress, but everything else works.

From version 1.0.1, the sideload share extension offers **Copy link**. Open DriftLoom yourself and paste it in Search
or the Home link box. The older 1.0 release attempts to open the shared link directly.

## Choose a tool

| Tool | What you need | Refreshing |
|---|---|---|
| [SideStore](https://sidestore.io) (recommended) | A Mac, Windows or Linux computer once, for setup, and the free LocalDevVPN app | On the iPhone itself, in the background, while LocalDevVPN is connected |
| [AltStore Classic](https://altstore.io) | A Mac or Windows PC running AltServer | In the background while the iPhone and the computer are on the same Wi-Fi |
| [Sideloadly](https://sideloadly.io) | A Mac or Windows PC | By hand: connect the iPhone and install again every 7 days |

**SideStore** is the easiest to live with: after a one-time setup you don't need a computer, except after some
iOS updates (see [If DriftLoom stops opening](#if-driftloom-stops-opening)). Use **AltStore Classic** if the
SideStore setup doesn't work for you and you have a computer that stays on at home.

## Before you start (all tools)

- An **Apple ID**. A free one works. A separate Apple ID just for sideloading is a good idea, because the tool
  signs in to Apple with it.
- On **iOS 16 or later**, turn on **Settings → Privacy & Security → Developer Mode** and restart when asked.
  The switch only appears after a sideloading tool has installed something, so you may need to come back to it.
- The first time you open a sideloaded app, iOS may ask you to trust the developer: **Settings → General →
  VPN & Device Management**, tap your Apple ID, and tap **Trust** (on newer iOS, **Allow & Restart**).

## Install with SideStore (recommended)

You need a computer once, to install SideStore and give it a "pairing file" that lets it sign apps on the phone.

1. On the iPhone, install **LocalDevVPN** from the App Store, open it and allow the VPN configuration.
2. On the computer, follow [SideStore's install guide](https://docs.sidestore.io). It currently uses a desktop
   app (iLoader) that installs SideStore and its pairing file over USB; sign in with your Apple ID when asked.
3. Do the Developer Mode and trust steps from [Before you start](#before-you-start-all-tools), then open SideStore.
4. On the iPhone, download `DriftLoom-<version>.ipa` from the [Releases page](https://github.com/sk3llo/DriftLoom/releases)
   in Safari (it goes to the Files app).
5. Connect LocalDevVPN, open SideStore → **My Apps** → **+**, and pick the IPA.

SideStore refreshes DriftLoom in the background as long as **LocalDevVPN is connected** and the phone has
internet. You can also refresh by hand: SideStore → **My Apps** → **Refresh All**. Keep SideStore itself
refreshed too; it expires on the same 7-day schedule.

## Install with AltStore Classic

1. Install AltServer on your computer and AltStore on your iPhone by following
   [AltStore's guide](https://faq.altstore.io/altstore-classic/your-altstore).
   - **Windows:** install iTunes and iCloud **from Apple's website**, not from the Microsoft Store. If you already
     have the Microsoft Store versions, uninstall them first. Keep them installed afterwards; AltServer uses them.
   - **Mac:** nothing extra is needed.
2. Do the Developer Mode and trust steps from [Before you start](#before-you-start-all-tools).
3. On the iPhone, download `DriftLoom-<version>.ipa` from the [Releases page](https://github.com/sk3llo/DriftLoom/releases)
   in Safari.
4. Open AltStore → **My Apps** → **+**, and pick the IPA.

AltStore refreshes in the background when the iPhone and the computer are on the same Wi-Fi and AltServer is
running (or when the phone is plugged in). If the computer is off for a week, DriftLoom stops opening until
you refresh.

## Install with Sideloadly

Follow [Sideloadly's instructions](https://sideloadly.io) to install the IPA from your computer, and do the steps
in [Before you start](#before-you-start-all-tools). Repeat the install at least every 7 days.

## Updating DriftLoom

If you added the public source, use **Update** in SideStore or AltStore Classic when a new release appears.
The source checks published releases, so unreleased development builds and draft releases are not offered.

Install the new IPA with the same tool and the same Apple ID. It replaces the old version and keeps your library.

## If DriftLoom stops opening

- **SideStore:** make sure LocalDevVPN is connected, then SideStore → **My Apps** → **Refresh All**.
- **SideStore after an iOS update or a reset:** if refreshing fails with a pairing or connection error, the
  pairing file needs to be made again. Connect the iPhone to a computer and redo step 2 of
  [Install with SideStore](#install-with-sidestore-recommended); your apps and data stay.
- **AltStore:** start AltServer on the computer, put both on the same Wi-Fi (or plug the phone in), then
  AltStore → **My Apps** → **Refresh All**.
- **"Maximum number of apps" or App ID errors:** remove another sideloaded app, wait for App IDs to free up
  (they count over 7 days), or install DriftLoom without its extensions.

For problems inside the app, see [Troubleshooting](user-guide/troubleshooting.md).

## Avoiding the 7-day refresh

- **Paid Apple Developer account** (US$99 a year): apps you sign with it last a year, with no 3-app limit.
  SideStore, AltStore and Sideloadly all accept a paid account.
- **TrollStore**: installs apps permanently, without refreshing, but only on the iOS versions with the bug it
  relies on (iOS 14.0 to 16.6.1, 16.7 RC and 17.0). It won't support newer iOS. See the
  [TrollStore project](https://github.com/opa334/TrollStore) for how to install it; DriftLoom's IPA installs in it
  as is. If you use it:
  - **Turn off automatic iOS updates.** Updating past a supported version makes TrollStore apps stop opening,
    and Apple doesn't let you go back.
  - If an app stops opening after a reboot, use **Refresh App Registrations** in TrollStore's settings.
  - TrollStore keeps DriftLoom's original bundle ID, while SideStore and AltStore change it. iOS treats them as
    different apps, so export a backup before switching (see below).
  - Only install the IPA from the Releases page and check its checksum. TrollStore gives apps more access than
    other tools do, so a tampered copy could do more harm.
- Services that sell "no-revoke" certificates use enterprise certificates against Apple's rules. Apple revokes
  them without warning, and they see what you install. DriftLoom doesn't recommend them.

## Checking the download

Each IPA comes with a `.sha256` file. On a Mac, `shasum -a 256 DriftLoom-<version>.ipa` should print the same value.

## Back up before reinstalling

Uninstalling the app, switching tools, or installing it with a different Apple ID starts with an empty library.
Before any of these, use **Settings → Backup and import → Export library backup** in DriftLoom. Downloads and
settings aren't in the backup.

This also applies when moving from SideStore/AltStore Classic to an official PAL install: the signing and app
identity can differ, so iOS may treat them as separate apps. Export first, import into the new install, and
check your library before removing the old copy. Downloaded media must be downloaded again.
