#!/usr/bin/env bash
# =======================================================
# 05 Cinnamon Setup - extensions, hotkeys, polish, Nemo actions
# -------------------------------------------------------
# Merges the old fancyCinnamon.sh / hotkeys.sh / ohmydebnPolish.sh /
# nemoActions.sh:
#   * Spice extensions/applets from the official cinnamon-spices
#     GitHub repos (verified UUIDs): Maximus, Blur Cinnamon, gTile,
#     Burn My Windows (preconfigured to Glide), New Window Settings,
#     Rearrange Workspaces, Focus New Window, Dim Inactive Windows,
#     Color Picker, Weather, SpicesUpdate, Coverflow alt-tab,
#     Night Light, Super+L lock
#   * Burn My Windows and (already-installed) Blur Cinnamon get their
#     settings.json written by lib helpers - no "click through every
#     settings page" chore after a fresh install
#   * Cinnamon custom hotkeys (Super+Return terminal, Super+F files,
#     Ctrl+Super+E editor, Ctrl+Shift+Escape system monitor)
#   * Panel: single grouped-window-list (duplicate window-list and the
#     stranded favorites applet are removed), a launcher cluster after the
#     menu, plus windows-quick-list + trash applets
#   * Polish: desktop sounds off, max effect speed (snappy), alt-tab
#     icons+preview across workspaces, hot corners (Expo top-left,
#     Show-Desktop bottom-right), hide ibus tray, kernel-hardening
#     module blacklists. Cinnamon desktop effects themselves stay ON.
#   * Nemo right-click actions: Compress PDF / Image, Open in
#     VS Code (if present), Open in OpenCode
# =======================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_not_root
log_head "05 Cinnamon Setup"

if ! command_exists python3; then
    install_pkgs "python3 (spice installer / dconf helpers)" python3
fi

SPICE_INSTALLER="$SCRIPT_DIR/../lib/install-spice.py"
LIST_ADD="$SCRIPT_DIR/../lib/dconf-list-add.py"
LIST_REMOVE="$SCRIPT_DIR/../lib/dconf-list-remove.py"
APPLET_ADD="$SCRIPT_DIR/../lib/panel-applet-add.py"
SET_PANEL_LAYOUT="$SCRIPT_DIR/../lib/set-panel-layout.py"
BURNMY_SETTER="$SCRIPT_DIR/../lib/apply-burnmywindows-settings.py"
BLUR_SETTER="$SCRIPT_DIR/../lib/apply-blur-cinnamon-settings.py"
EXT_DIR="$HOME/.local/share/cinnamon/extensions"
APPLET_DIR="$HOME/.local/share/cinnamon/applets"
CINNAMON_CONFIGS="$HOME/.cinnamon/configs"
HAVE_SESSION=0
command_exists gsettings && [ -n "${DISPLAY:-}" ] && HAVE_SESSION=1

remove_extension() {
    # $1 = uuid, $2 = human label - deletes the extension dir and drops it
    # from org.cinnamon enabled-extensions (idempotent).
    local uuid="$1" label="$2"
    if [ -d "$EXT_DIR/$uuid" ]; then
        rm -rf "${EXT_DIR:?}/${uuid:?}"
        log_ok "$label removed."
    else
        log_info "$label not present - nothing to remove."
    fi
    if [ "$HAVE_SESSION" -eq 1 ]; then
        run_as_user python3 "$LIST_REMOVE" org.cinnamon enabled-extensions "$uuid" >/dev/null
    fi
}

install_extension() {
    # $1 = uuid, $2 = human label, $3 = optional "skip-enable"
    local uuid="$1" label="$2"
    if [ -d "$EXT_DIR/$uuid" ]; then
        log_ok "$label already downloaded."
    else
        log_info "Downloading $label ($uuid) from cinnamon-spices-extensions..."
        if ! run_as_user python3 "$SPICE_INSTALLER" extensions "$uuid" "$EXT_DIR" | grep -q OK; then
            log_warn "Could not download $label - skipping (network / GitHub API rate limit)."
            return 1
        fi
        log_ok "$label downloaded."
    fi
    if [ "$HAVE_SESSION" -eq 1 ]; then
        run_as_user python3 "$LIST_ADD" org.cinnamon enabled-extensions "$uuid" >/dev/null
        log_ok "$label enabled."
    fi
}

