#!/usr/bin/env python3
"""Check the finished app, rather than trusting its requested build settings."""
import argparse
import os
import plistlib
from pathlib import Path


def check(app, channel):
    def require(condition, message):
        if not condition:
            raise ValueError(message)

    def info(path):
        with (path / "Info.plist").open("rb") as stream:
            return plistlib.load(stream)

    main = info(app)
    require(main["CFBundleIdentifier"] == "net.driftloom.app.DriftLoom", "Unexpected app bundle ID")
    version, build = main["CFBundleShortVersionString"], main["CFBundleVersion"]
    if os.environ.get("GITHUB_REF_TYPE") == "tag":
        require(os.environ["GITHUB_REF_NAME"] == "v" + version, "Tag does not match the app version")
    group = "group.net.driftloom.app.shared" if channel == "pal" else ""
    require(main.get("DriftLoomSharedAppGroup", "") == group, "Wrong shared-link configuration")
    require((app / "PrivacyInfo.xcprivacy").is_file(), "Privacy manifest is missing")
    for name, suffix in [("DriftLoomShare", "Share"), ("DriftLoomWidgets", "Widgets")]:
        extension = app / "PlugIns" / (name + ".appex")
        details = info(extension)
        require(details["CFBundleIdentifier"] == main["CFBundleIdentifier"] + "." + suffix, "Unexpected extension ID")
        require((details["CFBundleShortVersionString"], details["CFBundleVersion"]) == (version, build), "Extension version mismatch")
        if suffix == "Share":
            require(details.get("DriftLoomSharedAppGroup", "") == group, "App and share extension must share an inbox")
            binary = (extension / details["CFBundleExecutable"]).read_bytes()
            require(b"openURL:options:completionHandler:" not in binary, "Unsupported share-extension app opening is present")
    binary = (app / main["CFBundleExecutable"]).read_bytes()
    for flag in [b"--playback-smoke-url", b"--diagnostic-smoke", b"--settings-smoke", b"--crash-smoke", b"--shared-inbox-smoke"]:
        require(flag not in binary, "Test-only launch flags are present: " + flag.decode())
    print(f"Verified {channel} app: {version} ({build}), stable bundle IDs, both extensions, no test flags")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--channel", choices=["pal", "sideload"], required=True)
    args = parser.parse_args()
    try:
        check(args.app, args.channel)
    except (ValueError, KeyError, OSError, plistlib.InvalidFileException) as error:
        parser.exit(1, f"Release check failed: {error}\n")
