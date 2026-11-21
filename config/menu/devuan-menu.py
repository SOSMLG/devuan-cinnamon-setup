#!/usr/bin/env python3
"""devuan-menu — a trimmed, fully self-contained power-user menu.

Inspired by ohmydebn's GTK picker (https://github.com/dougburks/ohmydebn,
MIT licensed): a themed, search-as-you-type launcher for the handful of
things worth having hotkeyed. Where ohmydebn ships a ~2000-line
menu/picker/tree trio wired to a 170-script install/remove catalog, this is
a single file: curated categories + commands, a type-ahead search, and the
system/update/AI actions that actually get used.

Styling follows the ohmydebn picker-colors key format
(bg0/bg1/bg3/fg0) from ~/.config/devuan-cinnamon/current/picker.colors,
written by 04-theme.sh. Falls back to Graphite Amber defaults.

Launch from the command line (`devuan-menu`) or a Cinnamon hotkey.
"""

import os
import shlex
import subprocess
import sys

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Pango", "1.0")
from gi.repository import Gdk, Gtk, Pango

PICKER = os.path.expanduser("~/.config/devuan-cinnamon/current/picker.colors")
DEFAULTS = {"bg0": "#16181DF2", "bg1": "#16181D", "bg3": "#E8A33DF2", "fg0": "#D8D3C8"}

CATEGORIES = {
    "Apps": [
        ("Nemo Files", "nemo"),
        ("Firefox", "firefox"),
        ("VLC", "vlc"),
        ("GParted", "gparted"),
        ("KeePassXC", "keepassxc"),
        ("Timeshift", "timeshift-launcher"),
        ("OpenCode", "opencode"),
        ("Folder Sync (Unison)", "unison-gtk"),
    ],
    "AI": [
        ("OpenCode Agent", "opencode"),
        ("OpenCode in current dir", "opencode ."),
    ],
    "Terminals": [
        ("gnome-terminal", "gnome-terminal"),
        ("btop", "btop"),
        ("htop", "htop"),
        ("Root shell (root)", "pkexec x-terminal-emulator -- bash -il"),
    ],
    "Editors": [
        ("Xed", "xed"),
        ("Pluma", "pluma"),
        ("VSCodium", "codium"),
    ],
    "Browsers": [
        ("Firefox", "firefox"),
        ("Vivaldi", "vivaldi"),
    ],
    "Update": [
        ("Open Update Window", "devuan-update-gui"),
        ("Force update check", "sh -c '~/.local/bin/devuan-update-check.sh; echo; read -p press-enter'"),
    ],
    "System": [
        ("Cinnamon Settings", "cinnamon-settings"),
        ("Lock Screen", "cinnamon-screensaver-command --lock"),
        ("Suspend", "sudo pm-suspend"),
        ("Restart", "sudo shutdown -r now"),
        ("Shut Down", "sudo shutdown -h now"),
        ("Log Out", "cinnamon-session-quit --logout --no-prompt"),
        ("Screen Saver settings", "cinnamon-settings screensaver"),
    ],
}

# Commands whose substitutions would otherwise be auto-completed poorly
# without a terminal — launch those through a terminal window.
TERMINAL_WRAPPED = ("btop", "htop", "opencode", "sh -c", "sudo -i")


def terminal_wrap(cmd):
    """Wrap a command in the default terminal so the window stays open after
    the app exits (x-terminal-emulator is the Cinnamon default)."""
    inner = shlex.split(cmd)
    return [
        "x-terminal-emulator", "--", "bash", "-c",
        '"$@" ; exec bash', "devuan-menu", *inner,
    ]