install_applet() {
    # $1 = uuid, $2 = human label, $3 = optional package deps (space-separated)
    local uuid="$1" label="$2" deps="${3:-}"
    if [ -n "$deps" ]; then
        # shellcheck disable=SC2086
        install_pkgs "$label dependencies" $deps
    fi
    if [ -d "$APPLET_DIR/$uuid" ]; then
        log_ok "$label already downloaded."
    else
        log_info "Downloading $label ($uuid) from cinnamon-spices-applets..."
        if ! run_as_user python3 "$SPICE_INSTALLER" applets "$uuid" "$APPLET_DIR" | grep -q OK; then
            log_warn "Could not download $label - skipping."
            return 1
        fi
        log_ok "$label downloaded."
    fi
    if [ "$HAVE_SESSION" -eq 1 ]; then
        run_as_user python3 "$APPLET_ADD" "$uuid" >/dev/null
        log_ok "$label added to the panel."
    fi
}

# ---------------------------------------------------------------------------
# 1. Extensions - the "modern Cinnamon" set from the walkthroughs
# ---------------------------------------------------------------------------
install_extension "cinnamon-maximus@fmete" "Cinnamon Maximus"
log_info "(Tip: with Maximus on, hold Alt and nudge the mouse to get a maximized window's titlebar back.)"

install_extension "BlurCinnamon@klangman" "Blur Cinnamon"
install_extension "gTile@shuairan" "gTile"
log_info "gTile opens with Super+G by default."

# Ergonomic window-management set - all from the same author or the walkthroughs.
install_extension "NewWindowSettings@klangman" "New Window Settings"
install_extension "RearrangeWorkspaces@klangman" "Rearrange Workspaces"
install_extension "focus-new-window@mdpenguin" "Focus New Window"
install_extension "dim-inactive-windows@jark" "Dim Inactive Windows"

# Burn My Windows - preconfigured to the subtle Glide effect; the old
# standalone Magic Lamp extension is removed (Burn My Windows supersedes it).
install_extension "CinnamonBurnMyWindows@klangman" "Burn My Windows"
remove_extension "CinnamonMagicLamp@klangman" "Magic Lamp Effect"

if run_as_user python3 "$BURNMY_SETTER" | grep -q OK; then
    log_ok "Burn My Windows set to Glide (subtle; minimize stays Cinnamon's default)."
else
    log_warn "Could not pre-write Burn My Windows settings - configure it via Extensions > Burn My Windows."
fi

if run_as_user python3 "$BLUR_SETTER" | grep -q OK; then
    log_ok "Blur Cinnamon configured: panels + popup menus + alt-tab/overview/expo, graphite dim."
else
    log_warn "Could not pre-write Blur Cinnamon settings - configure it via Extensions > Blur Cinnamon."
fi

# ---------------------------------------------------------------------------
# 2. Panel layout - one grouped window list, a launcher cluster after the
#    menu, plus windows-quick-list + trash. set-panel-layout.py also removes
#    duplicates from older runs (window-list@cinnamon.org, and the stranded
#    favorites applet) while keeping anything else you've added.
# ---------------------------------------------------------------------------
if [ "$HAVE_SESSION" -eq 1 ]; then
    if OUT=$(run_as_user python3 "$SET_PANEL_LAYOUT"); then
        case "$OUT" in
            UNCHANGED) log_ok "Panel layout already correct." ;;
            OK*) log_ok "Panel layout applied ($OUT)." ;;
        esac
    else
        log_warn "Panel layout could not be applied - applets are unchanged."
    fi
fi
if [ "$HAVE_SESSION" -eq 0 ]; then
    log_info "No active Cinnamon session - panel layout deferred (run once logged in)."
fi

# ---------------------------------------------------------------------------
# 3. Color Picker applet (needs numpy + xlib for its built-in color lookup)
# ---------------------------------------------------------------------------
install_applet "color-picker@fmete" "Color Picker" "python3-numpy python3-xlib"

