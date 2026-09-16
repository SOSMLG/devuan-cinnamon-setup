#!/usr/bin/env python3
"""
set-panel-layout.py — rebuilds org.cinnamon enabled-applets into the
devuan-cinnamon-setup panel layout (idempotent, additive, preserves your
instance ids):

Left zone : menu, separator, launcher (nemo/firefox/xed/gnome-terminal as
            found), grouped-window-list
Right zone: windows-quick-list, trash, color-picker, systray, xapp-status,
            notifications, printers, removable-drives, keyboard, network,
            sound, power, calendar, cornerbar, workspace-switcher

Removals (from older runs): duplicate window-list@cinnamon.org and the
stranded favorites@cinnamon.org applet. Anything else you've added is kept.

The launcher instance also gets its config file written
(~/.cinnamon/configs/launcher@cinnamon.org/<id>.json) so the applets
actually have desktop files behind them.

Usage:
    python3 set-panel-layout.py

Prints OK (layout wrote), UNCHANGED (nothing to do), or FAILED (exit 1).
"""
import ast
import json
import os
import subprocess
import sys

LEFT_ORDER = [
    "menu@cinnamon.org",
    "separator@cinnamon.org",
    "launcher@cinnamon.org",
    "grouped-window-list@cinnamon.org",
]

RIGHT_ORDER = [
    "windows-quick-list@cinnamon.org",
    "trash@cinnamon.org",
    "color-picker@fmete",
    "systray@cinnamon.org",
    "xapp-status@cinnamon.org",
    "notifications@cinnamon.org",
    "printers@cinnamon.org",
    "removable-drives@cinnamon.org",
    "keyboard@cinnamon.org",
    "network@cinnamon.org",
    "sound@cinnamon.org",
    "power@cinnamon.org",
    "calendar@cinnamon.org",
    "cornerbar@cinnamon.org",
    "workspace-switcher@cinnamon.org",
]

REMOVE_UUIDS = {"window-list@cinnamon.org", "favorites@cinnamon.org"}

LAUNCHER_CANDIDATES = [
    "nemo.desktop",
    "firefox.desktop",
    "firefox-esr.desktop",
    "xed.desktop",
    "gnome-terminal.desktop",
]

APP_DIRS = [
    "/usr/share/applications",
    os.path.expanduser("~/.local/share/applications"),
]


def get_enabled_applets():
    out = subprocess.run(["gsettings", "get", "org.cinnamon", "enabled-applets"],
                         capture_output=True, text=True)
    if out.returncode != 0:
        raise RuntimeError("gsettings get org.cinnamon enabled-applets failed")
    raw = out.stdout.strip()
    try:
        current = ast.literal_eval(raw) if raw else []
        if not isinstance(current, list):
            current = []
    except Exception:
        current = []
    return current


def parse_entries(current):
    # returns dict "panel:zone" -> dict uuid -> (order, instance_id) and used ids
    zones = {"panel1:left": {}, "panel1:right": {}}
    used_ids = set()
    for entry in current:
        parts = entry.split(":")
        if len(parts) < 5:
            continue
        panel, zone, order, uuid, inst = parts[0], parts[1], parts[2], parts[3], parts[4]
        if inst.isdigit():
            used_ids.add(int(inst))
        if uuid in REMOVE_UUIDS:
            continue
        key = f"{panel}:{zone}"
        if key in zones:
            zones[key].setdefault(uuid, (int(order), int(inst)))
    return zones, used_ids


# Some distros ship terminals under a different desktop-file name
# (e.g. gnome-terminal >= 41 ships org.gnome.Terminal.desktop).
DESKTOP_ALIASES = {
    "gnome-terminal.desktop": "org.gnome.Terminal.desktop",
    "firefox.desktop": "firefox-esr.desktop",
}


def existing_desktop_files():
    found = []
    for cand in LAUNCHER_CANDIDATES:
        alias = DESKTOP_ALIASES.get(cand)
        names = (cand, alias) if alias else (cand,)
        for name in names:
            for d in APP_DIRS:
                if os.path.isfile(os.path.join(d, name)):
                    if name not in found:
                        found.append(name)
                    break
            else:
                continue
            break
    return found


