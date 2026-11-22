#!/usr/bin/env bash
# =======================================================
# 09 Update System - notifier, themed update GUI, and the Devuan Menu
# -------------------------------------------------------
# Merges the old updateNotifier.sh / updateGui.sh / ohmydebnMenu.sh:
#   * a cron-backed checker (runs 09:00 + 18:00, init-agnostic) that pops
#     a notification with a clickable "Update now" action
#   * a Graphite Amber themed GTK3 window with an embedded VTE terminal that
#     runs the update for you (the pretty layer never performs the update
#     itself - it spawns real apt commands in a real pty)
#   * devuan-menu - a searchable, theme-aware power-user launcher (Apps /
#     AI / Terminals / Editors / Update / System) bound to Super+M
# No systemd timers anywhere - cron + notify-send only.
# =======================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_not_root
log_head "09 Update System"

BIN_DIR="$HOME/.local/bin"
TOOL_DIR="$HOME/.local/share/devuan-cinnamon/bin"
MENU_TOOL_DIR="$HOME/.local/share/devuan-cinnamon/menu"
mkdir -p "$BIN_DIR" "$TOOL_DIR" "$MENU_TOOL_DIR"

apt_update
install_pkgs "Update GUI dependencies" python3-gi gir1.2-gtk-3.0 gir1.2-vte-2.91 libnotify-bin cron synaptic

# ---------------------------------------------------------------------------
# 1. The GTK update window
# ---------------------------------------------------------------------------
GUI="$TOOL_DIR/devuan-update-gui.py"
cat > "$GUI" << 'UPYEOF'
#!/usr/bin/env python3
"""devuan-update-gui - themed GTK window that runs system updates in a VTE.

Dresses in the live palette from ~/.config/devuan-cinnamon/current/picker.colors
(bg0/bg1/bg3/fg0 - written by 04-theme.sh), falling back to Graphite Amber
defaults if that file is missing or unreadable. Theme rules via CSS.
"""
import os
import subprocess
import sys

import gi

gi.require_version("Gtk", "3.0")
try:
    gi.require_version("Vte", "2.91")
    from gi.repository import Vte
    VTE_AVAILABLE = True
except (ValueError, ImportError):
    Vte = None
    VTE_AVAILABLE = False
from gi.repository import Gdk, GLib, Gtk

PICKER = os.path.expanduser("~/.config/devuan-cinnamon/current/picker.colors")
DEFAULTS = {"bg0": "#16181DF2", "bg1": "#16181D", "bg3": "#E8A33DF2", "fg0": "#D8D3C8"}