# ---------------------------------------------------------------------------
# 3b. Weather + SpicesUpdate applets (both from Petri Heinonen / claudiux -
#     external, so they live alongside the built-in panel set)
# ---------------------------------------------------------------------------
install_applet "weather@mockturtl" "Weather" "python3-requests"
install_applet "SpicesUpdate@claudiux" "SpicesUpdate"
log_info "Open the Weather applet's settings to pick your location/source."

# ---------------------------------------------------------------------------
# 4. Built-in behaviors: Night Light + Super+L lock
# ---------------------------------------------------------------------------
if [ "$HAVE_SESSION" -eq 1 ]; then
    if user_gsettings set org.cinnamon.settings-daemon.plugins.color night-light-enabled true; then
        user_gsettings set org.cinnamon.settings-daemon.plugins.color night-light-schedule-automatic true
        log_ok "Night Light enabled (automatic sunset/sunrise schedule)."
    else
        log_warn "Night Light unavailable (needs Cinnamon 6.4+)."
    fi

    if ! cinnamon_custom_binding "Lock Screen" "cinnamon-screensaver-command --lock" "<Super>l"; then
        log_warn "Could not bind Super+L (Cinnamon may bind it by default already)."
    fi
fi

# ---------------------------------------------------------------------------
# 5. Custom hotkeys - the essentials set
# ---------------------------------------------------------------------------
if [ "$HAVE_SESSION" -eq 1 ]; then
    cinnamon_custom_binding "Terminal"        "x-terminal-emulator"            "<Super>Return"
    cinnamon_custom_binding "Terminal (alt)"   "x-terminal-emulator"            "<Primary><Alt>t"
    cinnamon_custom_binding "File Manager"     "nemo"                           "<Super>f"
    cinnamon_custom_binding "Text Editor"      "xed"                            "<Primary><Super>e"
    cinnamon_custom_binding "System Monitor"   "x-terminal-emulator -e htop"    "<Primary><Shift>Escape"
    log_ok "Custom hotkeys applied."
else
    log_warn "No active Cinnamon session - hotkeys skipped. Re-run once logged in."
fi

# ---------------------------------------------------------------------------
# 6. Polish - sounds, snappiness, alt-tab, ibus, kernel hardening
# ---------------------------------------------------------------------------
if [ "$HAVE_SESSION" -eq 1 ]; then
    APPLIED=0
    for PAIR in \
        "org.cinnamon.desktop.sound|volume-sound-enabled|false" \
        "org.cinnamon.sounds|close-enabled|false" \
        "org.cinnamon.sounds|login-enabled|false" \
        "org.cinnamon.sounds|logout-enabled|false" \
        "org.cinnamon.sounds|map-enabled|false" \
        "org.cinnamon.sounds|maximize-enabled|false" \
        "org.cinnamon.sounds|minimize-enabled|false" \
        "org.cinnamon.sounds|notification-enabled|false" \
        "org.cinnamon.sounds|plug-enabled|false" \
        "org.cinnamon.sounds|switch-enabled|false" \
        "org.cinnamon.sounds|tile-enabled|false" \
        "org.cinnamon.sounds|unmaximize-enabled|false" \
        "org.cinnamon.sounds|unplug-enabled|false"; do
        SCHEMA="${PAIR%%|*}"; REST="${PAIR#*|}"; KEY="${REST%%|*}"; VAL="${REST##*|}"
        if user_gsettings set "$SCHEMA" "$KEY" "$VAL" >/dev/null 2>&1; then
            APPLIED=1
        fi
    done
    [ "$APPLIED" -eq 1 ] && log_ok "Desktop sounds disabled." \
        || log_warn "Could not apply sound settings on this Cinnamon version."

    if user_gsettings set org.cinnamon window-effect-speed 2 >/dev/null 2>&1; then
        log_ok "Effect speed maxed (snappy)."
    else
        log_warn "Could not set window-effect-speed on this Cinnamon version."
    fi

    if user_gsettings set org.cinnamon alttab-switcher-style "icons+preview" >/dev/null 2>&1 \
        && user_gsettings set org.cinnamon alttab-switcher-show-all-workspaces true >/dev/null 2>&1; then
        log_ok "Alt-Tab set to icons+preview across all workspaces."
    fi

    user_gsettings set org.freedesktop.ibus.panel show-icon-on-systray false >/dev/null 2>&1 \
        && log_ok "ibus tray icon hidden."

    # Hot corners: Expo top-left, Show-Desktop bottom-right; centre corners off.
    if user_gsettings set org.cinnamon hotcorner-layout \
        "['expo:true:0', 'scale:false:0', 'scale:false:0', 'desktop:true:0']" >/dev/null 2>&1; then
        log_ok "Hot corners set: Expo (top-left), Show-Desktop (bottom-right)."
    fi

    # Resize windows with the right mouse button on a titlebar.
    if user_gsettings set org.gnome.desktop.wm.preferences resize-with-right-button true >/dev/null 2>&1; then
        log_ok "Right-button titlebar resize enabled."
    fi

    # Panel height (idempotent; 40px is the toolkit's comfortable taskbar).
    if user_gsettings set org.cinnamon panels-height "['1:40']" >/dev/null 2>&1; then
        log_ok "Panel height set to 40px."
    fi
