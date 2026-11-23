#!/usr/bin/env bash
# =======================================================
# Verify Setup — end-state audit for devuan-cinnamon-setup
# -------------------------------------------------------
# One-pass check of the toolkit's expected end state:
# group membership, key packages, fonts, Firefox user.js,
# enabled services, the Cinnamon spices this kit installs,
# and the persistent palette marker. Designed to be run from
# install.sh --verify after a run, or standalone at any time.
#
# Prints PASS/FAIL/WARN lines and exits non-zero if any
# critical check failed, so it can gate CI/ISO validation.
# =======================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

PASS=0; FAIL=0; WARN=0

report() {  # report <name> <status> <detail>
    case "$2" in
        ok)
            printf '  PASS  %-48s %s\n' "$1" "${3:-}"
            PASS=$((PASS + 1))
            ;;
        fail)
            printf '  FAIL  %-48s %s\n' "$1" "${3:-}"
            FAIL=$((FAIL + 1))
            ;;
        warn)
            printf '  WARN  %-48s %s\n' "$1" "${3:-}"
            WARN=$((WARN + 1))
            ;;
    esac
}

pkg() {  # pkg <name> [critical|optional]
    local name="$1" level="${2:-critical}"
    local state detail
    if is_installed "$name"; then
        state="ok"; detail="installed"
    elif [ "$level" = "optional" ]; then
        state="warn"; detail="not installed (optional — OK to skip)"
    else
        state="fail"; detail="missing — re-run the relevant script"
    fi
    report "$name" "$state" "$detail"
}

pkg_glob() {
    local name="$1" level="${2:-critical}"
    local state detail
    if dpkg-query -W -f='${Status}' "$name" 2>/dev/null | grep -q "install ok installed" \
        || dpkg-query -l "${name}*" 2>/dev/null | grep -q '^ii'; then
        state="ok"; detail="installed"
    elif [ "$level" = "optional" ]; then
        state="warn"; detail="not installed (optional — OK to skip)"
    else
        state="fail"; detail="missing — re-run the relevant script"
    fi
    report "$name*" "$state" "$detail"
}

service_state() {
    local svc="$1" procname="$2" level="${3:-fail}"
    local enabled="" running=""
    case "$(init_system)" in
        systemd)
            systemctl is-enabled "$svc" >/dev/null 2>&1 && enabled="systemd"
            [ -z "$enabled" ] && systemctl is-enabled "${svc}.service" >/dev/null 2>&1 && enabled="systemd"
            ;;
        openrc)
            if command_exists rc-update && rc-update show 2>/dev/null | awk -v s="$svc" '$1==s{found=1} END{exit !found}'; then
                enabled="openrc"
            fi
            ;;
        sysvinit)
            if [ -f "/etc/init.d/$svc" ] && ls /etc/rc[0-9S]*.d/S*"$svc" >/dev/null 2>&1; then
                enabled="sysvinit"
            fi
            ;;
    esac
    pgrep -x "$procname" >/dev/null 2>&1 && running="yes"

    if [ -n "$running" ]; then
        report "$svc (service)" ok "${enabled:-running, not enabled}"
    elif [ "$level" = "optional" ]; then
        report "$svc (service)" warn "not running"
    else
        report "$svc (service)" fail "not running"
    fi
}

dir_exists() {
    local name="$1" path="$2" level="${3:-warn}"
    if [ -e "$path" ]; then
        report "$name" ok
    elif [ "$level" = "warn" ]; then
        report "$name" warn "not found — re-run the relevant script (or skip)"
    else
        report "$name" fail "not found — re-run the relevant script"
    fi
}

log_head "Setup verification"

echo -e "  (user: ${CYAN}${ACTUAL_USER}${NC})\n"

# --- 1. Group membership ------------------------------------------------
for g in input video render; do
    if id -nG "$ACTUAL_USER" 2>/dev/null | tr ' ' '\n' | grep -qx "$g"; then
        report "group: $g" ok
    else
        report "group: $g" fail "user not in $g — re-run 01-systemSetup.sh or: sudo usermod -aG $g $ACTUAL_USER"
    fi
done

# --- 2. Package baseline (default-Y/lean set) ----------------------------
pkg vlc
pkg tlp
pkg firefox-esr
pkg ffmpeg
pkg_glob libavcodec-extra
pkg fonts-noto-core optional
pkg fonts-noto-color-emoji optional
pkg fastfetch
pkg flatpak
pkg timeshift
pkg fwupd optional
pkg btop
pkg eza
pkg bat
pkg keepassxc optional
pkg cron

# --- 2b. Dev tools + AI agents (optional) --------------------------------
pkg codium optional
# opencode is installed by 10-aiAgents.sh to ~/.opencode/bin (not a .deb),
# so check PATH rather than dpkg.
if command_exists opencode; then
    report "opencode" ok "on PATH"