def theme_colors():
    colors = dict(DEFAULTS)
    try:
        with open(PICKER, "r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" in line:
                    key, value = line.split("=", 1)
                    if key in colors and value:
                        colors[key] = value
    except OSError:
        pass
    return colors


class UpdateWindow(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app)
        self.set_title("Devuan Update")
        self.set_default_size(720, 520)
        self.colors = theme_colors()
        self.busy = False

        self.setup_css()

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        outer.set_margin_top(14)
        outer.set_margin_bottom(14)
        outer.set_margin_left(16)
        outer.set_margin_right(16)
        self.add(outer)

        title = Gtk.Label(label="System Update")
        title.get_style_context().add_class("title")
        outer.pack_start(title, False, False, 0)

        sub = Gtk.Label(label="Updates run in the terminal below. Your password may be asked for sudo.")
        sub.get_style_context().add_class("subtitle")
        outer.pack_start(sub, False, False, 0)

        if VTE_AVAILABLE:
            self.term = Vte.Terminal()
            self.term.set_size(80, 24)
            fg, bg = self.parse("fg0"), self.parse("bg1")
            self.term.set_colors(fg, bg, [])
            scroller = Gtk.ScrolledWindow()
            scroller.set_hexpand(True)
            scroller.set_vexpand(True)
            scroller.add(self.term)
            outer.pack_start(scroller, True, True, 0)
        else:
            self.term = None
            warn = Gtk.Label(label="VTE terminal widget is missing (gir1.2-vte-2.91 not installed).\nUpdates will open in a separate terminal window instead.")
            warn.get_style_context().add_class("subtitle")
            outer.pack_start(warn, False, False, 0)

        btnrow = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        btnrow.set_halign(Gtk.Align.END)
        outer.pack_end(btnrow, False, False, 0)

        check = Gtk.Button(label="Check only")
        check.connect("clicked", self.on_check)
        self.check_btn = check
        btnrow.pack_start(check, False, False, 0)

        self.update_btn = Gtk.Button(label="Update now")
        self.update_btn.connect("clicked", self.on_update)
        btnrow.pack_start(self.update_btn, False, False, 0)

        close = Gtk.Button(label="Close")
        close.connect("clicked", lambda *_: self.close())
        btnrow.pack_start(close, False, False, 0)

        status_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        outer.pack_start(status_row, False, False, 0)
        self.status = Gtk.Label(label="Ready")
        self.status.get_style_context().add_class("status")
        status_row.pack_start(self.status, False, False, 0)
        self.spinner = Gtk.Spinner()
        self.spinner.set_active(False)
        status_row.pack_start(self.spinner, False, False, 0)

        self.update_btn.grab_focus()

    def parse(self, key):
        v = self.colors.get(key, DEFAULTS.get(key, "#000000"))
        v = v.strip()
        if len(v) == 9:  # 8-digit ARGB from the F2 suffix
            v = v[:7]
        r, g, b = int(v[1:3], 16), int(v[3:5], 16), int(v[5:7], 16)
        return Gdk.RGBA(red=r / 255.0, green=g / 255.0, blue=b / 255.0, alpha=1.0)

    def setup_css(self):
        css = b"""
            .title { font-size: 20px; font-weight: bold; color: %s; }
            .subtitle { color: %s; }
            .status { color: %s; }
        """ % (self.colors["fg0"].encode(), self.colors["fg0"].encode(), self.colors["bg3"].encode())
        provider = Gtk.CssProvider()
        provider.load_from_data(css)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

    def set_busy(self, busy):
        self.busy = busy
        self.spinner.set_active(busy)
        self.update_btn.set_sensitive(not busy)
        if getattr(self, "check_btn", None) is not None:
            self.check_btn.set_sensitive(not busy)

    def spawn(self, argv, on_exit=None):
        """Run a command in the embedded VTE; call on_exit(exit_status)
        when it finishes (or just daemonize if no VTE / no callback)."""
        if self.term is not None:
            def _handler(_term, status, cb=on_exit):
                if cb:
                    cb(status)
            try:
                pid = self.term.spawn_sync(
                    Vte.PtyFlags.DEFAULT, None, argv, None,
                    GLib.SpawnFlags.SEARCH_PATH, None, None, None,
                )[0]
                if on_exit is not None:
                    self.term.connect("child-exited", _handler)
            except Exception:
                if on_exit:
                    on_exit(-1)
        else:
            subprocess.Popen(argv)
            if on_exit:
                on_exit(0)

    def on_check(self, _btn):
        self.set_busy(True)
        self.status.set_text("Checking for updates...")
        def _done(_code):
            self.set_busy(False)
            self.status.set_text("Check complete. Lines ending in 'upgradable' are pending updates.")
        self.spawn(["bash", "-lc", "sudo apt-get update; apt list --upgradable"], on_exit=_done)

    def on_update(self, _btn):
        if self.busy:
            return
        self.set_busy(True)
        self.status.set_text("Updating... do not close this window mid-update.")
        if self.term is None:
            def _empty(_code):
                self.set_busy(False)
                self.status.set_text("Update running in the separate terminal window.")
            self.spawn(["x-terminal-emulator"], on_exit=_empty)
        else:
            def _finished(_code):
                self.set_busy(False)
                self.status.set_text("Update finished.")
            self.spawn([
                "bash", "-lc",
                "sudo apt-get update && sudo apt-get full-upgrade; "
                "CODE=$?; if [ $CODE -eq 0 ]; then "
                "notify-send -i software-update-ok 'Updates complete' 'Your system is up to date.'; "
                "else notify-send -i software-update-error 'Update had errors' 'See the terminal output for what failed.'; fi; "
                "exit $CODE",
            ], on_exit=_finished)


def main():
    app = Gtk.Application()
    app.connect("activate", lambda a: UpdateWindow(a).show_all())
    app.run(None)


if __name__ == "__main__":
    if not VTE_AVAILABLE and not os.environ.get("DISPLAY"):
        # Headless: just run the update in the foreground terminal.
        sys.exit(subprocess.call(["sudo", "apt-get", "full-upgrade"]))
    main()
UPYEOF
chmod +x "$GUI"

LAUNCHER="$BIN_DIR/devuan-update-gui"
cat > "$LAUNCHER" << EOF
#!/usr/bin/env bash
exec python3 "$GUI"
EOF
chmod +x "$LAUNCHER"
log_ok "Update window + launcher installed."

# ---------------------------------------------------------------------------
# 2. The cron checker - notification with a clickable "Update now" action
# ---------------------------------------------------------------------------
CHECKER="$BIN_DIR/devuan-update-check.sh"
cat > "$CHECKER" << 'EOF'
#!/usr/bin/env bash
# Checks for upgradable packages; pops a desktop notification with a
# clickable "Update now" action that opens devuan-update-gui. Run from cron.
#
# Cron has no X/DBus env by default, so we borrow DISPLAY +
# DBUS_SESSION_BUS_ADDRESS from a running cinnamon-session (or any X11 app)
# owned by the invoking user. Falls back to DISPLAY=:0 as a last resort.
set -uo pipefail

for candidate in "$USER" "${SUDO_USER:-}"; do
    [ -n "$candidate" ] || continue
    PID=$(pgrep -u "$candidate" cinnamon-session 2>/dev/null | head -n1)
    [ -n "$PID" ] || PID=$(pgrep -u "$candidate" Xorg 2>/dev/null | head -n1)
    [ -n "$PID" ] || continue
    if [ -r "/proc/$PID/environ" ]; then
        export DISPLAY="$(tr '\0' '\n' < "/proc/$PID/environ" | sed -n 's/^DISPLAY=//p' | head -n1)"
        export DBUS_SESSION_BUS_ADDRESS="$(tr '\0' '\n' < "/proc/$PID/environ" | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p' | head -n1)"
        [ -n "${DISPLAY:-}" ] && break
    fi
done
export DISPLAY="${DISPLAY:-:0}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}"

# Best-effort refresh (works if the user has passwordless sudo; otherwise the
# notifier simply reports on the last cached list).
sudo -n apt-get update -qq >/dev/null 2>&1 || true

COUNT=$(apt list --upgradable 2>/dev/null | grep -c '\[upgradable' || true)

if [ "${COUNT:-0}" -gt 0 ]; then
    ACTION=$(notify-send \
        -i software-update-available \
        "Updates available" \
        "${COUNT} package(s) can be upgraded." \
        --app-name="Devuan Update Notifier" \
        --action="update=Update now" 2>/dev/null)
    if [ "$ACTION" = "update" ]; then
        DISPLAY="$DISPLAY" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" devuan-update-gui &
    fi
fi
EOF
chmod +x "$CHECKER"

CRON_MARKER="# devuan-cinnamon-setup: update notifier"
NEW_CRON=$(mktemp)
( crontab -l 2>/dev/null | grep -vF "$CHECKER" | grep -vF "$CRON_MARKER" ) > "$NEW_CRON" || true
{
    echo "$CRON_MARKER"
    echo "0 9,18 * * * $CHECKER >/dev/null 2>&1"
} >> "$NEW_CRON"
if crontab "$NEW_CRON"; then
    log_ok "Cron job installed (runs at 09:00 and 18:00 daily)."
else
    log_err "Failed to install the cron job - add manually: crontab -e"
    echo "  0 9,18 * * * $CHECKER"
fi
rm -f "$NEW_CRON"
service_enable_now cron
log_ok "cron enabled and started via $(init_system)."

log_info "Running one check now to confirm it works..."
"$CHECKER"
log_ok "Check ran - if updates are available you should see a notification."

# ---------------------------------------------------------------------------
# 3. devuan-menu - themed power-user launcher, bound to Super+M
# ---------------------------------------------------------------------------
install_pkgs "Menu dependencies" python3-gi gir1.2-gtk-3.0
cp "$SCRIPT_DIR/../config/menu/devuan-menu.py" "$MENU_TOOL_DIR/devuan-menu.py"
chmod +x "$MENU_TOOL_DIR/devuan-menu.py"

cat > "$BIN_DIR/devuan-menu" << EOF
#!/usr/bin/env bash
exec python3 "$MENU_TOOL_DIR/devuan-menu.py" "\$@"
EOF
chmod +x "$BIN_DIR/devuan-menu"

mkdir -p "$HOME/.local/share/applications"
cat > "$HOME/.local/share/applications/devuan-menu.desktop" << EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=Devuan Menu
Comment=Power-user launcher (Apps, AI, Update, System)
Exec=$BIN_DIR/devuan-menu
Icon=utilities-terminal
Terminal=false
Categories=Utility;System;
EOF
log_ok "Devuan Menu installed."

if command_exists gsettings && command_exists python3 \
    && cinnamon_custom_binding "Devuan Menu" "$BIN_DIR/devuan-menu" "<Super>m"; then
    log_ok "Super+M now opens the Devuan Menu."
else
    log_warn "Could not bind Super+M - run devuan-menu manually, or bind it in Cinnamon Settings > Keyboard."
fi

echo -e "${GREEN}09 Update System complete.${NC}"
log_warn "Press Super+M (or run 'devuan-menu') to use it. The update notifier never applies updates automatically."
log_info "The cron checker auto-detects your session's DISPLAY/DBus at run time - no hard-coded :0 needed."

# ---------------------------------------------------------------------------
# 4. First-run welcome wizard - one-time, autostarted after a fresh install
# ---------------------------------------------------------------------------
if [ -f "$SCRIPT_DIR/../config/menu/devuan-first-run" ]; then
    install -m 755 "$SCRIPT_DIR/../config/menu/devuan-first-run" "$BIN_DIR/devuan-first-run"
    mkdir -p "$HOME/.config/autostart"
    cat > "$HOME/.config/autostart/devuan-first-run.desktop" << EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=Devuan First Run
Comment=Welcome wizard - first update + Timeshift, once per user
Exec=$BIN_DIR/devuan-first-run
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=5
EOF
    log_ok "First-run wizard installed (runs once on next login; skip anytime by answering N)."
    log_info "Re-run it whenever you like: $BIN_DIR/devuan-first-run  (delete $HOME/.config/devuan-cinnamon/first-run-complete to re-arm)."
else
    log_warn "config/menu/devuan-first-run not found - skipping first-run wizard."
fi