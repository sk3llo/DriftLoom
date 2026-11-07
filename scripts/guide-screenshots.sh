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
# guide image -> tour screenshot name (iosApp/iosAppUITests/ScreenshotTour.swift numbers them in tour order)
import glob
shots = {"home": "home-live", "home-menu": "home-menu", "subscriptions": "subscriptions", "library": "library",
         "bookmarks": "bookmarks", "item-actions": "item-actions", "trending": "trending",
         "search-suggestions": "search-suggestions", "search-results": "search-results",
         "open-link": "open-link", "download-settings": "download-settings", "settings": "settings",
         "home-tabs": "home-tabs", "backup": "backup", "player": "player",
         "download-sheet": "download-sheet", "player-scrub": "player-scrub"}
for name, shot in shots.items():
    path, = glob.glob(f"{tour}/[0-9][0-9]-{shot}.png")
    image = Image.open(path).convert("RGB")
    image.resize((420, round(420 * image.height / image.width)), Image.LANCZOS).save(f"{out}/{name}.jpg", quality=82, optimize=True)
    print("updated", name)
PY
echo "Review the images before committing: live content (trending, search results) changes every run."
