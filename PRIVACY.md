# Privacy

DriftLoom has no account, no server and no analytics. Nobody behind DriftLoom receives anything from the app.

## What stays on your device

Subscriptions, history, playlists, saved videos, queues, downloads, settings and search history are stored only
on your phone. They leave it only when you export a backup yourself. Deleting the app deletes them.

## Who the app talks to

To show and play videos, the app connects directly to the services you use:

- **YouTube** (youtube.com, ytimg.com, googlevideo.com and YouTube's RSS feeds) for search, pages, comments,
  subtitles, thumbnails, charts and streams.
- **SoundCloud** (soundcloud.com and its API) for tracks, profiles and playlists.
- On Android, also the other services NewPipe supports (PeerTube instances, Bandcamp, media.ccc.de) when you use them.

These requests carry what any web client sends: your IP address, the content language and country you chose,
and the search terms or pages you open. Each service handles them under its own privacy policy. DriftLoom
doesn't sign you in and sends no Google or SoundCloud account details.

## Problem and crash reports

Nothing is sent automatically.

- **Report a problem** opens a new GitHub issue in your browser, filled in with the error, the app version,
  your device model, OS version, app language and content language and country. It is posted only if you
  submit it on GitHub, and it is public once posted. You can edit or remove anything before submitting.
- On iOS, if the app crashed or hung last time, it asks on the next launch whether to report it the same way.
  The crash details come from Apple's MetricKit, which iOS delivers only if you have turned on
  **Share With App Developers** (in the iPhone's Settings app: Privacy, or Privacy & Security on iOS 16 and later, then Analytics & Improvements).
- **Copy details** copies the same text to the clipboard instead.

GitHub's own [privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement)
applies to anything you post there.

## Notifications and background refresh

New-video notifications (off by default) are checked by the app itself in the background, using the same
direct requests as the What's new tab. No push service is involved.

## Changes

Changes to this policy are made in this file; its history is in the repository.
