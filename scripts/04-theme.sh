#!/usr/bin/env bash
# =======================================================
# 04 Theme — LMDE skeleton + Catppuccin Mocha coat
# -------------------------------------------------------
# Merges the old mintLook.sh / catppuccinTheme.sh / themePacks.sh
# into one theming pass that ends in the toolkit's identity:
#   * Mint-Y base (icons + theme) built from Debian's repo /
#     upstream source so the desktop is never theme-less
#   * a dark GTK/Cinnamon shell (Mint-Y-Dark) + Papirus-Dark icons
#     + Bibata cursor; prefer-dark set for portals too
#   * extra Arc/Papirus (+ Materia when available) theme packs + a
#     Ctrl+Super+T theme-picker (cycles GTK/icon/shell themes together)
#   * Catppuccin Mocha-RED chrome: the Cinnamon-capable
#     Catppuccin-GTK-Theme (Fausto-Korpsvart) built with the Red accent —
#     shell + GTK + window borders all match the app layer
#   * Catppuccin Mocha palette applied to every themed app
#     (gnome-terminal, btop, bat, eza, starship, fastfetch) from the
#     single canonical palette (config/palette/catppuccin-mocha.toml)
#   * palette + picker colors persisted for the update GUI / menu
#
# No Mint repo is added: icons come from Debian's Cinnamon Team,
# the theme itself is built from linuxmint/mint-themes source.
# =======================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=lib/theme-apply.sh
source "$SCRIPT_DIR/../lib/theme-apply.sh" || { log_err "theme-apply.sh missing — aborting."; exit 1; }

require_not_root
log_head "04 Theme"

THEME_PALETTE="$SCRIPT_DIR/../config/palette/catppuccin-mocha.toml"
HAVE_SESSION=0
command_exists gsettings && [ -n "${DISPLAY:-}" ] && HAVE_SESSION=1

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

THEMES_DIR="$HOME/.themes"
ICONS_DIR="$HOME/.icons"
mkdir -p "$THEMES_DIR" "$ICONS_DIR"

apt_update

# ---------------------------------------------------------------------------
# 1. Mint-Y / Mint-X icons — real Debian packages when available
# ---------------------------------------------------------------------------
if apt-cache show mint-y-icons >/dev/null 2>&1; then
    install_pkgs "Mint icon themes" mint-y-icons mint-x-icons
else
    log_warn "mint-y-icons isn't in your configured repos (needs Debian's 'gnome' section)."
    log_warn "Skipping Mint icons — Papirus will be the icon set instead."
fi

# ---------------------------------------------------------------------------
# 2. Mint-Y GTK/Cinnamon theme — built from linuxmint/mint-themes source
#    since it isn't reliably packaged for Debian like the icon themes are.
# ---------------------------------------------------------------------------
if [ -d "$THEMES_DIR/Mint-Y" ]; then
    log_ok "Mint-Y theme already present in $THEMES_DIR — skipping rebuild."
else
    install_pkgs "Theme build dependencies" python3 sassc gtk2-engines-murrine gtk2-engines-pixbuf

    log_info "Looking up the latest mint-themes release tag..."
    TAG=$(curl -fsSL https://api.github.com/repos/linuxmint/mint-themes/releases/latest 2>/dev/null \
        | grep -oP '"tag_name":\s*"\K[^"]+' | head -1)
    if [ -z "$TAG" ]; then
        log_warn "GitHub API lookup failed — using pinned fallback tag."
        TAG="2.2.3"
    fi
    log_info "Using mint-themes ${TAG}"

    ARCHIVE="$WORK_DIR/mint-themes.tar.gz"
    if curl -fsSL -o "$ARCHIVE" "https://codeload.github.com/linuxmint/mint-themes/tar.gz/refs/tags/${TAG}"; then
        mkdir -p "$WORK_DIR/mint-themes"
        tar -xzf "$ARCHIVE" -C "$WORK_DIR/mint-themes" --strip-components=1
        if [ -f "$WORK_DIR/mint-themes/generate-themes.py" ]; then
            log_info "Building themes (generate-themes.py)..."
            if ( cd "$WORK_DIR/mint-themes" && python3 generate-themes.py >/dev/null 2>&1 ) \
                && [ -d "$WORK_DIR/mint-themes/usr/share/themes" ]; then
                cp -r "$WORK_DIR/mint-themes/usr/share/themes/." "$THEMES_DIR/"
                log_ok "Mint-Y/Mint-X theme variants installed to $THEMES_DIR."
            else
                log_warn "Theme generation failed — skipping (cosmetic only)."
            fi
        else
            log_warn "generate-themes.py not found upstream — layout may have changed."
        fi
    else
        log_warn "Could not download mint-themes source — skipping."
    fi
