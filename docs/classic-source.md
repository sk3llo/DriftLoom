# Public SideStore and AltStore Classic source

Public source: **https://sk3llo.github.io/DriftLoom/source.json**

Install links and instructions: **https://sk3llo.github.io/DriftLoom/**

Both installers use the same JSON source and unsigned IPA assets from public GitHub releases. The publisher
needs no Apple Developer membership, signing certificate or notarization. Users sign with their own Apple
account; free accounts retain the seven-day refresh and app-count limits.

## What gets published

`.github/workflows/classic-source.yml` generates and deploys the source through GitHub Pages. It runs when
a release is published, edited, unpublished or deleted, when source-publishing code changes on main, and
when manually dispatched. Only stable, published releases containing a DriftLoom IPA and matching SHA-256
file are included. Drafts, prereleases and Android-only releases are excluded.

`scripts/build-classic-source.py` downloads those actual public IPAs, verifies checksums and sizes, and reads
their bundle ID, version, minimum OS and permissions. Versions are ordered numerically with the newest first;
older versions remain available. The source includes each IPA's SHA-256, release notes, public icon/screenshots,
and the stable identifier `net.driftloom.source.classic`. It omits `marketplaceID` and `buildVersion` for
SideStore/Classic compatibility. No unpublished local 1.0.1 build is advertised before its release is published.

If a build fails validation, deployment does not run and the previous source stays online. When publishing
an update, increase the marketing version as well as the build number; this shared feed uses marketing versions
for update discovery. Do not replace an existing IPA with different bytes under the same version.

## Hosting setup

In the repository's **Settings → Pages**, use **GitHub Actions** as the build source. The workflow deploys a
GitHub Pages artifact and uses the `github-pages` environment. It requires `contents: read` for the build and
`pages: write` plus `id-token: write` for deployment. No personal token or paid hosting secret is stored in Actions.

The GitHub Pages address, repository name and JSON source identifier must remain stable after users add them.
If the repository is renamed or moved, preserve the old URL or arrange a permanent redirect before updating links.

## Local verification and manual refresh

```sh
python3 -m unittest discover -s scripts/tests -v
python3 scripts/build-classic-source.py --output build/classic-source
```

The generator runs on macOS so `codesign` can inspect any signed entitlements. A `GITHUB_TOKEN` is optional for
public reads; the workflow supplies its short-lived repository token. Downloads themselves are anonymous.

For a manual refresh, open **Actions → Publish SideStore and AltStore Classic source → Run workflow** on main.
After deployment, verify the public JSON and every linked IPA are accessible without signing in. Adding a source
to the apps and performing an actual signed-device install still requires the user's Apple account and installer setup.
