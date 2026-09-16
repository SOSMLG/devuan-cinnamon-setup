#!/usr/bin/env bash
# ==========================================
# 🌿  Devuan Cinnamon Setup — Ordered Runner
# Post-install polish for a Devuan box where Cinnamon is
# already installed by the distro's own installer
# (task-cinnamon-desktop). Aims for an LMDE 7 "Gigi"-like
# feel with a lean, full-fledged Cinnamon experience, native
# to Devuan's OpenRC init.
#
# Deterministic: runs the 10 consolidated scripts straight
# through — nothing prompts, everything is idempotent and
# safe to re-run. Order matters (01 updates first, 04 themes
# the apps that 06+ finish wiring up).
#
# Usage:
#   bash run.sh                # run everything
#   bash run.sh --yes          # same as above (DEBSWAY_ASSUME_YES=1, default)
#   bash run.sh --list         # just show the ordered steps
#   bash run.sh --only 05      # run a single script by number
#   bash run.sh --no-update    # skip apt-get update up front
#   bash run.sh --verify       # run scripts/verifySetup.sh afterwards
#   bash run.sh --backup       # run scripts/configBackup.sh first
# ==========================================

set -uo pipefail
# NOTE: intentionally not using `set -e` — one script failing (say, a flaky
# download in an installer step) shouldn't abort every later step. Each
# script exits non-zero on failure so this runner can report it and carry on.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# --- Refuse to run as root directly ---
# Per-user state (Firefox profile, ~/.zshrc, Cinnamon/dconf settings,
# ~/.local/bin) must land in the real user's $HOME, not /root. Scripts call
# sudo themselves for the parts that need it.
if [ "$(id -u)" -eq 0 ] && [ -z "${SUDO_USER:-}" ]; then
    echo -e "${RED}Please run this as your normal user, not as root / sudo bash run.sh.${NC}"
    echo -e "${YELLOW}Each script will call sudo itself for the parts that need it.${NC}"
    exit 1
fi

# --- Flags ---
SHOW_LIST=0
ONLY=""
RUN_VERIFY=0
RUN_BACKUP=0
prev=""
for arg in "$@"; do
    if [ "$prev" = "--only" ]; then
        ONLY="$arg"
        prev=""
        continue
    fi
    case "$arg" in
        --list)      SHOW_LIST=1 ;;
        --verify)    RUN_VERIFY=1 ;;
        --backup)    RUN_BACKUP=1 ;;
        --only=*)    ONLY="${arg#--only=}" ;;
        --only)      : ;;  # value comes in next arg
        --yes)       export DEBSWAY_ASSUME_YES=1 ;;
        --no-update) export DEBSWAY_SKIP_APT_UPDATE=1 ;;
        --no-verify) RUN_VERIFY=0 ;;
        *) echo -e "${YELLOW}Unknown flag: $arg${NC}" ;;
    esac
    prev="$arg"
done

# --- Distro check (Devuan or Debian; both ship /etc/debian_version) ---
if [ -f /etc/devuan_version ]; then
    echo -e "${GREEN}Devuan detected: $(cat /etc/devuan_version)${NC}"
elif [ -f /etc/debian_version ]; then
    echo -e "${YELLOW}Debian-based system detected: $(cat /etc/debian_version) (not Devuan — most of this should still work)${NC}"
else
    echo -e "${YELLOW}Warning: this toolkit targets Devuan/Debian. Your system may not be compatible.${NC}"
    read -r -p "Continue anyway? (y/N): " continue_anyway
    [[ "$continue_anyway" =~ ^[Yy]$ ]] || exit 1
fi

# --- Init system check ---
case "$(init_system)" in
    openrc)  echo -e "${GREEN}Init system: OpenRC (rc-service/rc-update will be used)${NC}" ;;
    systemd) echo -e "${YELLOW}Init system: systemd (written for OpenRC, but adapts)${NC}" ;;
    sysvinit) echo -e "${YELLOW}Init system: sysvinit fallback (service/update-rc.d will be used)${NC}" ;;
esac

# --- Desktop check (informational only) ---
if command_exists cinnamon-session \
    || [ -n "${XDG_CURRENT_DESKTOP:-}" ] && [[ "${XDG_CURRENT_DESKTOP,,}" == *cinnamon* ]]; then
    echo -e "${GREEN}Cinnamon detected.${NC}"
else
    echo -e "${YELLOW}Cinnamon not detected in this session — fine over SSH before first login, but"
    echo -e "${YELLOW}the desktop/preferences steps (04, 05, 09) need an active Cinnamon session to apply.${NC}"
fi

echo

# --- Ordered list: "script|description" ---
SCRIPTS=(
    "01-systemSetup.sh|Update everything, add user to input/video/render, weekly SSD trim, Timeshift"
    "02-debloat.sh|Remove Warpinator, HexChat, GNOME extras, games; disable Tracker; autoremove"
    "03-hardwareCodecs.sh|WiFi/Bluetooth firmware, CPU microcode, fwupd, media codecs, touchpad fixes"
    "04-theme.sh|Mint-Y base + Catppuccin Mocha palette across the desktop and every themed app"
    "05-cinnamonSetup.sh|Cinnamon extensions, applets, custom hotkeys, polish, Nemo right-click actions"
    "06-cliStack.sh|ButterBash, fonts (Noto/Nerd/Inter), zsh + starship + gnome-terminal, fastfetch, dev extras"
    "07-apps.sh|Flatpak/Flathub + software center, printing, GParted, firewall panel, VLC, qBit, TLP, Vesktop, Telegram"
    "08-firefox.sh|Install & harden Firefox ESR with Betterfox user.js + privacy policies"
    "09-updateSystem.sh|Cron update notifier + themed GTK update window + Devuan Menu (Super+M)"
    "10-aiAgents.sh|OpenCode agent + VSCodium, Super+A hotkey, system skill file"
)