fi

# ---------------------------------------------------------------------------
# 3. Catppuccin Mocha-Red chrome — built from Fausto-Korpsvart's
#    Catppuccin-GTK-Theme (Cinnamon-capable), Red accent so the shell, GTK
#    chrome and window borders match the app-layer palette. Cosmetic only:
#    if the build fails, the desktop simply keeps its current theme.
#    (Upstream >= v1.0.1 uses themes/install.sh; sole build dep is sassc.)
# ---------------------------------------------------------------------------
CATTUCCINO_GTK=""
HAS_CATP_RED=""
for cand in "$THEMES_DIR"/Catppuccin*Red*; do
    [ -d "$cand" ] || continue
    if [ -d "$cand/cinnamon" ] || [ -d "$cand/metacity-1" ]; then
        HAS_CATP_RED=1
        break
    fi
done
if [ -n "$HAS_CATP_RED" ]; then
    log_ok "Catppuccin Mocha-Red chrome already built — skipping rebuild."
else
    install_pkgs "Catppuccin theme build deps" sassc
    log_info "Looking up the latest Catppuccin-GTK-Theme release tag..."
    GTK_TAG=$(curl -fsSL https://api.github.com/repos/Fausto-Korpsvart/Catppuccin-GTK-Theme/releases/latest 2>/dev/null \
        | grep -oP '"tag_name":\s*"\K[^"]+' | head -1)
    GTK_REF="refs/tags/${GTK_TAG}"
    if [ -z "$GTK_TAG" ]; then
        GTK_REF="refs/heads/master"
        log_warn "Release lookup failed — cloning master branch instead."
    fi
    log_info "Using Catppuccin-GTK-Theme ${GTK_TAG:-master}"
    ARCHIVE="$WORK_DIR/catppuccin-gtk.tar.gz"
    if curl -fsSL -o "$ARCHIVE" "https://codeload.github.com/Fausto-Korpsvart/Catppuccin-GTK-Theme/tar.gz/${GTK_REF}"; then
        mkdir -p "$WORK_DIR/catppuccin-gtk"
        tar -xzf "$ARCHIVE" -C "$WORK_DIR/catppuccin-gtk" --strip-components=1
        INSTALL_SH=""
        [ -f "$WORK_DIR/catppuccin-gtk/themes/install.sh" ] && INSTALL_SH="$WORK_DIR/catppuccin-gtk/themes/install.sh"
        [ -z "$INSTALL_SH" ] && [ -f "$WORK_DIR/catppuccin-gtk/install.sh" ] && INSTALL_SH="$WORK_DIR/catppuccin-gtk/install.sh"
        if [ -n "$INSTALL_SH" ]; then
            log_info "Building Catppuccin Mocha-Red (Dark) into $THEMES_DIR..."
            if ( cd "$(dirname "$INSTALL_SH")" && ./install.sh -a red -m dark >/dev/null 2>&1 ) \
                && ls -d "$THEMES_DIR"/Catppuccin*Red*Dark* >/dev/null 2>&1; then
                log_ok "Catppuccin Mocha-Red chrome installed to $THEMES_DIR."
            else
                log_warn "Catppuccin theme build failed — keeping the current GTK theme (cosmetic only)."
            fi
        else
            log_warn "install.sh not found upstream — layout may have changed."
        fi
    else
        log_warn "Could not download Catppuccin-GTK-Theme — skipping."
    fi
fi
# Pick the best Red variant (prefer a dark theme, fall back to any Catppuccin Red).
for cand in "$THEMES_DIR"/Catppuccin*Red*; do
    [ -d "$cand" ] || continue
    if [ -d "$cand/cinnamon" ] || [ -d "$cand/metacity-1" ]; then
        CATTUCCINO_GTK="${cand##*/}"
        log_ok "Using upstream Catppuccin Mocha-Red chrome: '$CATTUCCINO_GTK'."
        break
    fi
