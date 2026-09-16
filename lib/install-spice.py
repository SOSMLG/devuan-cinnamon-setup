#!/usr/bin/env python3
"""
install-spice.py — fetches one Cinnamon Spice (extension or applet) into
{~/.local/share/cinnamon/}/extensions|applets/<UUID>/.

Primary source: the official Linux Mint Spices website, which serves a
pre-assembled zip per spice at
    https://cinnamon-spices.linuxmint.com/files/{extensions,applets}/<UUID>.zip
This is the exact endpoint Cinnamon's own Settings app uses, needs a single
request (no GitHub API rate limits), and the zip contains
<UUID>/... with the layout Cinnamon expects.

Fallback source: the raw linuxmint/cinnamon-spices-{extensions,applets}
repo on GitHub via its Contents API (used when the Spices site is
unreachable). Both paths write to <dest_root>/<UUID>/.

Usage:
    python3 install-spice.py <extensions|applets> <UUID> <dest_root_dir>

Exit: 0 on success (prints "OK"), 1 on hard failure, 2 on usage error.
"""
import sys
import os
import io
import json
import zipfile
import urllib.request
import urllib.error

KIND_URL = "https://cinnamon-spices.linuxmint.com/files"
REPO = {
    "extensions": "linuxmint/cinnamon-spices-extensions",
    "applets": "linuxmint/cinnamon-spices-applets",
}
HEADERS = {"User-Agent": "devuan-cinnamon-setup"}


def http_bytes(url, timeout=30):
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def api_get(url):
    return json.loads(http_bytes(url))


def fetch_zip(kind, uuid):
    """Primary path — one zip download from the official Spices site."""
    url = f"{KIND_URL}/{kind}/{uuid}.zip"
    return http_bytes(url)


def fetch_contents_api(kind, uuid):
    """
    Fallback path — walk the GitHub Contents API for that one spice's
    directory. Slower (one request per file) and subject to GitHub's
    unauthenticated rate limit (~60 reqs/hr), so it's only used if the
    Spices site is down.
    """
    entries = []

    def walk(api_url, local_dir, depth=0):
        if depth > 6:
            return
        for entry in api_get(api_url):
            name = entry["name"]
            if entry["type"] == "dir":
                walk(entry["url"], os.path.join(local_dir, name), depth + 1)
            elif entry["type"] == "file":
                entries.append((os.path.join(local_dir, name), entry["download_url"]))

    api_url = f"https://api.github.com/repos/{REPO[kind]}/contents/{uuid}/files/{uuid}"
    walk(api_url, uuid)
    return entries


def extract_zip(data, dest_root):
    """Extract a spice zip to dest_root/<UUID>/... Safely."""
    with zipfile.ZipFile(io.BytesIO(data)) as zf:
        # Guard against path traversal ("../", absolute paths).
        for name in zf.namelist():
            joined = os.path.normpath(os.path.join(dest_root, name))
            if not joined.startswith(os.path.normpath(dest_root) + os.sep) and joined != os.path.normpath(dest_root):
                raise RuntimeError(f"unsafe path in spice zip: {name}")
        zf.extractall(dest_root)


def main():
    if len(sys.argv) != 4:
        print("Usage: install-spice.py <extensions|applets> <UUID> <dest_root_dir>", file=sys.stderr)
        sys.exit(2)

    kind, uuid, dest_root = sys.argv[1], sys.argv[2], sys.argv[3]
    if kind not in REPO:
        print(f"Unknown kind '{kind}' (expected 'extensions' or 'applets')", file=sys.stderr)
        sys.exit(2)

    local_dir = os.path.join(dest_root, uuid)

    # 1) Primary: official Spices-site zip.
    try:
        data = fetch_zip(kind, uuid)
        extract_zip(data, dest_root)
    except Exception as e:
        print(f"Spices-site zip failed ({e}); falling back to GitHub Contents API.", file=sys.stderr)
        try:
            entries = fetch_contents_api(kind, uuid)
            if not entries:
                raise RuntimeError("GitHub Contents API returned no files")
            for rel, url in entries:
                target = os.path.join(dest_root, rel)
                os.makedirs(os.path.dirname(target), exist_ok=True)
                with open(target, "wb") as f:
                    f.write(http_bytes(url))
        except urllib.error.HTTPError as e:
            print(f"HTTP error fetching {uuid}: {e.code} {e.reason}", file=sys.stderr)
            sys.exit(1)
        except Exception as e:
            print(f"Failed to fetch {uuid}: {e}", file=sys.stderr)
            sys.exit(1)

    if not os.path.isdir(local_dir) or not os.listdir(local_dir):
        print(f"Fetched nothing for {uuid} — dest dir is empty.", file=sys.stderr)
        sys.exit(1)

    print("OK")


if __name__ == "__main__":
    main()