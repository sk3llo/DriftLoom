DriftLoom contribution guidelines
=================================

DriftLoom is a fork of [NewPipe](https://github.com/TeamNewPipe/NewPipe) with a native iOS app alongside the
Android one. Please report DriftLoom problems here, not to Team NewPipe.

## Reporting problems

* **From the app** is easiest. On iOS, use **Settings → Help → Report a problem**, the Report button on an error,
  or the prompt after a crash. On Android, use **Report on GitHub** on the error screen. These open a new issue
  with the error, version and device filled in; nothing is sent until you submit it on GitHub.
* **Already reported?** Search the [open and closed issues](https://github.com/sk3llo/DriftLoom/issues?q=is%3Aissue) first.
* **One problem per issue**, in English, with steps to reproduce.
* **Still happening?** Check the latest [release](https://github.com/sk3llo/DriftLoom/releases/latest).

YouTube changes often and sometimes blocks networks ("confirm you're not a bot"). DriftLoom doesn't try to get
around those checks; see [Troubleshooting](../docs/user-guide/troubleshooting.md).

## AI-assisted contributions

You may use AI tools, but you are responsible for what you submit:

* Understand and review every line, and make sure it fits the project's structure.
* Fix the root cause, not the symptom.
* Test the change on a device or simulator and say how in the PR.
* Write issue and PR descriptions yourself, or check every claim in them.

Reports opened by the app's Report button are fine as they are; just add what you were doing.

## Translation

* **iOS:** strings live in Xcode string catalogs (`Localizable.xcstrings`) in `iosApp/iosApp`, `iosApp/DriftLoomShare`
  and the two package targets in `iosApp/Playback`. English, Ukrainian and Portuguese are complete; to add a
  language, open the catalogs in Xcode, add the language and translate every entry, including plural forms.
* **Android:** strings are in `app/src/main/res/values-*/strings.xml`, inherited from NewPipe's translations.
* Keep the user guide (`docs/user-guide`) in step if you change what a screen says.

## Code contribution

### Before starting

* Comment on the issue you want to work on, or open one describing the change, so we can agree on the approach first.
* Keep a PR to **one** fix or feature.
* **No non-free software**: no binary blobs or closed-source libraries (such as Google Play Services). The
  project follows the [F-Droid inclusion policy](https://f-droid.org/docs/Inclusion_Policy/).

### Pull requests

* Work on a branch with a meaningful name and open the PR against `main`.
* **Test before submitting.** Untested code is not merged. For iOS changes, run the package tests and the UI tests
  you touched (see the [development notes](../docs/development.md)); for Android, build and run the app.
* Keep the PR up to date with `main` and look into CI failures yourself.
* Respond to review comments.

## Building

* **iOS:** Xcode 26.6 or newer. Open `iosApp/iosApp.xcodeproj` and run the `iosApp` scheme. Package tests:
  `swift test --package-path iosApp/Playback`. Details in [docs/development.md](../docs/development.md).
* **Android:** [Android Studio](https://developer.android.com/studio/) with JDK 21. Clone
  `https://github.com/sk3llo/DriftLoom.git` (or your fork), open the folder and run the `app` configuration.

### Style

* Swift follows the surrounding code; keep views small and put logic that can be tested in the `DriftLoomPlayback` package.
* Java is checked by [checkStyle](https://github.com/checkstyle/checkstyle) and Kotlin by
  [ktlint](https://github.com/pinterest/ktlint) on every build. In Android Studio, the `CheckStyle-IDEA` plugin
  with `checkstyle/checkstyle.xml` and the `Ktlint (unofficial)` plugin show problems in the editor.

## Communication

Use [GitHub issues](https://github.com/sk3llo/DriftLoom/issues) for bugs and ideas. DriftLoom has no chat room;
the NewPipe Matrix and IRC channels are for NewPipe only.
