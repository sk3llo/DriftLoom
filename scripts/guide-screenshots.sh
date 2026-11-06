#!/bin/bash
# Retakes the user-guide screenshots (docs/user-guide/images) with the ScreenshotTour UI test.
# Usage: scripts/guide-screenshots.sh [simulator-udid]   (default: an iPhone SE (3rd generation), 750x1334)
# Needs network (it browses YouTube) and Pillow (python3 -m pip install pillow).
set -euo pipefail
cd "$(dirname "$0")/.."
UDID=${1:-$(xcrun simctl list devices available | grep -m1 "iPhone SE (3rd generation)" | grep -oE '[0-9A-F-]{36}')}
WORK=$(mktemp -d)
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" >/dev/null
xcrun simctl ui "$UDID" appearance light
xcrun simctl status_bar "$UDID" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode notSupported --batteryState charged --batteryLevel 100 --operatorName ""
TEST_RUNNER_TOUR_DIR="$WORK/tour" TEST_RUNNER_TOUR_LANG=en xcodebuild test -project iosApp/iosApp.xcodeproj \
  -scheme iosApp -configuration Release -destination "id=$UDID" -derivedDataPath "$WORK/dd" \
  -only-testing:DriftLoomUITests/ScreenshotTour CODE_SIGNING_ALLOWED=NO \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS=DRIFTLOOM_DEVICE_TESTING > "$WORK/test.log" 2>&1 \
  || { tail -20 "$WORK/test.log"; exit 1; }
xcrun simctl status_bar "$UDID" clear
python3 - "$WORK/tour/en" docs/user-guide/images <<'PY'
import sys
from PIL import Image
tour, out = sys.argv[1:]
# guide image -> tour screenshot (see iosApp/iosAppUITests/ScreenshotTour.swift for the order)
shots = {"home": "01-home-live", "drawer": "02-drawer", "subscriptions": "04-subscriptions",
         "bookmarks": "10-bookmarks", "item-actions": "11-item-actions", "trending": "13-trending",
         "search-suggestions": "15-search-suggestions", "search-results": "16-search-results",
         "open-link": "19-open-link", "download-settings": "21-download-settings", "settings": "23-settings",
         "home-tabs": "27-home-tabs", "backup": "29-backup", "player": "32-player",
         "download-sheet": "38-download-sheet", "player-scrub": "40-player-scrub"}
for name, shot in shots.items():
    image = Image.open(f"{tour}/{shot}.png").convert("RGB")
    image.resize((420, round(420 * image.height / image.width)), Image.LANCZOS).save(f"{out}/{name}.jpg", quality=82, optimize=True)
    print("updated", name)
PY
echo "Review the images before committing: live content (trending, search results) changes every run."
