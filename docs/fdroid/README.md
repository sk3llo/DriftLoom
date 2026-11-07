# Publishing on F-Droid

F-Droid builds DriftLoom itself from the public source at a release tag, so the repository has to be public
before the app can be submitted.

## Before submitting

- [x] A DriftLoom launcher icon and store artwork (F-Droid requires a fork to look different from the original).
- [x] Phone screenshots of the DriftLoom Android app in `fastlane/metadata/android/en-US/images/phoneScreenshots/`.
- [x] A release tag whose `versionCode`/`versionName` match the recipe. The application ID is `net.driftloom.app`.
- [x] The recipe builds with F-Droid's tools (checked 7 November 2026 on `v1.0`, see below).
- [ ] The v1.0 release is published, so `Binaries:` can download its APK.
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

The build is reproducible, so the recipe has `Binaries:` (the GitHub release APK) and `AllowedAPKSigningKeys:`
(the certificate SHA-256 pinned in `.github/workflows/release.yml`). F-Droid builds the tag, checks that its APK
matches ours apart from the signature, and then publishes our signed APK. F-Droid and GitHub installs can update
each other. If a release ever stops reproducing, F-Droid won't publish it; fix the difference rather than dropping
`Binaries:`, since switching to F-Droid's own key would break updates for existing installs.

## Checking the recipe locally

F-Droid builds in the `registry.gitlab.com/fdroid/fdroidserver:buildserver` image (Debian, JDK 21). On a Mac:

1. Make a working folder with `fdroiddata/config/` (from fdroiddata's `config` folder, which lint needs),
   `fdroiddata/config.yml` containing `sdk_path: /opt/android-sdk`, and this recipe as
   `fdroiddata/metadata/net.driftloom.app.yml`. While the repository is private, point `Repo:` at a mirror
   (`git clone --mirror`) mounted into the container.
2. In the container (`docker run --platform linux/amd64 ...`), install fdroidserver from its git checkout into a
   venv, then run `fdroid lint net.driftloom.app` and `fdroid build --verbose --test --no-tarball net.driftloom.app:1`.
   Under emulation, put `org.gradle.workers.max=2` and `kotlin.compiler.execution.strategy=in-process` in the
   container's `~/.gradle/gradle.properties`, or the Gradle daemon runs out of memory during R8. The build takes
   about 17 minutes.
3. Compare: `apksigcopier copy DriftLoom-<version>.apk fdroiddata/tmp/net.driftloom.app_<code>.apk out.apk`, then
   `apksigner verify out.apk` and `cmp out.apk DriftLoom-<version>.apk`. Identical files mean F-Droid will accept it.

The recipe removes `doc` (F-Droid's scanner mistakes the Somali `README.so.md` for a native library) and
`app/src/test`, as NewPipe's recipe does.
