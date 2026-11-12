#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Archive for App Store Connect / PAL notarization. Never uploads or publishes.
# DRIFTLOOM_TEAM_ID=ABCDEFGHIJ scripts/build-ios-pal.sh [output-dir]
# scripts/build-ios-pal.sh --unsigned [output-dir]  # local / CI verification only
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UNSIGNED=NO
if [[ "${1:-}" == --unsigned ]]; then UNSIGNED=YES; shift; fi
[[ $# -le 1 ]] || { echo "usage: $0 [--unsigned] [output-dir]" >&2; exit 1; }
if [[ "$UNSIGNED" == NO && ! "${DRIFTLOOM_TEAM_ID:-}" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "Set DRIFTLOOM_TEAM_ID to your 10-character Apple signing team ID, or use --unsigned for verification." >&2
  exit 1
fi
OUT="$(mkdir -p "${1:-$ROOT/build/ios-pal}" && cd "${1:-$ROOT/build/ios-pal}" && pwd)"
ARCHIVE="$OUT/DriftLoom-PAL.xcarchive"
SIGNING=(TEAM_ID="${DRIFTLOOM_TEAM_ID:-}" CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates)
if [[ "$UNSIGNED" == YES ]]; then
  SIGNING=(TEAM_ID= CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=)
fi
xcodebuild archive \
  -project "$ROOT/iosApp/iosApp.xcodeproj" -scheme iosApp -configuration Release \
  -xcconfig "$ROOT/iosApp/Configuration/PAL.xcconfig" \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" -derivedDataPath "$OUT/DerivedData" \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS= "${SIGNING[@]}" \
  | { command -v xcbeautify >/dev/null && xcbeautify --quiet || grep -E 'error:|warning: .*deprecated|\*\* ARCHIVE' || true; }
python3 "$ROOT/scripts/check-ios-release.py" "$ARCHIVE/Products/Applications/DriftLoom.app" --channel pal
if [[ "$UNSIGNED" == YES ]]; then
  echo "Verified unsigned PAL archive: $ARCHIVE (cannot be uploaded or installed)."
else
  echo "Signed archive: $ARCHIVE. Open it in Xcode Organizer to upload to App Store Connect."
fi
