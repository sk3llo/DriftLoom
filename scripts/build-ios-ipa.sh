#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Builds an unsigned DriftLoom.ipa for sideloading (AltStore, SideStore, Sideloadly), which sign it with
# the user's own Apple ID. Release configuration only: no DEBUG or DRIFTLOOM_DEVICE_TESTING code is in it.
#
#   scripts/build-ios-ipa.sh [output-dir]      # default: build/ios-release
#
# Writes DriftLoom-<version>.ipa and DriftLoom-<version>.ipa.sha256. Needs Xcode 26.6 or newer.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mkdir -p "${1:-$ROOT/build/ios-release}" && cd "${1:-$ROOT/build/ios-release}" && pwd)"
WORK="$OUT/work"
rm -rf "$WORK"; mkdir -p "$WORK"

PROJECT="$ROOT/iosApp/iosApp.xcodeproj"
ARCHIVE="$WORK/DriftLoom.xcarchive"

# Signing is left to the sideloading tool. TEAM_ID stays empty, so the bundle IDs are the plain
# net.driftloom.app.DriftLoom(.Share/.Widgets); the tool rewrites them for each Apple ID anyway.
xcodebuild archive \
  -project "$PROJECT" -scheme iosApp -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  -derivedDataPath "$WORK/DerivedData" \
  TEAM_ID= SWIFT_ACTIVE_COMPILATION_CONDITIONS= \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
  | { command -v xcbeautify >/dev/null && xcbeautify --quiet || grep -E "error:|warning: .*deprecated|\*\* ARCHIVE" || true; }

APP="$ARCHIVE/Products/Applications/DriftLoom.app"
[[ -d "$APP" ]] || { echo "error: archive has no DriftLoom.app" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist")"

# Test-only launch flags must not be in a release binary.
for flag in --playback-smoke-url --diagnostic-smoke --settings-smoke --crash-smoke; do
  if grep -q -- "$flag" "$APP/DriftLoom"; then
    echo "error: $flag is compiled into the release binary; build without test flags" >&2; exit 1
  fi
done
for ext in DriftLoomShare DriftLoomWidgets; do
  [[ -d "$APP/PlugIns/$ext.appex" ]] || { echo "error: $ext.appex is missing" >&2; exit 1; }
done

IPA="$OUT/DriftLoom-$VERSION.ipa"
rm -rf "$WORK/Payload" "$IPA"; mkdir -p "$WORK/Payload"
ditto "$APP" "$WORK/Payload/DriftLoom.app"
(cd "$WORK" && ditto -c -k --norsrc --noextattr --keepParent Payload "$IPA")
(cd "$OUT" && shasum -a 256 "$(basename "$IPA")" > "$(basename "$IPA").sha256")

echo "Built $IPA (version $VERSION, build $BUILD, $(du -h "$IPA" | cut -f1 | tr -d ' '))"
cat "$IPA.sha256"