def config_file_for(instance_id):
    return os.path.join(os.path.expanduser("~"), ".cinnamon", "configs",
                        "launcher@cinnamon.org", f"{instance_id}.json")


def write_launcher_config(instance_id, desktop_files):
    schema = os.path.join("/usr/share/cinnamon/applets/launcher@cinnamon.org",
                          "settings-schema.json")
    config_dir = os.path.join(os.path.expanduser("~"), ".cinnamon", "configs",
                              "launcher@cinnamon.org")
    os.makedirs(config_dir, exist_ok=True)
    out = config_file_for(instance_id)
    settings = {}
    if os.path.isfile(schema):
        with open(schema, encoding="utf-8") as fh:
            schema_data = json.load(fh)
        for key, entry in schema_data.items():
            if not isinstance(entry, dict) or "type" not in entry:
                continue
            val = entry.get("default", entry.get("value"))
            if key == "launcher-list":
                val = list(desktop_files)
            settings[key] = {"type": entry["type"], "default": val, "value": val}
    else:
        settings = {"launcher-list": {"type": "list", "default": list(desktop_files),
                                      "value": list(desktop_files)}}
    with open(out, "w", encoding="utf-8") as fh:
        json.dump(settings, fh, indent=2)
    return out


def main():
    try:
        current = get_enabled_applets()
        zones, used_ids = parse_entries(current)
    except Exception as exc:  # noqa: BLE001
        print(f"FAILED: {exc}")
        sys.exit(1)

    next_id = 0
    while next_id in used_ids:
        next_id += 1

    def assign(uuid):
        nonlocal next_id
        if uuid in zones["panel1:left"]:
            return zones["panel1:left"][uuid][1]
        alloc = next_id
        next_id += 1
        return alloc

    # left zone (launcher handled below)
    left_entries = []
    launcher_inst = assign("launcher@cinnamon.org")
    for order, uuid in enumerate(LEFT_ORDER):
        if uuid == "launcher@cinnamon.org":
            left_entries.append(f"panel1:left:{order}:{uuid}:{launcher_inst}")
        else:
            inst = zones["panel1:left"].get(uuid, (0, assign(uuid)))[1]
            left_entries.append(f"panel1:left:{order}:{uuid}:{inst}")

    right_seen = set()
    right_entries = []
    for order, uuid in enumerate(RIGHT_ORDER):
        if uuid in right_seen:
            continue
        right_seen.add(uuid)
        inst = zones["panel1:right"].get(uuid, (0, assign(uuid)))[1]
        right_entries.append(f"panel1:right:{order}:{uuid}:{inst}")

    # preserve anything else the user added that we didn't touch
    for uuid, (order, inst) in zones["panel1:right"].items():
        if uuid in right_seen:
            continue
        right_seen.add(uuid)
        right_entries.append(f"panel1:right:{order}:{uuid}:{inst}")

    new_layout = sorted(left_entries + right_entries)

    desktop_files = existing_desktop_files()
    config_path = config_file_for(launcher_inst)
    config_changed = True
    try:
        with open(config_path, encoding="utf-8") as fh:
            old = json.load(fh)
        old_list = old.get("launcher-list", {}).get("value", [])
        config_changed = old_list != desktop_files
    except (OSError, ValueError, AttributeError):
        pass

    if new_layout == current and not config_changed:
        print("UNCHANGED")
        return

    try:
        write_launcher_config(launcher_inst, desktop_files)
    except OSError as exc:
        print(f"FAILED: launcher config not written: {exc}")
        sys.exit(1)

    if new_layout == current:
        print(f"OK: launcher config refreshed ({len(desktop_files)} apps)")
        return

    new_value = str(new_layout).replace('"', "'")
    result = subprocess.run(["gsettings", "set", "org.cinnamon", "enabled-applets", new_value])
    if result.returncode != 0:
        print("FAILED")
        sys.exit(1)
    print(f"OK: wrote launcher config with {len(desktop_files)} apps")


if __name__ == "__main__":
    main()