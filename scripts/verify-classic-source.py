#!/usr/bin/env python3
"""A successful Pages API response is insufficient: verify the canonical public file."""
import argparse
import hashlib
import json
import re
import time
from urllib.parse import urlsplit
from urllib.request import Request, urlopen


def read_source(url):
    request = Request(url, headers={"Cache-Control": "no-cache", "User-Agent": "DriftLoom-source-verifier"})
    with urlopen(request, timeout=15) as response:
        return response.read()


def verify(url, expected, attempts=21, delay=30):
    parsed = urlsplit(url)
    if parsed.scheme != "https" or not parsed.hostname or parsed.query or parsed.fragment or parsed.username or parsed.password:
        raise ValueError("Verify the canonical public HTTPS source URL without a cache-busting query")
    if not re.fullmatch(r"[a-f0-9]{64}", expected):
        raise ValueError("Expected SHA-256 is missing or invalid")
    if attempts < 1 or not 0 <= delay <= 30:
        raise ValueError("Invalid retry settings")
    for attempt in range(1, attempts + 1):
        try:
            data = read_source(url)
            if hashlib.sha256(data).hexdigest() == expected:
                source = json.loads(data)
                versions = [v["version"] for v in source["apps"][0]["versions"]]
                print("Verified canonical public source: " + ", ".join(versions), flush=True)
                return
            message = "the public file still differs from the uploaded artifact"
        except OSError as error:
            message = str(error)
        print(f"Public source check {attempt}/{attempts}: {message}", flush=True)
        if attempt < attempts:
            time.sleep(delay)
    raise RuntimeError("Pages reported success, but the canonical public source did not match the uploaded artifact")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", required=True)
    parser.add_argument("--sha256", required=True)
    args = parser.parse_args()
    try:
        verify(args.url, args.sha256)
    except (ValueError, KeyError, RuntimeError) as error:
        parser.exit(1, f"Source verification failed: {error}\n")
