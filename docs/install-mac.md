# Installing DriftLoom on a Mac

The Mac app is DriftLoom's iOS app built for the Mac. It runs on **macOS 12 or later**, on Apple silicon and Intel
Macs. It's a preview: Apple hasn't notarized it, because notarization needs a paid Apple Developer membership, so
macOS asks you to allow it before it opens.

## Install

1. Download `DriftLoom-<version>-mac.dmg` from the [Releases page](https://github.com/sk3llo/DriftLoom/releases).
2. Open the disk image and drag **DriftLoom** to **Applications**.
3. Open DriftLoom from Applications. macOS says it couldn't verify the app. Click **Done**.
4. Open **System Settings → Privacy & Security**, scroll down to **Security**, and click **Open Anyway** next to
   the message about DriftLoom. Confirm with your password or Touch ID, then choose **Open Anyway** again.

   On macOS 14 or earlier you can instead Control-click DriftLoom in Applications and choose **Open**.

After that, DriftLoom opens normally.

## Updating

The Mac app doesn't update itself yet. Download the new disk image from Releases and drag DriftLoom to
Applications again, replacing the old copy. macOS asks you to allow the new version once, as above. If it then asks
whether DriftLoom may access data from other apps, allow it: that's your library from the previous version.

To be safe, export a backup first: **Settings → Backup and import → Export library backup**. Downloads and settings
aren't in the backup.

## Checking the download

Each disk image comes with a `.sha256` file. In Terminal, `shasum -a 256 DriftLoom-<version>-mac.dmg` should print
the same value. GitHub Actions builds the disk image from the tagged source, and the app is sandboxed: it can reach
the network and the files you choose in its dialogs, nothing else.

## Differences from the iPhone app

- Download progress shows in the app only; Macs have no Lock Screen Live Activities.
- Full screen has no brightness or volume swipes. Use your Mac's keys instead.
- Picture in Picture, background playback and downloads work as on iPhone.

For problems inside the app, see [Troubleshooting](user-guide/troubleshooting.md).