else
    report "opencode" warn "not on PATH — re-run 10-aiAgents.sh"
fi
pkg build-essential optional
pkg synaptic optional
pkg gufw optional
pkg qbittorrent optional

# --- 3. Fonts -------------------------------------------------------------
# NOTE: no `grep -q` on a pipe under set -o pipefail — grep -q exits early,
# SIGPIPEs the producer, and pipefail then reports "failure" even on a match.
NBF_COUNT=$(fc-list 2>/dev/null | grep -c "JetBrainsMono Nerd Font")
if [ "${NBF_COUNT:-0}" -gt 0 ]; then
    report "JetBrainsMono Nerd Font" ok
else
    report "JetBrainsMono Nerd Font" fail "not found — re-run 06-cliStack.sh"
fi
INTER_COUNT=$(fc-list 2>/dev/null | grep -ciE ': Inter([^a-z-]|$)')
if [ "${INTER_COUNT:-0}" -gt 0 ]; then
    report "Inter font" ok
else
    report "Inter font" warn "not found — re-run 06-cliStack.sh"
fi
dir_exists "fontconfig defaults (fonts.conf)" "$HOME/.config/fontconfig/fonts.conf" warn

# --- 4. Firefox hardening -------------------------------------------------
if [ -f "$HOME/.local/share/butterscripts/firefox/user.js" ] \
    || grep -rlsq "user_pref" "$HOME/.mozilla/firefox" 2>/dev/null; then
    report "Firefox hardened user.js" ok
else
    report "Firefox hardened user.js" warn "no user.js found (re-run 08-firefox.sh or skip)"
fi

# --- 5. Theme / palette ---------------------------------------------------
# The palette marker 04 writes persists the active palette + picker.colors.
if [ -f "$HOME/.config/devuan-cinnamon/current/picker.colors" ]; then
    report "Palette marker (picker.colors)" ok
else
    report "Palette marker (picker.colors)" warn "not applied — re-run 04-theme.sh in a Cinnamon session"
fi

# --- 6. Cinnamon spices this kit installs (05-cinnamonSetup.sh) ----------
EXT_UUIDS=(cinnamon-maximus@fmete BlurCinnamon@klangman gTile@shuairan \
    NewWindowSettings@klangman RearrangeWorkspaces@klangman \
    focus-new-window@mdpenguin dim-inactive-windows@jark \
    CinnamonBurnMyWindows@klangman)
APPLET_UUIDS=(color-picker@fmete weather@mockturtl SpicesUpdate@claudiux)

for uuid in "${EXT_UUIDS[@]}"; do
    if [ -d "$HOME/.local/share/cinnamon/extensions/$uuid" ]; then
        report "extension: $uuid" ok
    else
        report "extension: $uuid" warn "not downloaded — re-run 05-cinnamonSetup.sh"
    fi
done
for uuid in "${APPLET_UUIDS[@]}"; do
    if [ -d "$HOME/.local/share/cinnamon/applets/$uuid" ]; then
        report "applet: $uuid" ok
    else
        report "applet: $uuid" warn "not downloaded — re-run 05-cinnamonSetup.sh"
    fi
done

# --- 7. Nemo right-click actions (05) -------------------------------------
dir_exists "Nemo 'Compress PDF'" "$HOME/.local/share/nemo/actions/devuan-compress-pdf.nemo_action"
dir_exists "Nemo 'Compress Image'" "$HOME/.local/share/nemo/actions/devuan-compress-image.nemo_action"

# --- 8. Power-user launchers (09) -----------------------------------------
dir_exists "devuan-update-gui" "$HOME/.local/share/devuan-cinnamon/bin/devuan-update-gui.py"
dir_exists "devuan-menu" "$HOME/.local/bin/devuan-menu"
dir_exists "devuan-update-check" "$HOME/.local/bin/devuan-update-check.sh"

# --- 9. Cron jobs this kit installs ----------------------------------------
if crontab -l 2>/dev/null | grep -q "devuan-cinnamon-setup: update notifier"; then
    report "update notifier cron (09)" ok
else
    report "update notifier cron (09)" warn "not installed — re-run 09-updateSystem.sh"
fi
if sudo crontab -l 2>/dev/null | grep -q "devuan-cinnamon-setup: weekly fstrim"; then
    report "weekly fstrim cron (01)" ok
else
    report "weekly fstrim cron (01)" warn "not installed — re-run 01-systemSetup.sh"
fi

# --- 10. Services -----------------------------------------------------------
service_state cron cron optional
service_state tlp tlp optional
service_state cups cupsd optional
service_state fwupd fwupd optional

echo
echo -e "${GREEN}  ${PASS} passed${NC}, ${RED}${FAIL} failed${NC}, ${YELLOW}${WARN} warnings${NC}"
if [ "$FAIL" -gt 0 ]; then
    echo
    log_err "Some checks failed — see lines above, then re-run the relevant script."
    exit 1
fi
exit 0