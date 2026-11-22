#!/usr/bin/env bash
# =======================================================
# lib/common.sh — shared helpers for every script in this toolkit
# -------------------------------------------------------
# Source this near the top of a script:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/../lib/common.sh"
#
# Provides:
#   - colored log_info/log_ok/log_warn/log_err
#   - ask "question" [Y|N]                  -> y/n prompt with default
#   - is_installed <pkg>                    -> dpkg check
#   - install_pkgs "label" pkg1 pkg2 ...     -> only installs what's missing
#   - purge_if_installed "label" pkg1 ...    -> only purges what's present
#   - apt_update                            -> refresh pkg lists once (see DEBSWAY_SKIP_APT_UPDATE)
#   - init_system                           -> prints: openrc | systemd | sysvinit
#   - service_enable_now <svc>              -> enable+start on whatever init runs
#   - service_start <svc>                   -> start only, no enable-at-boot
#   - require_not_root
#   - actual_user / run_as_user <cmd...>    -> for when the script runs via sudo
#   - user_gsettings / cinnamon_custom_binding <name> <cmd> <key>
# =======================================================

# Don't re-source
if [ -n "${DCS_COMMON_LOADED:-}" ]; then return 0 2>/dev/null || exit 0; fi
DCS_COMMON_LOADED=1

RED="\033[0;31m"; GREEN="\033[0;32m"; YELLOW="\033[1;33m"; CYAN="\033[0;36m"; BLUE="\033[1;34m"; NC="\033[0m"

log_info() { echo -e "${CYAN}[*]${NC} $1"; }
log_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $1"; }
log_head() {
    echo -e "${CYAN}=========================================================${NC}"
    echo -e "${CYAN} $1${NC}"
    echo -e "${CYAN}=========================================================${NC}"
}

ask() {
    local prompt="$1" default="${2:-Y}" reply
    local hint="(Y/n)"
    [ "$default" = "N" ] && hint="(y/N)"
    read -rp "$(echo -e "${YELLOW}${prompt} ${hint}: ${NC}")" reply
    reply=${reply:-$default}
    [[ "$reply" =~ ^[Yy]$ ]]
}

require_not_root() {
    if [[ $EUID -eq 0 ]] && [ -z "${SUDO_USER:-}" ]; then
        log_err "Do not run this as root / sudo bash <script>.sh — run as your normal user."
        log_err "This script calls sudo itself for the parts that need it."
        exit 1
    fi
}

is_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

install_pkgs() {
    local label="$1"; shift
    local to_install=()
    local pkg
    for pkg in "$@"; do
        is_installed "$pkg" || to_install+=("$pkg")
    done
    if [ "${#to_install[@]}" -eq 0 ]; then
        log_ok "$label already installed."
        return 0
    fi
    log_info "$label: installing ${to_install[*]}"
    if sudo apt-get install -y "${to_install[@]}"; then
        log_ok "$label installed."
    else
        log_warn "$label: some packages failed to install (continuing)."
        return 1
    fi
}

purge_if_installed() {
    local label="$1"; shift
    local to_purge=()
    local pkg
    for pkg in "$@"; do
        is_installed "$pkg" && to_purge+=("$pkg")
    done
    if [ "${#to_purge[@]}" -eq 0 ]; then
        log_info "$label: nothing installed, skipping."
        return 0
    fi
    log_info "$label: purging ${to_purge[*]}"
    if sudo apt-get purge -y "${to_purge[@]}"; then
        log_ok "$label removed."
    else
        log_warn "$label: some packages failed to purge (continuing)."
    fi
}

# Refresh apt package lists exactly once per run. Honors
# DEBSWAY_SKIP_APT_UPDATE=1 (set automatically by run.sh/install.sh after the
# first successful refresh so the remaining ~15 steps don't re-refresh).
apt_update() {
    if [ "${DEBSWAY_SKIP_APT_UPDATE:-0}" = "1" ]; then
        log_info "apt lists already fresh (DEBSWAY_SKIP_APT_UPDATE=1) — skipping apt-get update."
        return 0
    fi
    log_info "Refreshing apt package lists..."
    if sudo apt-get update; then
        export DEBSWAY_SKIP_APT_UPDATE=1
        log_ok "apt lists refreshed."
    else
        log_warn "apt-get update reported an error — continuing anyway."
    fi
}

# ---------------------------------------------------------------------------
# Init system detection & service abstraction.
#
# Devuan can boot under sysvinit, OpenRC, or runit — this toolkit is written
# for the OpenRC variant, but detects at runtime rather than assuming, so it
# doesn't break on a sysvinit or (Debian) systemd box someone runs it on.
#
# Priority: OpenRC native (rc-service/rc-update) > systemd > sysvinit fallback
# (service + update-rc.d — Devuan's sysvinit and OpenRC both understand this).
# ---------------------------------------------------------------------------
init_system() {
    if command_exists rc-service && command_exists rc-update && [ -d /etc/runlevels ]; then
        echo "openrc"
    elif command_exists systemctl && [ -d /run/systemd/system ]; then
        echo "systemd"
    else
        echo "sysvinit"
    fi
}

