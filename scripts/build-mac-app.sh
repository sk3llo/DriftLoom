#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds the Mac app (Mac Catalyst) and packages DriftLoom-<version>-mac.dmg for download outside the App Store.
#
#   scripts/build-mac-app.sh --unsigned [output-dir]
#       Signs ad hoc, without a certificate. Releases ship this until there's a paid developer account:
#       other Macs open it only after the user allows it once (Privacy & Security → Open Anyway).
#   DRIFTLOOM_MAC_IDENTITY="Developer ID Application: Name (TEAMID)" scripts/build-mac-app.sh [output-dir]
#       Signs for distribution: hardened runtime, secure timestamp, sandboxed app and share extension.
#   DRIFTLOOM_MAC_IDENTITY=... DRIFTLOOM_NOTARY_PROFILE=name scripts/build-mac-app.sh --notarize [output-dir]
#       Also uploads the disk image to Apple's notary service and staples the ticket to it.
#       Create the profile once with `xcrun notarytool store-credentials name`; it lives in your keychain.
#
# Writes DriftLoom-<version>-mac.dmg and its .sha256. Never publishes anything.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE=signed
case "${1:-}" in
  --unsigned) MODE=adhoc; shift ;;
  --notarize) MODE=notarize; shift ;;
esac
[[ $# -le 1 ]] || { echo "usage: $0 [--unsigned|--notarize] [output-dir]" >&2; exit 1; }
if [[ "$MODE" == adhoc ]]; then
  IDENTITY=-
else
  IDENTITY="${DRIFTLOOM_MAC_IDENTITY:-}"
  if [[ "$IDENTITY" != "Developer ID Application: "* ]]; then
    echo "Set DRIFTLOOM_MAC_IDENTITY to your \"Developer ID Application: ...\" certificate" \
         "(see: security find-identity -v -p codesigning), or use --unsigned." >&2
    exit 1
  fi
fi
if [[ "$MODE" == notarize && -z "${DRIFTLOOM_NOTARY_PROFILE:-}" ]]; then
  echo "Set DRIFTLOOM_NOTARY_PROFILE to a profile made with: xcrun notarytool store-credentials" >&2
  exit 1
fi
OUT="$(mkdir -p "${1:-$ROOT/build/mac-release}" && cd "${1:-$ROOT/build/mac-release}" && pwd)"
WORK="$OUT/work"
rm -rf "$WORK"; mkdir -p "$WORK"

# Build unsigned, then sign below with the checked-in entitlements, so no debugging entitlement slips in.
xcodebuild build \
  -project "$ROOT/iosApp/iosApp.xcodeproj" -scheme iosApp -configuration Release \
  -destination 'generic/platform=macOS,variant=Mac Catalyst' -derivedDataPath "$WORK/DerivedData" \
  TEAM_ID= SWIFT_ACTIVE_COMPILATION_CONDITIONS= \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
  | { command -v xcbeautify >/dev/null && xcbeautify --quiet || grep -E "error:|\*\* BUILD" || true; }

APP="$WORK/DerivedData/Build/Products/Release-maccatalyst/DriftLoom.app"
[[ -d "$APP" ]] || { echo "error: no DriftLoom.app was built" >&2; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"

# Sign from the inside out: any embedded frameworks or libraries, the share extension, then the app.
SIGN=(codesign --force --sign "$IDENTITY" --options runtime)
[[ "$IDENTITY" == - ]] || SIGN+=(--timestamp)
if [[ -d "$APP/Contents/Frameworks" ]]; then
  find "$APP/Contents/Frameworks" -depth \( -name '*.framework' -o -name '*.dylib' \) -print0 \
    | while IFS= read -r -d '' nested; do "${SIGN[@]}" "$nested"; done
fi
"${SIGN[@]}" --entitlements "$ROOT/iosApp/DriftLoomShare/DriftLoomShare-Mac.entitlements" \
  "$APP/Contents/PlugIns/DriftLoomShare.appex"
"${SIGN[@]}" --entitlements "$ROOT/iosApp/iosApp/DriftLoom-Mac.entitlements" "$APP"
codesign --verify --deep --strict "$APP"

# Check the signed result, not the requested settings.
python3 - "$APP" <<'PY'
import plistlib, subprocess, sys
app = sys.argv[1]
def entitlements(path):
    out = subprocess.run(["codesign", "-d", "--entitlements", "-", "--xml", path], capture_output=True).stdout
    return plistlib.loads(out) if out.strip() else {}
def flags(path):
    info = subprocess.run(["codesign", "-dv", path], capture_output=True, text=True).stderr
    return next((line for line in info.splitlines() if line.startswith("CodeDirectory")), "")
for path, needed in ((app, {"com.apple.security.app-sandbox", "com.apple.security.network.client"}),
                     (app + "/Contents/PlugIns/DriftLoomShare.appex", {"com.apple.security.app-sandbox"})):
    ents = entitlements(path)
    missing = sorted(key for key in needed if ents.get(key) is not True)
    if missing or ents.get("com.apple.security.get-task-allow"):
        sys.exit(f"error: {path.rsplit('/', 1)[-1]} entitlements wrong: missing {missing}, get-task-allow={ents.get('com.apple.security.get-task-allow')}")
    if "runtime" not in flags(path):
        sys.exit(f"error: {path.rsplit('/', 1)[-1]} isn't signed with the hardened runtime")
archs = subprocess.run(["lipo", "-archs", app + "/Contents/MacOS/DriftLoom"], capture_output=True, text=True).stdout.split()
if sorted(archs) != ["arm64", "x86_64"]:
    sys.exit(f"error: expected a universal app, got {archs}")
print("Checked: sandboxed app and extension, hardened runtime, no debugging entitlement, arm64 + x86_64")
PY

DMG="$OUT/DriftLoom-$VERSION-mac.dmg"
STAGE="$WORK/dmg"
rm -rf "$STAGE" "$DMG"; mkdir -p "$STAGE"
ditto "$APP" "$STAGE/DriftLoom.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "DriftLoom $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO "$DMG"
[[ "$IDENTITY" == - ]] || codesign --force --sign "$IDENTITY" --timestamp "$DMG"

if [[ "$MODE" == notarize ]]; then
  # Stapling the disk image covers the app inside it. A copied-out app checks its ticket online on first
  # launch, which DriftLoom needs to stream anyway.
  RESULT="$(xcrun notarytool submit "$DMG" --keychain-profile "$DRIFTLOOM_NOTARY_PROFILE" --wait --output-format json)"
  STATUS="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("status", ""))' "$RESULT")"
  if [[ "$STATUS" != Accepted ]]; then
    ID="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("id", ""))' "$RESULT")"
    echo "error: notarization status '$STATUS'" >&2
    [[ -n "$ID" ]] && xcrun notarytool log "$ID" --keychain-profile "$DRIFTLOOM_NOTARY_PROFILE" >&2
    exit 1
  fi
  xcrun stapler staple -q "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose "$DMG"
fi

(cd "$OUT" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "Built $DMG (version $VERSION, build $BUILD, $(du -h "$DMG" | cut -f1 | tr -d ' '), $MODE)"
