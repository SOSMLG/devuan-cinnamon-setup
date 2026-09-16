#!/usr/bin/env python3
"""
dconf-list-remove.py — idempotently removes a string from a dconf/gsettings
string-array key, run as the target user (the caller is responsible for
that — this script just does the get/modify/set).

Usage:
    python3 dconf-list-remove.py <schema> <key> <value>

If <value> is not present in the list, does nothing (exit 0, prints
NOT_PRESENT). Otherwise removes it and writes the list back (exit 0, prints
OK). Any gsettings failure (e.g. no active session) prints FAILED and
exits 1.
"""
import sys
import subprocess
import ast


def main():
    if len(sys.argv) != 4:
        print("Usage: dconf-list-remove.py <schema> <key> <value>", file=sys.stderr)
        sys.exit(2)

    schema, key, value = sys.argv[1], sys.argv[2], sys.argv[3]

    out = subprocess.run(["gsettings", "get", schema, key], capture_output=True, text=True)
    if out.returncode != 0:
        print("FAILED")
        sys.exit(1)

    raw = out.stdout.strip()
    try:
        current = ast.literal_eval(raw) if raw else []
        if not isinstance(current, list):
            current = []
    except Exception:
        current = []

    if value not in current:
        print("NOT_PRESENT")
        return

    current = [item for item in current if item != value]
    new_value = str(current).replace('"', "'")

    result = subprocess.run(["gsettings", "set", schema, key, new_value])
    if result.returncode != 0:
        print("FAILED")
        sys.exit(1)

    print("OK")


if __name__ == "__main__":
    main()