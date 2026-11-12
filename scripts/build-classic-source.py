#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Build the public SideStore/Classic source from published GitHub release assets only."""
import argparse
from datetime import datetime
import hashlib
from html import escape
import importlib.util
import json
import os
from pathlib import Path
import re
import tempfile
from urllib.parse import quote, urlsplit
from urllib.request import Request, urlopen

spec = importlib.util.spec_from_file_location("altstore_source", Path(__file__).with_name("prepare-altstore-source.py"))
source = importlib.util.module_from_spec(spec)
spec.loader.exec_module(source)


def fetch(url, token=None):
    headers = {"User-Agent": "DriftLoom-source-publisher", "Accept": "application/vnd.github+json"}
    # Release downloads are public and must never receive the API credential.
    if token and urlsplit(url).hostname == "api.github.com":
        headers["Authorization"] = "Bearer " + token
    with urlopen(Request(url, headers=headers), timeout=120) as response:
        return response.read()


def releases(repository):
    result = []
    page = 1
    while True:
        batch = json.loads(fetch(f"https://api.github.com/repos/{repository}/releases?per_page=100&page={page}", os.environ.get("GITHUB_TOKEN")))
        if not isinstance(batch, list):
            raise ValueError("GitHub did not return a release list")
        result.extend(batch)
        if len(batch) < 100:
            return result
        page += 1


def public_asset_url(asset, repository):
    url = asset["browser_download_url"]
    parsed = urlsplit(url)
    if parsed.scheme != "https" or parsed.netloc != "github.com" or not parsed.path.startswith(f"/{repository}/releases/download/"):
        raise ValueError("Release asset points outside the expected public repository")
    return url


def version_key(version):
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", version):
        raise ValueError("Unsupported app version: " + version)
    parts = tuple(int(part) for part in version.split("."))
    return parts + (0,) * (3 - len(parts))


def build(repository, records):
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("Invalid repository")
    if repository != "sk3llo/DriftLoom":
        raise ValueError("This publisher is configured for sk3llo/DriftLoom")
    candidates = []
    for release in records:
        if release.get("draft") or release.get("prerelease"):
            continue
        assets = release.get("assets", [])
        ipas = [a for a in assets if re.fullmatch(r"DriftLoom-[0-9.]+\.ipa", a["name"])]
        if not ipas:
            continue
        if len(ipas) != 1:
            raise ValueError("A release must have exactly one DriftLoom IPA")
        ipa = ipas[0]
        digest_asset = next((a for a in assets if a["name"] == ipa["name"] + ".sha256"), None)
        if digest_asset is None:
            raise ValueError("Missing checksum for " + ipa["name"])
        digest_text = fetch(public_asset_url(digest_asset, repository)).decode().strip().split()
        if len(digest_text) != 2 or not re.fullmatch(r"[a-fA-F0-9]{64}", digest_text[0]) or digest_text[1].lstrip("*") != ipa["name"]:
            raise ValueError("Invalid checksum file for " + ipa["name"])
        url = public_asset_url(ipa, repository)
        data = fetch(url)
        digest = hashlib.sha256(data).hexdigest()
        if digest != digest_text[0].lower() or len(data) != ipa["size"]:
            raise ValueError("Checksum or size mismatch for " + ipa["name"])
        if ipa.get("digest") and ipa["digest"] != "sha256:" + digest:
            raise ValueError("GitHub asset digest mismatch for " + ipa["name"])
        published = release["published_at"]
        datetime.fromisoformat(published.replace("Z", "+00:00"))
        with tempfile.TemporaryDirectory(prefix="driftloom-release-") as temporary:
            path = Path(temporary) / ipa["name"]
            path.write_bytes(data)
            args = argparse.Namespace(ipa=path, adp_dir=None, base_url=url.rsplit("/", 1)[0],
                                      marketplace_id=None, developer_name="DriftLoom", release_date=published[:10])
            item = source.prepare(args)
        app = item["apps"][0]
        version = app["versions"][0]
        if release["tag_name"] != "v" + version["version"] or ipa["name"] != "DriftLoom-" + version["version"] + ".ipa":
            raise ValueError("Release tag, filename and IPA version must match")
        version.update(date=published, sha256=digest, downloadURL=url,
                       localizedDescription=(release.get("body") or "DriftLoom " + version["version"]).strip())
        candidates.append((version_key(version["version"]), item))
    if not candidates:
        raise ValueError("No published stable IPA releases; the existing source must remain online")
    candidates.sort(key=lambda entry: entry[0], reverse=True)
    result = candidates[0][1]
    versions, seen = [], set()
    entitlements, privacy = set(), {}
    for key, item in candidates:
        app = item["apps"][0]
        if key in seen:
            raise ValueError("Duplicate app version in published releases")
        seen.add(key)
        versions.extend(app["versions"])
        entitlements.update(app["appPermissions"]["entitlements"])
        # Prefer the latest wording when an older version uses the same permission.
        for name, value in app["appPermissions"]["privacy"].items():
            privacy.setdefault(name, value)
    result["apps"][0]["versions"] = versions
    result["apps"][0]["appPermissions"] = {"entitlements": sorted(entitlements), "privacy": privacy}
    result["description"] = "Install and update DriftLoom with SideStore or AltStore Classic. Sign using your own Apple account; free accounts need refreshing every 7 days."
    return result


