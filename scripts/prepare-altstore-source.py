#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Generate an AltStore source from a real IPA or notarized PAL package. Never uploads files."""
import argparse
from datetime import date
import json
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
from urllib.parse import quote, urlsplit
import zipfile

BUNDLE_ID = "net.driftloom.app.DriftLoom"
REPOSITORY = "https://github.com/sk3llo/DriftLoom"
ASSETS = "https://raw.githubusercontent.com/sk3llo/DriftLoom/main/"


def https_url(value):
    url = urlsplit(value)
    if (url.scheme != "https" or not url.hostname or url.username or url.password or url.query or url.fragment
            or url.hostname.lower() in {"host", "example.com", "localhost"} or "<" in value or ">" in value):
        raise ValueError("Use the real public HTTPS base URL, without credentials, query or fragment")
    return value.rstrip("/")


def read_ipa(path, require_signed):
    """Inspect each bundle's actual permissions, including extensions, without changing the IPA."""
    with tempfile.TemporaryDirectory(prefix="driftloom-source-") as temporary, zipfile.ZipFile(path) as archive:
        root = Path(temporary)
        for name in archive.namelist():
            try:
                (root / name).resolve().relative_to(root.resolve())
            except ValueError:
                raise ValueError("IPA contains an unsafe file path")
        archive.extractall(root)
        apps = list((root / "Payload").glob("*.app"))
        if len(apps) != 1:
            raise ValueError("IPA must contain exactly one app")
        app = apps[0]
        main = plistlib.loads((app / "Info.plist").read_bytes())
        if main["CFBundleIdentifier"] != BUNDLE_ID:
            raise ValueError("IPA has the wrong DriftLoom bundle ID")
        if require_signed and main.get("DTPlatformName") != "iphoneos":
            raise ValueError("PAL requires an iPhone device build, not a simulator app")
        entitlements, privacy = set(), {}
        for bundle in [app, *app.glob("PlugIns/*.appex")]:
            info = plistlib.loads((bundle / "Info.plist").read_bytes())
            privacy.update({k: v for k, v in info.items() if k.endswith("UsageDescription") and isinstance(v, str)})
            result = subprocess.run(["codesign", "-d", "--entitlements", "-", str(bundle)], capture_output=True)
            if result.returncode:
                if require_signed:
                    raise ValueError("PAL requires Apple's signed ADP; an unsigned build is not a distribution package")
                continue
            values = plistlib.loads(result.stdout) if result.stdout.strip() else {}
            if require_signed and values.get("get-task-allow"):
                raise ValueError("PAL requires distribution signing, not a development build")
            if require_signed and info["CFBundleIdentifier"] in {BUNDLE_ID, BUNDLE_ID + ".Share"}:
                if values.get("com.apple.security.application-groups") != ["group.net.driftloom.app.shared"]:
                    raise ValueError("The app and Share extension need their matching signed App Group")
            entitlements.update(k for k, v in values.items() if v and k not in {"application-identifier", "com.apple.developer.team-identifier"})
        if require_signed and (main.get("DriftLoomSharedAppGroup") != "group.net.driftloom.app.shared"
                               or "com.apple.security.application-groups" not in entitlements):
            raise ValueError("The PAL app is missing its shared-link App Group")
        return main, {"entitlements": sorted(entitlements), "privacy": privacy}


def prepare(args):
    base_url = https_url(args.base_url)
    date.fromisoformat(args.release_date)
    if not args.developer_name.strip():
        raise ValueError("Developer name must match the actual developer")
    pal = args.adp_dir is not None
    if pal:
        if not args.marketplace_id or not re.fullmatch(r"[1-9][0-9]*", args.marketplace_id):
            raise ValueError("PAL requires the numeric Apple app ID from App Store Connect")
        for name in ["manifest.json", "signature"]:
            if not (args.adp_dir / name).is_file() or not (args.adp_dir / name).stat().st_size:
                raise ValueError("ADP is missing " + name)
        json.loads((args.adp_dir / "manifest.json").read_bytes())
        variants = sorted(args.adp_dir.rglob("*.ipa"))
        if not variants:
            raise ValueError("ADP contains no IPA variants")
        ipa = variants[0]
        download_url = base_url + "/manifest.json"
    else:
        if args.marketplace_id:
            raise ValueError("A Classic source must not have a PAL marketplace ID")
        ipa = args.ipa
        download_url = base_url + "/" + quote(ipa.name)
    main, permissions = read_ipa(ipa, require_signed=pal)
    version = main["CFBundleShortVersionString"]
    notes = Path(__file__).resolve().parent.parent / "docs/release-notes" / (version + ".md")
    app = {
        "name": "DriftLoom", "bundleIdentifier": BUNDLE_ID, "developerName": args.developer_name,
        "subtitle": "No ads, no tracking, no account",
        "localizedDescription": "A free YouTube and SoundCloud client with subscriptions, background audio, Picture in Picture, queues and offline downloads. Your library stays on your device.",
        "iconURL": ASSETS + "iosApp/iosApp/Assets.xcassets/AppIcon.appiconset/app-icon-1024.png",
        "tintColor": "#2E1C66", "category": "entertainment",
        "screenshots": [{"imageURL": ASSETS + "docs/user-guide/images/" + name + ".jpg", "width": 420, "height": 747}
                        for name in ["home", "player", "subscriptions", "library"]],
        "versions": [{"version": version, "buildVersion": main["CFBundleVersion"], "date": args.release_date,
                      "localizedDescription": notes.read_text() if notes.is_file() else "DriftLoom " + version,
                      "downloadURL": download_url, "size": ipa.stat().st_size, "minOSVersion": main["MinimumOSVersion"]}],
        "appPermissions": permissions,
    }
    if pal:
        app["marketplaceID"] = args.marketplace_id
    else:
        # Keep the shared SideStore/Classic feed free of marketplace build metadata.
        app["versions"][0].pop("buildVersion")
    return {"name": "DriftLoom" + (" PAL" if pal else ""),
            "identifier": "net.driftloom.source." + ("pal" if pal else "classic"),
            "subtitle": "Free YouTube and SoundCloud client", "website": REPOSITORY,
            "iconURL": app["iconURL"], "apps": [app]}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    artifact = parser.add_mutually_exclusive_group(required=True)
    artifact.add_argument("--ipa", type=Path, help="Unsigned IPA for Classic/SideStore")
    artifact.add_argument("--adp-dir", type=Path, help="Unchanged Apple-signed ADP for PAL")
    parser.add_argument("--base-url", required=True, help="Public directory containing the IPA or ADP manifest")
    parser.add_argument("--marketplace-id", help="PAL only: numeric Apple app ID")
    parser.add_argument("--developer-name", required=True)
    parser.add_argument("--release-date", required=True, help="YYYY-MM-DD")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.adp_dir and (args.output.resolve() == args.adp_dir.resolve() or args.adp_dir.resolve() in args.output.resolve().parents):
            raise ValueError("Write source.json outside the ADP so Apple's package stays unchanged")
        result = prepare(args)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
        print("Prepared " + str(args.output) + ". Verify the hosted files before publishing this source.")
    except (ValueError, KeyError, OSError, zipfile.BadZipFile, plistlib.InvalidFileException) as error:
        parser.exit(1, f"Source preparation failed: {error}\n")
