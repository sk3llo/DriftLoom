import argparse
import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location("source", Path(__file__).resolve().parents[1] / "prepare-altstore-source.py")
source = importlib.util.module_from_spec(spec)
spec.loader.exec_module(source)


class SourceTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.ipa = self.root / "DriftLoom-1.0.1.ipa"
        self.metadata = {"CFBundleIdentifier": source.BUNDLE_ID, "CFBundleShortVersionString": "1.0.1",
                         "CFBundleVersion": "2", "MinimumOSVersion": "15.0", "DTPlatformName": "iphoneos",
                         "DriftLoomSharedAppGroup": "group.net.driftloom.app.shared"}
        with zipfile.ZipFile(self.ipa, "w") as archive:
            archive.writestr("Payload/DriftLoom.app/Info.plist", plistlib.dumps(self.metadata))
        self.args = argparse.Namespace(ipa=self.ipa, adp_dir=None, base_url="https://downloads.driftloom.test/releases/v1.0.1",
                                      marketplace_id=None, developer_name="Test developer", release_date="2026-11-12")

    def test_classic_uses_real_ipa_metadata_and_never_a_marketplace_manifest(self):
        with patch.object(source.subprocess, "run", return_value=argparse.Namespace(returncode=1)):
            result = source.prepare(self.args)
        app = result["apps"][0]
        self.assertNotIn("marketplaceID", app)
        version = app["versions"][0]
        self.assertNotIn("buildVersion", version)
        self.assertEqual((version["version"], version["size"]), ("1.0.1", self.ipa.stat().st_size))
        self.assertTrue(version["downloadURL"].endswith("/DriftLoom-1.0.1.ipa"))

    def test_pal_requires_real_id_complete_adp_and_signed_variants(self):
        self.args.adp_dir, self.args.ipa = self.root, None
        for invalid in [None, "APPLE_ID_FROM_APP_STORE_CONNECT", "0"]:
            self.args.marketplace_id = invalid
            with self.assertRaisesRegex(ValueError, "numeric Apple app ID"):
                source.prepare(self.args)
        self.args.marketplace_id = "123456789"
        with self.assertRaisesRegex(ValueError, "manifest.json"):
            source.prepare(self.args)
        (self.root / "manifest.json").write_text("{}")
        (self.root / "signature").write_bytes(b"fixture")
        with patch.object(source.subprocess, "run", return_value=argparse.Namespace(returncode=1)):
            with self.assertRaisesRegex(ValueError, "signed ADP"):
                source.prepare(self.args)

    def test_pal_source_points_at_manifest_and_preserves_package(self):
        self.args.adp_dir, self.args.ipa, self.args.marketplace_id = self.root, None, "123456789"
        manifest = b'{"fixture": true}\n'
        (self.root / "manifest.json").write_bytes(manifest)
        (self.root / "signature").write_bytes(b"fixture")
        permissions = {"entitlements": ["com.apple.security.application-groups"], "privacy": {}}
        with patch.object(source, "read_ipa", return_value=(self.metadata, permissions)):
            result = source.prepare(self.args)
        app = result["apps"][0]
        self.assertEqual(app["marketplaceID"], "123456789")
        self.assertTrue(app["versions"][0]["downloadURL"].endswith("/manifest.json"))
        self.assertEqual(app["appPermissions"], permissions)
        self.assertEqual((self.root / "manifest.json").read_bytes(), manifest)

    def test_rejects_placeholder_and_insecure_hosts(self):
        for url in ["https://HOST/driftloom", "https://example.com/app", "http://downloads.driftloom.test", "https://user:password@downloads.driftloom.test"]:
            self.args.base_url = url
            with self.assertRaisesRegex(ValueError, "real public HTTPS"):
                source.prepare(self.args)

    def test_pal_rejects_development_signing_and_missing_shared_group(self):
        for entitlements, message in [({"get-task-allow": True}, "development build"), ({}, "matching signed App Group")]:
            signed = argparse.Namespace(returncode=0, stdout=plistlib.dumps(entitlements))
            with patch.object(source.subprocess, "run", return_value=signed):
                with self.assertRaisesRegex(ValueError, message):
                    source.read_ipa(self.ipa, require_signed=True)


if __name__ == "__main__":
    unittest.main()