def theme_colors():
    colors = dict(DEFAULTS)
    try:
        with open(PICKER, "r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if line.startswith(("bg0=", "bg1=", "bg3=", "fg0=")):
                    key, value = line.split("=", 1)
                    if value:
                        colors[key] = value
    except OSError:
        pass
    return colors


def rgba(value, alpha=1.0):
    value = value.strip()
    if len(value) == 9:
        value = value[:7]
    if not (value.startswith("#") and len(value) == 7):
        value = "#16181D"
    return Gdk.RGBA(
        red=int(value[1:3], 16) / 255.0,
        green=int(value[3:5], 16) / 255.0,
        blue=int(value[5:7], 16) / 255.0,
        alpha=alpha,
    )


ALL_ITEMS = [(cat, name, cmd) for cat, items in CATEGORIES.items() for name, cmd in items]


class Menu(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app)
        self.set_title("devuan-menu")
        self.set_default_size(520, 420)
        self.colors = theme_colors()
        self.setup_css()

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        vbox.set_margin_top(12)
        vbox.set_margin_bottom(12)
        vbox.set_margin_left(12)
        vbox.set_margin_right(12)
        self.add(vbox)

        hint = Gtk.Label(label="Type to filter — Enter/click to run")
        hint.get_style_context().add_class("hint")
        vbox.pack_start(hint, False, False, 0)

        self.search = Gtk.SearchEntry()
        self.search.set_placeholder_text("search apps, system, update…")
        self.search.connect("search-changed", self.on_search)
        vbox.pack_start(self.search, False, False, 0)

        self.store = Gtk.ListStore(str, str, str)  # category, name, command
        for cat, name, cmd in ALL_ITEMS:
            self.store.append([cat, name, cmd])

        self.view = Gtk.TreeView(model=self.store)
        self.view.set_headers_visible(True)
        self.view.set_activate_on_single_click(True)
        self.view.connect("row-activated", self.on_activate)
        col_cat = Gtk.TreeViewColumn("Category", Gtk.CellRendererText(), text=0)
        col_name = Gtk.TreeViewColumn("Action", Gtk.CellRendererText(), text=1)
        col_name.set_expand(True)
        self.view.append_column(col_cat)
        self.view.append_column(col_name)

        scrolled = Gtk.ScrolledWindow()
        scrolled.add(self.view)
        scrolled.set_vexpand(True)
        vbox.pack_start(scrolled, True, True, 0)

        self.status = Gtk.Label(label="")
        self.status.get_style_context().add_class("hint")
        vbox.pack_start(self.status, False, False, 0)

        self.search.grab_focus()

    def setup_css(self):
        css = (
            "window {{ background-color: {bg0}; }}\n"
            "treeview {{ background-color: {bg1}; color: {fg0}; }}\n"
            "treeview:selected {{ background-color: {bg3}; color: {bg1}; }}\n"
            ".hint {{ color: {fg0}; font-size: 11px; }}\n"
        ).format(**self.colors).encode("utf-8")
        provider = Gtk.CssProvider()
        provider.load_from_data(css)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

    def on_search(self, _entry):
        needle = self.search.get_text().strip().lower()
        self.store.clear()
        for cat, name, cmd in ALL_ITEMS:
            if not needle or needle in (cat + " " + name + " " + cmd).lower() or needle in name.lower() or needle in cmd.lower():
                self.store.append([cat, name, cmd])
        self.status.set_text("" if needle else "Categories: Apps · AI · Terminals · Editors · Browsers · Update · System")

    def on_activate(self, _view, path, _col):
        it = self.store.get_iter(path)
        _, name, cmd = (self.store.get_value(it, i) for i in (0, 1, 2))
        self.close()
        run_command(name, cmd)


def run_command(name, cmd):
    argv = cmd.split()
    base = argv[0]
    if any(tok in cmd for tok in TERMINAL_WRAPPED) and base not in ("sudo", "pkexec"):
        argv = terminal_wrap(cmd)
    try:
        if base in ("sudo", "pkexec"):
            subprocess.Popen(argv)
        else:
            subprocess.Popen(argv, stdin=subprocess.DEVNULL)
    except FileNotFoundError:
        subprocess.Popen(["x-terminal-emulator", "-e", cmd])
    except Exception as exc:  # noqa: BLE001 — best-effort launcher
        print(f"devuan-menu: could not launch {name}: {exc}", file=sys.stderr)
        raise SystemExit(1)


def main():
    app = Gtk.Application()
    app.connect("activate", lambda a: Menu(a).show_all())
    app.run(None)


if __name__ == "__main__":
    main()