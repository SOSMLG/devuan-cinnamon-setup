#!/usr/bin/env python3
"""
apply-burnmywindows-settings.py — writes CinnamonBurnMyWindows@klangman
settings.json into ~/.cinnamon/configs/, merging our choices over the
schema's official defaults so the file stays valid across extension
updates.

Read only the general-purpose keys the plan cares about:
  * open-window-effect   = 6  (Glide) — subtle, no color tint
  * close-window-effect  = 6  (Glide)
  * minimize/unminimize  = 1000 (None) — keep Cinnamon's default animation
  * power-*-effect       = 1000 (None) — nothing extra on battery either
  * enable-sound         = false
  * glide knob settings  = subtle defaults
  * effect-selector      = 6  (settings dialog shows the Glide page)

Prints OK on success, FAILED + exit 1 on any hard error.
"""
import glob
import json
import os
import sys

UUID = "CinnamonBurnMyWindows@klangman"
CONFIG_DIR = os.path.join(os.path.expanduser("~"), ".cinnamon", "configs", UUID)
EXT_DIR = os.path.join(os.path.expanduser("~"), ".local", "share", "cinnamon", "extensions", UUID)

OVERRIDES = {
    "open-window-effect": 6,    # Glide
    "close-window-effect": 6,   # Glide
    "minimize-effect": 1000,    # None
    "unminimize-effect": 1000,  # None
    "power-open-effect": 1000,
    "power-close-effect": 1000,
    "power-minimize-effect": 1000,
    "power-unminimize-effect": 1000,
    "enable-sound": False,
    "effect-selector": 6,
    "glide-scale": 0.90,
    "glide-squish": 0.10,
    "glide-tilt": -0.25,
    "glide-shift": -0.05,
    "glide-animation-time": 220,
}


def find_schema():
    candidates = sorted(glob.glob(os.path.join(EXT_DIR, "*", "settings-schema.json")))
    return candidates[-1] if candidates else None


def main():
    schema_path = find_schema()
    if not schema_path:
        print("FAILED: no settings-schema.json found for " + UUID)
        sys.exit(1)
    try:
        with open(schema_path, encoding="utf-8") as fh:
            schema = json.load(fh)
    except OSError as exc:
        print(f"FAILED: cannot read {schema_path}: {exc}")
        sys.exit(1)

    settings = {}
    for key, entry in schema.items():
        if not isinstance(entry, dict) or "type" not in entry:
            continue
        default = entry.get("default")
        if key in OVERRIDES:
            default = OVERRIDES[key]
        if default is None:
            default = entry.get("value")  # arbitrary returned by schema
        settings[key] = {
            "type": entry["type"],
            "default": default,
            "value": default,
        }

    os.makedirs(CONFIG_DIR, exist_ok=True)
    out_path = os.path.join(CONFIG_DIR, "settings.json")
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(settings, fh, indent=2)
    print(f"OK: wrote {out_path}")


if __name__ == "__main__":
    main()