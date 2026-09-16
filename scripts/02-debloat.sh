#!/usr/bin/env bash
# =======================================================
# 02 Debloat — lean Cinnamon without the cruft
# -------------------------------------------------------
# Merges the old cinnamonDebloat.sh. Cinnamon's default
# task is leaner than KDE but still pulls in Warpinator
# (open network discovery port), HexChat (IRC), a handful
# of redundant GNOME apps, bundled games, and Tracker
# (GNOME's file indexer). Every removal is a dpkg purge
# of what's actually installed — nothing destructive to
# your files, no Cinnamon effects disabled.
# =======================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_not_root
log_head "02 Debloat"

if ! command_exists apt-get; then
    log_err "apt-get not found — need a Debian/Devuan APT system."
    exit 1
fi

apt_update

# ---------------------------------------------------------------------------
# 1. Warpinator — always-listening LAN discovery port; unnecessary attack
#    surface on a laptop that roams onto untrusted WiFi.
# ---------------------------------------------------------------------------
purge_if_installed "Warpinator" warpinator

# ---------------------------------------------------------------------------
# 2. HexChat — IRC client that nobody on a Mint-style desktop touches.
# ---------------------------------------------------------------------------
purge_if_installed "HexChat" hexchat hexchat-common hexchat-python

# ---------------------------------------------------------------------------
# 3. GNOME extras — weather/maps/todo/contacts/clocks apps that duplicate
#    what a browser or phone already does, plus Pix (a second image viewer).
# ---------------------------------------------------------------------------
purge_if_installed "GNOME extras" \
    gnome-weather gnome-maps gnome-todo gnome-contacts gnome-clocks pix

# ---------------------------------------------------------------------------
# 4. Simple games — aisleriot/mines/sudoku bundled as Recommends. Lean
#    approach: remove them. If you actually play them, re-install later.
# ---------------------------------------------------------------------------
purge_if_installed "Simple games" aisleriot gnome-mines gnome-sudoku

# ---------------------------------------------------------------------------
# 5. Cleanup orphaned dependencies
# ---------------------------------------------------------------------------
log_info "Running apt-get autoremove --purge..."
sudo apt-get autoremove --purge -y || log_warn "autoremove reported issues (non-fatal)."
log_info "Running apt-get clean..."
sudo apt-get clean || true
log_ok "Cleanup done."

# ---------------------------------------------------------------------------
# 6. Disable Tracker file indexing (GNOME's Baloo-equivalent). Nemo pulls
#    it in for filename/content search; it's a real idle-CPU/disk cost on
#    a minimal install. Disables + masks it rather than hard-purging the
#    packages, since gvfs/file-roller share the same libtracker dependency.
#    The dconf key works identically under OpenRC because Tracker is a
#    session/dbus service, not an init-managed one.
# ---------------------------------------------------------------------------
if command_exists tracker3; then
    run_as_user tracker3 reset --hard >/dev/null 2>&1 || true
fi
if user_gsettings set org.freedesktop.Tracker3.Miner.Files crawling-interval -2 2>/dev/null; then
    log_ok "Tracker crawling disabled (crawling-interval=-2)."
    # Under any init, clearing the recursive-index key ensures nothing is
    # crawled even if something restarts tracker outside our control.
    user_gsettings set org.freedesktop.Tracker3.Miner.Files \
        index-recursive-directories "[]" 2>/dev/null || true
else
    log_warn "Tracker schema not present — nothing to disable."
fi
# Belt-and-suspenders: mask the Tracker systemd units so systemd users can't
# accidentally restart them.  Harmless if systemd isn't the init (no
# ~/.config/systemd/user/ to touch), but useful on Debian boxes where
# cinnamon pulls in systemd.
if [ "$(init_system)" = "systemd" ]; then
    mkdir -p "$HOME/.config/systemd/user" 2>/dev/null || true
    for svc in tracker-miner-fs-3 tracker-extract-3 tracker-writeback-3 tracker-xdg-portal-3; do
        run_as_user ln -sf /dev/null "$HOME/.config/systemd/user/${svc}.service" 2>/dev/null || true
    done
fi
log_ok "Tracker indexing disabled."

# ---------------------------------------------------------------------------
# 7. Trim Mint autostart launchers that happen to be present (Devuan ships
#    clean by default, but other packages sometimes drop one).
# ---------------------------------------------------------------------------
mkdir -p "$HOME/.config/autostart"
TRIMMED=0
for NAME in mintupdate mintreport mintwelcome warpinator-autostart sticky; do
    if [ -f "/etc/xdg/autostart/$NAME.desktop" ]; then
        printf '[Desktop Entry]\nType=Application\nHidden=true\n' > "$HOME/.config/autostart/$NAME.desktop"
        log_ok "Disabled autostart: $NAME"
        TRIMMED=1
    fi
done
[ "$TRIMMED" -eq 0 ] && log_ok "No Mint/optional autostart launchers present — nothing to trim."

echo -e "${GREEN}02 Debloat complete.${NC}"