done
[ -z "$CATTUCCINO_GTK" ] && log_warn "No usable Catppuccin Red theme found — desktop keeps its current chrome."

# ---------------------------------------------------------------------------
# 4. Cursor theme — Bibata when Debian has it
# ---------------------------------------------------------------------------
CURSOR_THEME=""
if apt-cache show bibata-cursor-theme >/dev/null 2>&1; then
    install_pkgs "Bibata cursor theme" bibata-cursor-theme
    CURSOR_THEME="Bibata-Modern-Classic"
else
    log_warn "bibata-cursor-theme not available in your repos — keeping the current cursor."
fi

# ---------------------------------------------------------------------------
# 5. Extra theme/icon packs (Arc, Papirus, Materia) + the theme picker.
#    Availability is checked per-package so a missing theme (e.g. Debian
#    has no materia-gtk-theme) never blocks the ones that do exist.
# ---------------------------------------------------------------------------
EXTRA_PKGS=()
for p in arc-theme papirus-icon-theme materia-gtk-theme; do
    if apt-cache show "$p" >/dev/null 2>&1; then
        EXTRA_PKGS+=("$p")
    else
        log_warn "$p not available in your repos — skipping."
    fi
done
[ "${#EXTRA_PKGS[@]}" -gt 0 ] && install_pkgs "Extra theme packs" "${EXTRA_PKGS[@]}"

if ! command_exists zenity; then
    install_pkgs "zenity (theme-picker dialog)" zenity
fi

BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
PICKER="$BIN_DIR/devuan-theme-picker.sh"
cat > "$PICKER" << 'EOF'
#!/usr/bin/env bash
# Lists *usable* GTK/Cinnamon themes — a dir is only offered when it really
# contains a GTK, Cinnamon-shell or metacity theme — lets you pick one via
# zenity, and applies it. The Cinnamon-shell + window-borders keys are only
# touched when the chosen theme can drive them (has a cinnamon/ or
# metacity-1/ dir): pointing them at a theme that can't renders the default
# *white* window borders.
set -uo pipefail

FOUND=()
for base in /usr/share/themes "$HOME/.themes"; do
    for d in "$base"/*/; do
        [ -d "$d" ] || continue
        if [ -d "$d/cinnamon" ] || [ -d "$d/gtk-3.0" ] || [ -d "$d/metacity-1" ]; then
            FOUND+=("${d%/}")
        fi
    done
done

mapfile -t THEMES < <(printf '%s\n' "${FOUND[@]##*/}" | sort -u)

if [ "${#THEMES[@]}" -eq 0 ]; then
    zenity --error --text="No usable themes found in /usr/share/themes or ~/.themes." 2>/dev/null
    exit 1
fi

CHOICE=$(printf '%s\n' "${THEMES[@]}" | zenity --list --title="Pick a theme" \
    --column="Theme" --height=400 --width=300 2>/dev/null)

[ -z "$CHOICE" ] && exit 0

gsettings set org.cinnamon.desktop.interface gtk-theme "$CHOICE" 2>/dev/null

SHELL_NAME=""
for base in /usr/share/themes "$HOME/.themes"; do
    if [ -d "$base/$CHOICE" ]; then
        { [ -d "$base/$CHOICE/cinnamon" ] || [ -d "$base/$CHOICE/metacity-1" ]; } \
            && SHELL_NAME="$CHOICE"
        break
    fi
done
if [ -n "$SHELL_NAME" ]; then
    gsettings set org.cinnamon.theme name "$SHELL_NAME" 2>/dev/null
    gsettings set org.cinnamon.desktop.wm.preferences theme "$SHELL_NAME" 2>/dev/null
fi

notify-send "Theme applied" "$CHOICE" 2>/dev/null || true
EOF
chmod +x "$PICKER"
log_ok "Theme picker installed at $PICKER"
if [ "$HAVE_SESSION" -eq 1 ] && cinnamon_custom_binding "Theme Picker" "$PICKER" "<Primary><Super>t"; then
    log_ok "Ctrl+Super+T now opens the theme picker."
fi