fi

# ---------------------------------------------------------------------------
# 7. Kernel hardening - blacklist modules behind in-place-decrypt bugs
#    (algif_aead "Copy Fail", esp4/esp6/rxrpc "Dirty Frag"). Ported from
#    ohmydebn's modprobe.sh; the conf files are easy to revert.
# ---------------------------------------------------------------------------
NEEDS_INITRAMFS_UPDATE=false
CONFIG_ALGIF=/etc/modprobe.d/disable-algif-aead.conf
if [ ! -f "$CONFIG_ALGIF" ]; then
    echo "install algif_aead /bin/false" | sudo tee "$CONFIG_ALGIF" >/dev/null
    sudo rmmod algif_aead 2>/dev/null || true
    NEEDS_INITRAMFS_UPDATE=true
    log_ok "Blacklisted algif_aead."
fi
CONFIG_DIRTYFRAG=/etc/modprobe.d/disable-esp4-esp6-rxrpc.conf
if [ ! -f "$CONFIG_DIRTYFRAG" ]; then
    {
        echo "install esp4 /bin/false"
        echo "install esp6 /bin/false"
        echo "install rxrpc /bin/false"
    } | sudo tee "$CONFIG_DIRTYFRAG" >/dev/null
    echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null || true
    sudo rmmod esp4 esp6 rxrpc 2>/dev/null || true
    NEEDS_INITRAMFS_UPDATE=true
    log_ok "Blacklisted esp4/esp6/rxrpc."
fi
if [ "$NEEDS_INITRAMFS_UPDATE" = true ]; then
    log_info "Updating initramfs (so the blacklists survive reboot)..."
    sudo update-initramfs -u 2>/dev/null && log_ok "Initramfs updated."
else
    log_ok "Kernel hardening already in place."
fi

# ---------------------------------------------------------------------------
# 8. Nemo right-click actions
# ---------------------------------------------------------------------------
BIN_DIR="$HOME/.local/bin"
ACTIONS_DIR="$HOME/.local/share/nemo/actions"
mkdir -p "$BIN_DIR" "$ACTIONS_DIR"

install_pkgs "Ghostscript" ghostscript
install_pkgs "ImageMagick" imagemagick

cat > "$BIN_DIR/devuan-nemo-compress-pdf.sh" << 'EOF'
#!/usr/bin/env bash
# Compresses each given PDF to "<name>-compressed.pdf" alongside the original.
set -uo pipefail
OK=0; FAIL=0
for f in "$@"; do
    [ -f "$f" ] || continue
    out="${f%.pdf}-compressed.pdf"
    if gs -sDEVICE=pdfwrite -dCompatibilityLevel=1.4 -dPDFSETTINGS=/ebook \
          -dNOPAUSE -dQUIET -dBATCH -sOutputFile="$out" "$f" 2>/dev/null; then
        OK=$((OK+1))
    else
        FAIL=$((FAIL+1))
    fi
