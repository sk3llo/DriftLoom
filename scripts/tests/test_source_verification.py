import hashlib
import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("verifier", Path(__file__).resolve().parents[1] / "verify-classic-source.py")
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


class SourceVerificationTests(unittest.TestCase):
    url = "https://sk3llo.github.io/DriftLoom/source.json"
    current = json.dumps({"apps": [{"versions": [{"version": "1.0.1"}, {"version": "1.0"}]}]}).encode()

    def test_waits_for_cached_old_content_to_be_replaced(self):
        with patch.object(verifier, "read_source", side_effect=[b"old cached content", self.current]):
            verifier.verify(self.url, hashlib.sha256(self.current).hexdigest(), attempts=2, delay=0)

    def test_never_passes_when_only_the_old_source_is_live(self):
        with patch.object(verifier, "read_source", return_value=b"old cached content"):
            with self.assertRaisesRegex(RuntimeError, "did not match"):
                verifier.verify(self.url, hashlib.sha256(self.current).hexdigest(), attempts=2, delay=0)

    def test_does_not_substitute_a_cache_busted_url_for_the_real_source(self):
        with self.assertRaisesRegex(ValueError, "canonical"):
            verifier.verify(self.url + "?fresh=1", hashlib.sha256(self.current).hexdigest())


if __name__ == "__main__":
    unittest.main()
