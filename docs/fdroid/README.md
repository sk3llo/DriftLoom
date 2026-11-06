# Publishing on F-Droid

F-Droid builds DriftLoom itself from the public source at a release tag, so the repository has to be public
before the app can be submitted.

## Before submitting

- [ ] A DriftLoom launcher icon and store artwork. F-Droid requires a fork to look different from the original;
      the launcher icon, `fastlane/metadata/android/en-US/images/icon.png` and `featureGraphic.png` are still NewPipe's.
- [ ] Phone screenshots of the DriftLoom Android app in `fastlane/metadata/android/en-US/images/phoneScreenshots/`
      (the current ones are NewPipe's).
- [ ] A release tag whose `versionCode`/`versionName` match the recipe. The application ID is `net.driftloom.app`.
- [ ] The repository is public.

## Submitting

1. Fork https://gitlab.com/fdroid/fdroiddata and copy [`net.driftloom.app.yml`](net.driftloom.app.yml) to
   `metadata/net.driftloom.app.yml`, with `commit:` set to the release tag.
2. Check it locally with `fdroid readmeta`, `fdroid lint net.driftloom.app` and `fdroid build -v -l net.driftloom.app`.
3. Open a merge request titled "New App: net.driftloom.app". Reviews usually take a few weeks.

Store text comes from `fastlane/metadata/android/` in this repository: `en-US/title.txt`,
`short_description.txt` (80 characters at most), `full_description.txt`, and `changelogs/<versionCode>.txt`
for each release.

## Signing

By default F-Droid signs the APK with its own key, so an F-Droid install can't be updated with the APK from
GitHub Releases, or the other way round. If the build is reproducible, F-Droid can ship our signed APK instead:
add `Binaries:` (the GitHub release APK URL) and `AllowedAPKSigningKeys:` with the certificate SHA-256 pinned in
`.github/workflows/release.yml`. Check reproducibility first by building the tag with `fdroid build` and comparing
the result with the release APK (`apksigcopier compare`).
