#!/usr/bin/env bash
# =======================================================
# 01 System Setup — the run-this-first step
# -------------------------------------------------------
# Merges the old systemUpdate.sh / addUserToGroups.sh /
# ssdTrim.sh / timeshiftSetup.sh into one deterministic,
# unattended-first system baseline:
#   1. apt update + full-upgrade + autoremove
#   2. add the calling user to input/video/render
#   3. weekly fstrim via cron (safe no-op on non-SSDs)
#   4. Timeshift (installed only; schedule via its wizard)
#
# Skips the apt refresh if DEBSWAY_SKIP_APT_UPDATE=1 (set
# automatically after the first successful update in a run).
# =======================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_not_root
log_head "01 System Setup"

# ---------------------------------------------------------------------------
# 1. Update everything before anything else
# ---------------------------------------------------------------------------
log_info "Refreshing package lists and applying all available updates..."
apt_update

UPGRADABLE=$(apt list --upgradable 2>/dev/null | grep -c '\[upgradable' || true)
if [ "${UPGRADABLE:-0}" -eq 0 ]; then
    log_ok "Already up to date — nothing to install."
else
    log_info "${UPGRADABLE} package(s) can be upgraded."
    sudo apt-get full-upgrade -y && log_ok "System updated." \
        || log_warn "full-upgrade reported issues — check the output above."
fi

log_info "Removing now-unneeded packages (apt autoremove)..."
sudo apt-get autoremove --purge -y >/dev/null 2>&1 && log_ok "Orphaned packages cleaned up."
log_warn "If the kernel or a core library was updated, reboot before continuing."

# ---------------------------------------------------------------------------
# 2. Add the real user to input/video/render (GPU accel + touchpad tools)
# ---------------------------------------------------------------------------
if [ -z "$ACTUAL_USER" ] || [ "$ACTUAL_USER" = "root" ]; then
    log_err "Could not determine a non-root user to modify."
else
    log_info "Adding ${ACTUAL_USER} to input, video, render groups..."
    for grp in input video render; do
        if ! getent group "$grp" >/dev/null 2>&1; then
            log_warn "Group '$grp' does not exist — skipping."
            continue
        fi
        if id -nG "$ACTUAL_USER" 2>/dev/null | tr ' ' '\n' | grep -qx "$grp"; then
            log_ok "Already in '$grp'."
            continue
        fi
        if sudo usermod -aG "$grp" "$ACTUAL_USER"; then
            log_ok "Added to '$grp'."
        else
            log_err "Failed to add to '$grp'."
        fi
    done
    log_warn "Log out and back in for new group membership to take effect."
fi

# ---------------------------------------------------------------------------
# 3. SSD TRIM — weekly fstrim via cron (init-agnostic, unlike fstrim.timer)
# ---------------------------------------------------------------------------
install_pkgs "util-linux (provides fstrim)" util-linux
install_pkgs "cron" cron

log_info "Running 'fstrim -av' once to confirm it works..."
if sudo fstrim -av; then
    log_ok "fstrim ran successfully."
else
    log_warn "fstrim reported an issue (harmless if no TRIM-capable filesystem is mounted)."
fi

MARKER="# devuan-cinnamon-setup: weekly fstrim"
NEW_CRON=$(mktemp)
( sudo crontab -l 2>/dev/null | grep -vF "fstrim -av" | grep -vF "$MARKER" ) > "$NEW_CRON" || true
{
    echo "$MARKER"
    echo "30 3 * * 0 /sbin/fstrim -av >/var/log/fstrim.log 2>&1"
} >> "$NEW_CRON"
if sudo crontab "$NEW_CRON"; then
    log_ok "Weekly fstrim cron job installed (root crontab, Sundays 03:30)."
else
    log_warn "Could not install the fstrim cron job — add manually: sudo crontab -e"
    echo "  30 3 * * 0 /sbin/fstrim -av >/var/log/fstrim.log 2>&1"
fi
rm -f "$NEW_CRON"
service_enable_now cron
log_ok "cron enabled and started via $(init_system)."

# ---------------------------------------------------------------------------
# 4. Timeshift — Mint's snapshot/restore safety net (works on cron, no systemd)
# ---------------------------------------------------------------------------
install_pkgs "Timeshift" timeshift

if is_installed timeshift; then
    log_ok "Timeshift installed."
    log_warn "One-time setup: run 'sudo timeshift-launcher' to choose rsync vs BTRFS mode,"
    log_warn "the snapshot location, and a schedule — deliberately left for you, not guessed."
else
    log_err "Timeshift installation failed."
fi

echo -e "${GREEN}01 System Setup complete.${NC}"