# ---------------------------------------------------------------------------
# 6. Apps that carry the palette — installed here so the apply step below
#    never has to guess whether its target is present.
# ---------------------------------------------------------------------------
install_pkgs "Themed apps" gnome-terminal btop bat eza starship fastfetch imagemagick
if command_exists batcat && ! command_exists bat; then
    ln -sf "$(command -v batcat)" "$BIN_DIR/bat"
    log_ok "Symlinked batcat -> ~/.local/bin/bat"
fi

# ---------------------------------------------------------------------------
# 7. Desktop shell — Catppuccin Mocha-Red chrome by default, else the dark
#    base theme; prefer-dark + Papirus-Dark icons to carry the look.
#    GTK and the Cinnamon shell/WM keys are resolved separately: pushing a
#    non-shell theme into org.cinnamon.theme / wm.preferences renders the
#    default *white* window borders (what the missing -Light theme caused).
# ---------------------------------------------------------------------------
PICKED_GTK=""
PICKED_SHELL=""
if [ -n "$CATTUCCINO_GTK" ]; then
    PICKED_GTK="$CATTUCCINO_GTK"
elif [ "$HAVE_SESSION" -eq 1 ]; then
    # No Catppuccin chrome — respect a manually chosen theme on re-runs.
    CURRENT_GTK=$(user_gsettings get org.cinnamon.desktop.interface gtk-theme 2>/dev/null | tr -d "'")
    if [ -n "$CURRENT_GTK" ] && { [ -d "$THEMES_DIR/$CURRENT_GTK" ] || [ -d "/usr/share/themes/$CURRENT_GTK" ]; }; then
        PICKED_GTK="$CURRENT_GTK"
    fi
else
    PICKED_GTK="Mint-Y-Dark"
fi

# The Cinnamon shell + window-borders keys only accept shell-capable themes
# (a cinnamon/ or metacity-1/ dir). Everything else stays as the user had it.
if [ -n "$PICKED_GTK" ]; then
    for CONF in "$THEMES_DIR/$PICKED_GTK" "/usr/share/themes/$PICKED_GTK"; do
        if [ -d "$CONF" ]; then
            if [ -d "$CONF/cinnamon" ] || [ -d "$CONF/metacity-1" ]; then
                PICKED_SHELL="${CONF##*/}"
            fi
            break
        fi
    done
fi

if [ -n "$PICKED_GTK" ] && [ "$HAVE_SESSION" -eq 1 ]; then
    user_gsettings set org.cinnamon.desktop.interface gtk-theme "$PICKED_GTK" >/dev/null 2>&1
    if [ -n "$PICKED_SHELL" ]; then
        user_gsettings set org.cinnamon.theme name "$PICKED_SHELL" >/dev/null 2>&1
        user_gsettings set org.cinnamon.desktop.wm.preferences theme "$PICKED_SHELL" >/dev/null 2>&1
    else
        log_warn "'$PICKED_GTK' can't drive the Cinnamon shell — leaving shell + window borders untouched."
    fi
    user_gsettings set org.cinnamon.desktop.interface color-scheme "prefer-dark" >/dev/null 2>&1
    user_gsettings set org.gnome.desktop.interface color-scheme "prefer-dark" >/dev/null 2>&1 || true
    user_gsettings set org.x.apps.portal color-scheme "prefer-dark" >/dev/null 2>&1 || true
    if [ -n "$PICKED_SHELL" ]; then
        log_ok "Applied $PICKED_GTK (GTK + chrome + window borders) + prefer-dark to the desktop."
    else
        log_ok "Applied $PICKED_GTK (GTK only) + prefer-dark to the desktop."
    fi

    if [ -d /usr/share/icons/Papirus-Dark ]; then
        user_gsettings set org.cinnamon.desktop.interface icon-theme "Papirus-Dark" >/dev/null 2>&1 \
            && log_ok "Icon theme set to Papirus-Dark."
    elif is_installed mint-y-icons; then
        user_gsettings set org.cinnamon.desktop.interface icon-theme "Mint-Y" >/dev/null 2>&1 \
            && log_ok "Icon theme set to Mint-Y."
    fi

    if [ -n "$CURSOR_THEME" ]; then
        user_gsettings set org.cinnamon.desktop.interface cursor-theme "$CURSOR_THEME" >/dev/null 2>&1 \
            && log_ok "Cursor theme set to $CURSOR_THEME."
    fi