# Enable a service at boot AND start it now.
service_enable_now() {
    local svc="$1"
    case "$(init_system)" in
        openrc)
            sudo rc-update add "$svc" default >/dev/null 2>&1 || true
            sudo rc-service "$svc" start >/dev/null 2>&1 || true
            ;;
        systemd)
            sudo systemctl enable --now "$svc" >/dev/null 2>&1 || true
            ;;
        sysvinit)
            sudo update-rc.d "$svc" defaults >/dev/null 2>&1 || true
            sudo service "$svc" start >/dev/null 2>&1 || true
            ;;
    esac
}

# Start a service now without touching its boot-time enablement.
service_start() {
    local svc="$1"
    case "$(init_system)" in
        openrc)   sudo rc-service "$svc" start >/dev/null 2>&1 || true ;;
        systemd)  sudo systemctl start "$svc" >/dev/null 2>&1 || true ;;
        sysvinit) sudo service "$svc" start >/dev/null 2>&1 || true ;;
    esac
}

service_restart() {
    local svc="$1"
    case "$(init_system)" in
        openrc)   sudo rc-service "$svc" restart >/dev/null 2>&1 || true ;;
        systemd)  sudo systemctl restart "$svc" >/dev/null 2>&1 || true ;;
        sysvinit) sudo service "$svc" restart >/dev/null 2>&1 || true ;;
    esac
}

ACTUAL_USER="${SUDO_USER:-$USER}"
run_as_user() {
    if [ "$(id -un)" = "$ACTUAL_USER" ]; then
        "$@"
    else
        sudo -u "$ACTUAL_USER" "$@"
    fi
}

# gsettings/dconf writes need a session bus. Cinnamon settings live in
# dconf, which works fine without systemd (dconf is a plain file-backed
# store + a dbus service — dbus itself runs happily under OpenRC), but we
# still need to run the write AS the desktop user, not root.
user_gsettings() {
    run_as_user dbus-launch --exit-with-session gsettings "$@" 2>/dev/null \
        || run_as_user gsettings "$@" 2>/dev/null \
        || return 1
}

# ===========================================================================
# Cinnamon custom keybindings — additive, never a bulk overwrite.
#
# dconf schema (confirmed against Cinnamon 6):
#   /org/cinnamon/desktop/keybindings/custom-list   = ['custom0', ...]
#   /org/cinnamon/desktop/keybindings/custom-keybindings/customN/binding  = ['<Super>a']
#   .../customN/command  = 'x-terminal-emulator -e opencode'
#   .../customN/name     = 'OpenCode AI'
#
# Walks the existing custom-list; if the same name already exists its
# command/binding are refreshed in place. Otherwise allocates the next free
# custom<N> slot. Returns 0 on success (or no-op), 1 on failure.
# ---------------------------------------------------------------------------
_cbg_get() { # _cbg_get <slot> <key>
    user_gsettings get \
        "org.cinnamon.desktop.keybindings.custom-keybinding:/org/cinnamon/desktop/keybindings/custom-keybindings/$1/" \
        "$2" 2>/dev/null
}
_cbg_list() { # _cbg_list <gvariant array> -> names, one per line, via python
    python3 - "$1" <<'PY'
import sys, ast
try:
    v = ast.literal_eval(sys.argv[1])
except Exception:
    v = []
print("\n".join(x for x in v if isinstance(x, str)))
PY
}
_cbg_append() { # _cbg_append <gvariant array> <slot> -> new gvariant array
    python3 - "$1" "$2" <<'PY'
import sys, ast
v = ast.literal_eval(sys.argv[1]) or []
if sys.argv[2] not in v:
    v.append(sys.argv[2])
print(repr(v))
PY
}