done
if command -v notify-send >/dev/null 2>&1; then
    notify-send -i application-pdf "PDF compression done" "${OK} compressed, ${FAIL} failed." 2>/dev/null || true
fi
EOF
chmod +x "$BIN_DIR/devuan-nemo-compress-pdf.sh"
cat > "$ACTIONS_DIR/devuan-compress-pdf.nemo_action" << EOF
[Nemo Action]
Name=Compress PDF
Comment=Shrink this PDF with Ghostscript
Exec=$BIN_DIR/devuan-nemo-compress-pdf.sh %F
Icon-Name=application-pdf
Selection=any
Extensions=pdf;
EscapeSpaces=true
EOF
log_ok "'Compress PDF' added."

cat > "$BIN_DIR/devuan-nemo-compress-image.sh" << 'EOF'
#!/usr/bin/env bash
# Compresses each given image to "<name>-compressed.<ext>" alongside the original.
set -uo pipefail
OK=0; FAIL=0
for f in "$@"; do
    [ -f "$f" ] || continue
    ext="${f##*.}"
    base="${f%.*}"
    out="${base}-compressed.${ext}"
    if convert "$f" -strip -quality 85 "$out" 2>/dev/null; then
        OK=$((OK+1))
    else
        FAIL=$((FAIL+1))
    fi
done
if command -v notify-send >/dev/null 2>&1; then
    notify-send -i image-x-generic "Image compression done" "${OK} compressed, ${FAIL} failed." 2>/dev/null || true
fi
EOF
chmod +x "$BIN_DIR/devuan-nemo-compress-image.sh"
cat > "$ACTIONS_DIR/devuan-compress-image.nemo_action" << EOF
[Nemo Action]
Name=Compress Image
Comment=Shrink this image with ImageMagick (quality 85)
Exec=$BIN_DIR/devuan-nemo-compress-image.sh %F
Icon-Name=image-x-generic
Selection=any
Extensions=jpg;jpeg;png;webp;bmp;tiff;
EscapeSpaces=true
EOF
log_ok "'Compress Image' added."

# Deferred: 06-cliStack.sh installs VSCodium and calls nemo_add_vscode_action
# there, so the Nemo action only appears after the editor actually exists.
# Guard here anyway for partial runs (05 alone, no 06).
if command_exists codium; then
    nemo_add_vscode_action
else
    log_warn "'codium' not on PATH yet - Nemo 'Open with VSCodium' action deferred to step 06."
fi

if ! command_exists opencode; then
    log_warn "'opencode' not on PATH yet (installed by 10-aiAgents.sh) - adding the 'Open in OpenCode' action anyway."
fi
cat > "$BIN_DIR/devuan-nemo-open-opencode.sh" << 'EOF'
#!/usr/bin/env bash
# Opens a terminal in the given folder running OpenCode.
set -uo pipefail
DIR="${1:-$HOME}"
exec x-terminal-emulator -e bash -c "cd \"$DIR\" && opencode; exec bash"
EOF
chmod +x "$BIN_DIR/devuan-nemo-open-opencode.sh"
cat > "$ACTIONS_DIR/devuan-open-opencode.nemo_action" << EOF
[Nemo Action]
Name=Open in OpenCode
Comment=Open a terminal here running the OpenCode AI agent
Exec=$BIN_DIR/devuan-nemo-open-opencode.sh %F
Icon-Name=utilities-terminal
Selection=s
Extensions=dir;
EscapeSpaces=true
EOF
log_ok "'Open in OpenCode' added."

echo -e "${GREEN}05 Cinnamon Setup complete.${NC}"
if [ "$HAVE_SESSION" -eq 0 ]; then
    log_warn "No active Cinnamon session - extension/dconf steps were skipped. Re-run once logged in."
fi
log_warn "New extensions/applets need a Cinnamon restart: press Alt+F2, type 'r', Enter."
log_warn "If a new Nemo action doesn't show up right away, run 'nemo -q'."