else
    log_warn "No active Cinnamon session — re-run once logged in to apply the desktop theme."
fi

# ---------------------------------------------------------------------------
# 8. Wallpaper — locally generated gradient in the palette's colors, then
#    applied (sets org.gnome too so portals/GNOME apps agree).
# ---------------------------------------------------------------------------
WALLPAPER_PATH="$HOME/.local/share/backgrounds/devuan-cinnamon-catppuccin-mocha.png"
if ! command_exists convert; then
    log_warn "ImageMagick unavailable — skipping wallpaper generation."
    WALLPAPER_PATH=""
elif ! convert -size 1920x1080 gradient:'#101019'-'#1e1e2e' \
    \( -size 1920x1080 xc:none -fill '#f38ba8' -draw "circle 1700,700 2000,1100" -blur 0x260 \) \
    -compose over -composite "$WALLPAPER_PATH" 2>/dev/null; then
    log_warn "ImageMagick composite failed — skipping wallpaper (cosmetic only)."
    WALLPAPER_PATH=""
else
    log_ok "Wallpaper generated at $WALLPAPER_PATH"
    if [ "$HAVE_SESSION" -eq 1 ]; then
        user_gsettings set org.cinnamon.desktop.background picture-uri "file://$WALLPAPER_PATH" >/dev/null 2>&1
        user_gsettings set org.gnome.desktop.background picture-uri "file://$WALLPAPER_PATH" >/dev/null 2>&1
        log_ok "Wallpaper applied."
    fi
fi

# ---------------------------------------------------------------------------
# 9. Palette-driven app themes — the core deliverable. Each config is only
#    written if the app is installed, with a timestamped .bak first.
# ---------------------------------------------------------------------------
if command_exists gnome-terminal; then
    apply_gnome_terminal "$THEME_PALETTE"
fi
if command_exists btop; then
    apply_btop "$SCRIPT_DIR/../config/templates/btop.theme.tpl"
fi
if command_exists bat || command_exists batcat; then
    apply_bat "$SCRIPT_DIR/../config/bat/themes/Catppuccin Mocha.tmTheme"
fi
if command_exists eza; then
    apply_eza "$SCRIPT_DIR/../config/eza/theme.yml"
fi
if command_exists starship; then
    apply_starship "$SCRIPT_DIR/../config/templates/starship.toml.tpl"
fi
if command_exists fastfetch; then
    apply_fastfetch "$SCRIPT_DIR/../config/templates/fastfetch.config.tpl"
fi
apply_vscodium_catppuccin

# ---------------------------------------------------------------------------
# 10. Persist palette + picker colors for the update GUI / menu (ohmydebn's
#     ~/.config/ohmydebn/current layout, under ~/.config/devuan-cinnamon).
# ---------------------------------------------------------------------------
CURRENT_DIR="$HOME/.config/devuan-cinnamon/current"
mkdir -p "$CURRENT_DIR"
cp "$THEME_PALETTE" "$CURRENT_DIR/theme-catppuccin-mocha.toml"

BG=$(grep -E '^\s*background\s*=' "$THEME_PALETTE" | head -1 | sed -E 's/.*=\s*"([^"]+)".*/\1/')
ACCENT=$(grep -E '^\s*accent\s*=' "$THEME_PALETTE" | head -1 | sed -E 's/.*=\s*"([^"]+)".*/\1/')
FG=$(grep -E '^\s*foreground\s*=' "$THEME_PALETTE" | head -1 | sed -E 's/.*=\s*"([^"]+)".*/\1/')
cat > "$CURRENT_DIR/picker.colors" << PCEOF
bg0=${BG}F2
bg1=${BG}
bg3=${ACCENT}F2
fg0=${FG}
PCEOF
log_ok "Palette + picker colors saved under ~/.config/devuan-cinnamon/current."

echo -e "${GREEN}04 Theme complete.${NC}"
if [ "$HAVE_SESSION" -eq 0 ]; then
    log_warn "No active Cinnamon session — desktop theme/wallpaper were skipped. Re-run once logged in."
fi
log_warn "Open a new terminal / 'source ~/.bashrc' to see the new colors and prompt."