cinnamon_custom_binding() {
    local name="$1" command="$2" binding="$3"
    local base="/org/cinnamon/desktop/keybindings"
    local list slot schema

    list="$(user_gsettings get org.cinnamon.desktop.keybindings custom-list 2>/dev/null)"
    list="${list:-[]}"

    while read -r slot; do
        [ -n "$slot" ] || continue
        local existing_cmd existing_bind
        existing_cmd="$(_cbg_get "$slot" command)"
        existing_bind="$(_cbg_get "$slot" binding)"
        if [ "$(_cbg_get "$slot" name)" = "'$name'" ]; then
            # Same name -> refresh command/binding in place (idempotent re-run).
            if [ "$existing_cmd" != "'$command'" ]; then
                user_gsettings set \
                    "org.cinnamon.desktop.keybindings.custom-keybinding:/org/cinnamon/desktop/keybindings/custom-keybindings/$slot/" \
                    command "'$command'" || return 1
            fi
            if [ "$existing_bind" != "['$binding']" ]; then
                user_gsettings set \
                    "org.cinnamon.desktop.keybindings.custom-keybinding:/org/cinnamon/desktop/keybindings/custom-keybindings/$slot/" \
                    binding "['$binding']" || return 1
            fi
            log_ok "Keybinding '$name' present — command/binding refreshed if needed."
            return 0
        fi
    done < <(_cbg_list "$list")

    # Allocate the next free custom<N> slot.
    local i=0 found
    while true; do
        found="custom$i"
        printf '%s\n' "$list" | grep -q "'$found'" || break
        i=$((i+1))
    done

    local newlist
    newlist="$(_cbg_append "$list" "$found")"
    schema="org.cinnamon.desktop.keybindings.custom-keybinding:/org/cinnamon/desktop/keybindings/custom-keybindings/$found/"

    user_gsettings set org.cinnamon.desktop.keybindings custom-list "$newlist" || return 1
    user_gsettings set "$schema" name    "'$name'"        || return 1
    user_gsettings set "$schema" command "'$command'"     || return 1
    user_gsettings set "$schema" binding "['$binding']"   || return 1
    log_ok "Keybinding '$name' ($binding) added."
    return 0
}

# ===========================================================================
# 06-cliStack section 5 — VSCodium + C++/Python dev toolchain + Nemo wiring
# ===========================================================================

# Install VSCodium from its official APT repo (telemetry-free VS Code,
# stays updated via apt instead of a one-off .deb).
install_vscodium_apt() {
    if is_installed codium || command_exists codium; then
        log_ok "VSCodium already installed."
        return 0
    fi
    [ -f /etc/apt/sources.list.d/vscodium.list ] || {
        install_pkgs "VSCodium repo prereqs" curl gnupg
        curl -fsSL "https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg"             | gpg --dearmor | sudo tee /usr/share/keyrings/vscodium-archive-keyring.gpg >/dev/null
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/vscodium-archive-keyring.gpg] https://download.vscodium.com/debs vscodium main" |
            sudo tee /etc/apt/sources.list.d/vscodium.list >/dev/null
    }
    purge_if_installed "VSCodium beta/pre" codium-beta 2>/dev/null || true
    install_pkgs "VSCodium" codium
}

# C++ (clangd-based) + Python (ruff/basedpyright) toolchain.
vscodium_dev_toolchain() {
    install_pkgs "C++ toolchain (VSCodium)" build-essential cmake clang clangd clang-format lldb gdb
    install_pkgs "Python toolchain (VSCodium)" python3 python3-pip python3-venv python3-dev
}

# Extensions: clangd family + Open VSX-compatible Python tooling (no license-blocked cpptools).
vscodium_install_extensions() {
    local ext
    for ext in         llvm-vs-code-extensions.vscode-clangd         vadimcn.vscode-lldb         ms-vscode.cmake-tools         twxs.cmake         ms-python.python         ms-python.debugpy         detachhead.basedpyright; do
        command_exists codium && codium --install-extension "$ext" --force >/dev/null 2>&1
    done
}

# Starter C++/Python project opened at first launch.
vscodium_starter_project() {
    local dir="$HOME/dev/cpp-starter"
    mkdir -p "$dir/src"
    [ -f "$dir/CMakeLists.txt" ] || cat > "$dir/CMakeLists.txt" << 'EOF'
cmake_minimum_required(VERSION 3.16)
project(cpp_starter CXX)
set(CMAKE_CXX_STANDARD 20)
add_executable(main src/main.cpp)
EOF
    [ -f "$dir/src/main.cpp" ] || cat > "$dir/src/main.cpp" << 'EOF'
#include <iostream>
int main() { std::cout << "Hello from VSCodium\n"; return 0; }
EOF
}

# Shared 'Open with VSCodium' Nemo action (used by 05 + 06). Idempotent,
# no-op if codium isn't present yet.
nemo_add_vscode_action() {
    local bin_dir="$HOME/.local/bin"
    local actions_dir="$HOME/.local/share/nemo/actions"
    command_exists codium || { log_warn "VSCodium not installed yet — skipping Nemo action."; return 0; }
    mkdir -p "$bin_dir" "$actions_dir"
    [ -f "$actions_dir/devuan-open-vscode.nemo_action" ] && { log_ok "'Open with VSCodium' Nemo action already present."; return 0; }
    cat > "$bin_dir/devuan-nemo-open-vscode.sh" << 'EOF'
#!/usr/bin/env bash
exec codium "$@"
EOF
    chmod +x "$bin_dir/devuan-nemo-open-vscode.sh"
    cat > "$actions_dir/devuan-open-vscode.nemo_action" << 'EOF'
[Nemo Action]
Name=Open with VSCodium
Comment=Open this folder in VSCodium
Exec=$HOME/.local/bin/devuan-nemo-open-vscode.sh %F
Icon-Name=vscodium
Selection=s
Extensions=dir;
EscapeSpaces=true
EOF
    log_ok "'Open with VSCodium' Nemo action added."
}

