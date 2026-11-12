import argparse
from copy import deepcopy
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location("publisher", Path(__file__).resolve().parents[1] / "build-classic-source.py")
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


class PublisherTests(unittest.TestCase):
    def release(self, version):
        name = f"DriftLoom-{version}.ipa"
        prefix = f"https://github.com/sk3llo/DriftLoom/releases/download/v{version}/"
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            archive.writestr("Payload/DriftLoom.app/Info.plist", plistlib.dumps({
                "CFBundleIdentifier": publisher.source.BUNDLE_ID, "CFBundleShortVersionString": version,
                "CFBundleVersion": "1", "MinimumOSVersion": "15.0"}))
            archive.writestr("Payload/DriftLoom.app/PlugIns/Share.appex/Info.plist", plistlib.dumps({
                "CFBundleIdentifier": publisher.source.BUNDLE_ID + ".Share",
                "NSCameraUsageDescription": "Fixture permission from the extension"}))
        data = buffer.getvalue()
        digest = hashlib.sha256(data).hexdigest()
        record = {"tag_name": "v" + version, "published_at": "2026-11-10T12:46:48Z", "body": "Release " + version,
                  "draft": False, "prerelease": False, "assets": [
                      {"name": name, "size": len(data), "browser_download_url": prefix + name, "digest": "sha256:" + digest},
                      {"name": name + ".sha256", "browser_download_url": prefix + name + ".sha256"}]}
        files = {prefix + name: data, prefix + name + ".sha256": (digest + "  " + name + "\n").encode()}
        return record, files

    def build(self, records, files):
        with patch.object(publisher, "fetch", side_effect=lambda url: files[url]), \
             patch.object(publisher.source.subprocess, "run", return_value=argparse.Namespace(returncode=1)):
            return publisher.build("sk3llo/DriftLoom", records)

    def test_orders_versions_numerically_and_keeps_older_versions(self):
        old, old_files = self.release("1.0.2")
        new, new_files = self.release("1.0.11")
        result = self.build([old, new], dict(old_files, **new_files))
        app = result["apps"][0]
        self.assertEqual([v["version"] for v in app["versions"]], ["1.0.11", "1.0.2"])
        self.assertEqual(result["identifier"], "net.driftloom.source.classic")
        self.assertNotIn("marketplaceID", app)
        self.assertTrue(all("buildVersion" not in v and len(v["sha256"]) == 64 for v in app["versions"]))
        self.assertIn("NSCameraUsageDescription", app["appPermissions"]["privacy"])

    def test_never_advertises_drafts_prereleases_or_missing_ipas(self):
        stable, files = self.release("1.0")
        draft, _ = self.release("2.0")
        draft["draft"] = True
        beta, _ = self.release("3.0")
        beta["prerelease"] = True
        android_only = dict(stable, assets=[])
        result = self.build([draft, beta, android_only, stable], files)
        self.assertEqual([v["version"] for v in result["apps"][0]["versions"]], ["1.0"])
        with self.assertRaisesRegex(ValueError, "No published stable IPA"):
            self.build([draft, beta, android_only], {})

    def test_rejects_tampered_downloads_and_mismatched_tags(self):
        record, files = self.release("1.0")
        broken = deepcopy(files)
        broken[record["assets"][0]["browser_download_url"]] += b"tampered"
        with self.assertRaisesRegex(ValueError, "Checksum or size mismatch"):
            self.build([record], broken)
        record["tag_name"] = "v1.0.1"
        with self.assertRaisesRegex(ValueError, "must match"):
            self.build([record], files)

    def test_refuses_unverified_or_external_assets(self):
        record, files = self.release("1.0")
        missing = deepcopy(record)
        missing["assets"].pop()
        with self.assertRaisesRegex(ValueError, "Missing checksum"):
            self.build([missing], files)
        record["assets"][1]["browser_download_url"] = "https://example.com/checksum"
        with self.assertRaisesRegex(ValueError, "outside"):
            self.build([record], files)

    def test_install_links_use_the_same_public_source(self):
        record, files = self.release("1.0")
        result = self.build([record], files)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            publisher.write_site(result, root, "https://sk3llo.github.io/DriftLoom/source.json")
            self.assertEqual(json.loads((root / "source.json").read_text()), result)
            page = (root / "index.html").read_text()
            for scheme in ["sidestore", "altstore"]:
                self.assertIn(scheme + "://source?url=https%3A%2F%2Fsk3llo.github.io%2FDriftLoom%2Fsource.json", page)


if __name__ == "__main__":
    unittest.main()