show_list() {
    for i in "${!SCRIPTS[@]}"; do
        ENTRY="${SCRIPTS[$i]}"
        SCRIPT="${ENTRY%%|*}"
        DESC="${ENTRY#*|}"
        printf "  %2d  %-24s %s\n" "$((i + 1))" "$SCRIPT" "$DESC"
    done
}

if [ "$SHOW_LIST" -eq 1 ]; then
    echo -e "${BLUE}Devuan Cinnamon Setup — ordered steps:${NC}"
    show_list
    echo
    echo -e "${YELLOW}Run everything with: bash run.sh${NC}"
    exit 0
fi

# --- State log (used by verifySetup.sh + documentation) ---
STATE_DIR="$HOME/.local/state/devuan-cinnamon-setup"
mkdir -p "$STATE_DIR"
STATE_LOG="$STATE_DIR/last-run.log"
record_run() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$STATE_LOG"
}
record_run "run.sh start (flags: $*) init=$(init_system)"

FAILED=()

# --- Single up-front apt refresh ---
# One refresh before any step runs, then flip DEBSWAY_SKIP_APT_UPDATE so the
# scripts' own apt_update() calls (and any --only run) skip straight to work
# instead of re-refreshing ~15 times.
if [ "${DEBSWAY_SKIP_APT_UPDATE:-0}" != "1" ]; then
    apt_update
fi

# --- Optional config backup (before any changes) ---
if [ "$RUN_BACKUP" -eq 1 ]; then
    echo -e "${YELLOW}▶ scripts/configBackup.sh${NC}"
    if bash "$SCRIPTS_DIR/configBackup.sh"; then
        echo -e "${GREEN}   ✅ Config backup done.${NC}\n"
        record_run "config backup done"
    else
        echo -e "${RED}   ❌ configBackup.sh failed (continuing)${NC}\n"
        FAILED+=("configBackup.sh")
    fi
fi

echo -e "${BLUE}=========================================================${NC}"
echo -e "${BLUE}   Devuan Cinnamon Setup — LMDE energy, OpenRC bones${NC}"
echo -e "${BLUE}=========================================================${NC}"
echo -e "${GREEN}Running $([ -n "$ONLY" ] && echo "script $ONLY" || echo "all ${#SCRIPTS[@]} steps")${NC}"
echo

run_script() {
    local script="$1"
    local path="$SCRIPTS_DIR/$script"
    echo -e "${YELLOW}▶ $script${NC}"
    if [ ! -f "$path" ]; then
        echo -e "${RED}   ❌ Script not found: $path${NC}\n"
        FAILED+=("$script (missing)")
        record_run "FAIL script-not-found: $script"
        return
    fi
    if bash "$path"; then
        echo -e "${GREEN}   ✅ Done: $script${NC}\n"
        record_run "OK  $script"
    else
        echo -e "${RED}   ❌ $script exited with an error (continuing)${NC}\n"
        FAILED+=("$script")
        record_run "FAIL $script"
    fi
}

if [ -n "$ONLY" ]; then
    # Match "$ONLY" against a leading number in the script name (e.g. 5, 05, "05-cinnamonSetup.sh")
    matched=0
    for i in "${!SCRIPTS[@]}"; do
        ENTRY="${SCRIPTS[$i]}"
        SCRIPT="${ENTRY%%|*}"
        NUM="${SCRIPT%%-*}"
        if [ "$NUM" = "$ONLY" ] || [[ "$SCRIPT" == "$ONLY"* ]]; then
            run_script "$SCRIPT"
            matched=1
            break
        fi
    done
    [ "$matched" -eq 0 ] && { echo -e "${RED}No script matches '$ONLY'. Use --list to see the step numbers.${NC}"; exit 1; }
else
    for ENTRY in "${SCRIPTS[@]}"; do
        run_script "${ENTRY%%|*}"
    done
fi

echo -e "${BLUE}=========================================================${NC}"
echo -e "${BLUE}   🏁 All tasks processed.${NC}"
echo -e "${BLUE}=========================================================${NC}"

# --- Optional verification pass (end-state audit) ---
if [ "$RUN_VERIFY" -eq 1 ] && [ -f "$SCRIPTS_DIR/verifySetup.sh" ]; then
    echo -e "${YELLOW}▶ scripts/verifySetup.sh${NC}"
    if bash "$SCRIPTS_DIR/verifySetup.sh"; then
        echo -e "${GREEN}   ✅ Verification passed.${NC}\n"
        record_run "verify: passed"
    else
        echo -e "${RED}   ⚠ Verification found issues (see above).${NC}\n"
        record_run "verify: issues found"
    fi
fi

if [ "${#FAILED[@]}" -gt 0 ]; then
    echo -e "${RED}Failed:  ${FAILED[*]}${NC}"
    echo -e "${YELLOW}Re-run individual scripts with: bash scripts/<name>.sh${NC}"
    record_run "run.sh end: FAILED=${FAILED[*]}"
    exit 1
fi

record_run "run.sh end: all OK"
echo -e "${GREEN}Done. A logout/reboot is recommended (groups, theme, compositor, shell all benefit from a fresh session).${NC}"