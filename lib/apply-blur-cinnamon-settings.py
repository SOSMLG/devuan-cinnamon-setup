#!/usr/bin/env python3
"""
apply-blur-cinnamon-settings.py — writes BlurCinnamon@klangman settings.json
into ~/.cinnamon/configs/, merging our choices over the schema's official
defaults so the file stays valid across extension updates.

This is what activates the already-installed Blur Cinnamon extension on a
vanilla install (the extension ships installed by step 05 but never
configured).

Goals (all schema-validated):
  * panels           ON  — translucent panel over a Gaussian/Dual-Kawase blur
  * popup menus      ON  — blurred applet/panel/title context menus
  * overview / expo  ON  — blurred overview + expo
  * alt-tab          ON  — blurred application switcher
  * dimming overlay  rgb(30,30,46) (#1e1e2e Mocha base) at 40%
  * blur radius      12, Dual Kawase dynamic (gentle on GPUs)

Prints OK on success, FAILED + exit 1 on any hard error.
"""
import glob
import json
import os
import sys

UUID = "BlurCinnamon@klangman"
CONFIG_DIR = os.path.join(os.path.expanduser("~"), ".cinnamon", "configs", UUID)
EXT_DIR = os.path.join(os.path.expanduser("~"), ".local", "share", "cinnamon", "extensions", UUID)

OVERRIDES = {
    "enable-panels-effects": True,
    "enable-popup-effects": True,
    "enable-overview-effects": True,
    "enable-expo-effects": True,
    "enable-appswitcher-effects": True,
    "enable-notification-effects": False,
    "enable-desklet-effects": False,
    "enable-window-effects": False,
    "enable-tooltips-effects": False,
    "allow-transparent-color-panels": True,
    "allow-transparent-color-popup": True,
    "allow-transparent-color-switcher": True,
    "opacity": 40,
    "blendColor": "rgb(30,30,46)",
    "blurType": 8,          # Dual Kawase dynamic
    "radius": 12,
    "saturation": 100,
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
            default = entry.get("value")
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