def write_site(result, output, source_url):
    source_url = source.https_url(source_url)
    output.mkdir(parents=True, exist_ok=True)
    (output / "source.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    (output / ".nojekyll").write_text("")
    latest = result["apps"][0]["versions"][0]
    page = f'''<!doctype html>
<html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Install DriftLoom</title>
<style>body{{margin:0;background:#1f1650;color:#fff;font:18px/1.6 system-ui,sans-serif}}main{{max-width:640px;margin:8vh auto;padding:28px}}img{{width:88px;border-radius:20px}}h1{{font-size:44px;line-height:1.15}}a{{color:#ffc857}}.button{{display:inline-block;background:#ff8a5b;color:#1f1650;font-weight:650;padding:12px 18px;border-radius:12px;margin:6px 8px 6px 0;text-decoration:none}}code{{display:block;overflow-wrap:anywhere;background:#ffffff15;padding:14px;border-radius:10px;font-size:14px}}small{{color:#dfd8f7}}</style>
<main><img src="{escape(result['iconURL'])}" alt=""><h1>DriftLoom</h1>
<p>YouTube and SoundCloud, without ads or an account in the app.</p>
<p>Install SideStore or AltStore Classic first, then add the public DriftLoom source:</p>
<a class="button" href="sidestore://source?url={quote(source_url, safe='')}">Add to SideStore</a>
<a class="button" href="altstore://source?url={quote(source_url, safe='')}">Add to AltStore Classic</a>
<p>Or paste this address in your installer's Sources screen:</p><code>{escape(source_url)}</code>
<p>Latest release: <strong>{escape(latest['version'])}</strong> · iOS {escape(latest['minOSVersion'])} or later.</p>
<p><a href="https://github.com/sk3llo/DriftLoom/blob/main/docs/install-ios.md">Installation and refresh instructions</a> · <a href="{escape(latest['downloadURL'])}">Download IPA</a> · <a href="source.json">View source</a></p>
<p><small>No paid Apple Developer membership is needed to publish this source. Users install with their own Apple account. Free accounts still require refreshing every seven days; a source makes updates easier but does not change Apple's signing limits.</small></p></main></html>'''
    (output / "index.html").write_text(page + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", default="sk3llo/DriftLoom")
    parser.add_argument("--source-url", default="https://sk3llo.github.io/DriftLoom/source.json")
    parser.add_argument("--output", type=Path, default=Path("build/classic-source"))
    args = parser.parse_args()
    try:
        result = build(args.repository, releases(args.repository))
        write_site(result, args.output, args.source_url)
        print("Prepared source with " + str(len(result["apps"][0]["versions"])) + " published version(s).")
    except (ValueError, KeyError, OSError) as error:
        parser.exit(1, f"Public source build failed: {error}\n")
