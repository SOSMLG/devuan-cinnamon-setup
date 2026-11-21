#!/usr/bin/env bash
# =======================================================
# 06 CLI Stack - fonts, ButterBash, zsh power shell, fastfetch
# -------------------------------------------------------
# Merges the old terminalButterbash.sh / installFonts.sh /
# zshPowerUser.sh / fastfetchConfig.sh / (useful bits of)
# devToolsExtras.sh:
#   * ButterBash (bundled locally under ../butterbash - works offline)
#   * Fonts: Noto (Latin+Arabic+Emoji), Font Awesome, JetBrainsMono Nerd
#     Font (latest GitHub release) + fontconfig prefs + the Inter UI font
#     applied as Cinnamon's desktop font
#   * zsh + Oh My Zsh + autosuggestions + syntax-highlighting, a starship
#     prompt, eza/zoxide/bat/btop/fzf/fd/lazygit/gum/grc/yq/jq, and
#     gnome-terminal as THE default terminal (system alternative + Cinnamon
#     keys + Graphite Amber profile; Alacritty, if present, is purged)
#   * Dev extras: btop, eza, bat, zoxide, KeePassXC (no heavier stack;
#     Neovim/LazyVim and VSCodium are intentionally not bundled here)
#   * fastfetch + curated presets (Graphite Amber config applied)
# =======================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=lib/theme-apply.sh
source "$SCRIPT_DIR/../lib/theme-apply.sh" || { log_err "theme-apply.sh missing - aborting."; exit 1; }

require_not_root
log_head "06 CLI Stack"

THEME_PALETTE="$SCRIPT_DIR/../config/palette/graphite-amber.toml"
HAVE_SESSION=0
command_exists gsettings && [ -n "${DISPLAY:-}" ] && HAVE_SESSION=1
BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"

apt_update

# ---------------------------------------------------------------------------
# 1. ButterBash - bundled so it works offline / without relying on the
#    upstream repo still existing.
# ---------------------------------------------------------------------------
BUTTERBASH_SRC="$SCRIPT_DIR/../butterbash"
if [ ! -d "$BUTTERBASH_SRC" ] || [ ! -f "$BUTTERBASH_SRC/install.sh" ]; then
    log_warn "Bundled ButterBash not found at $BUTTERBASH_SRC - skipping."
else
    log_info "Installing ButterBash from $BUTTERBASH_SRC ..."
    if ( cd "$BUTTERBASH_SRC" && bash install.sh --yes ); then
        log_ok "ButterBash installed."
        log_info "Run 'source ~/.bashrc' or open a new terminal to use it."
    else
        log_warn "ButterBash installation failed - continuing."
    fi
fi

# ---------------------------------------------------------------------------
# 2. Fonts - Noto + Font Awesome via apt, JetBrainsMono Nerd Font from the
#    latest GitHub release, plus fontconfig rendering prefs.
# ---------------------------------------------------------------------------
apt_update
install_pkgs "Fonts (Noto + Font Awesome)" \
    curl fonts-font-awesome fonts-noto-core fonts-noto-unhinted \
    fonts-noto-color-emoji fonts-noto-mono

NERD_FONT_DIR="$HOME/.local/share/fonts/NerdFonts"
mkdir -p "$NERD_FONT_DIR"
if fc-list | grep -qi "JetBrainsMono Nerd Font"; then
    log_ok "JetBrainsMono Nerd Font already installed - skipping download."
else
    log_info "Fetching the latest JetBrainsMono Nerd Font release... "
    DOWNLOAD_URL=$(curl -fsSL https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest \
        | grep -oP '"browser_download_url": "\K[^"]+' \
        | grep -i "JetBrainsMono.*tar\.xz" \
        | head -1)
    if [ -z "$DOWNLOAD_URL" ]; then
        log_warn "GitHub API failed - using pinned fallback URL."
        DOWNLOAD_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/JetBrainsMono.tar.xz"
    fi

    WORK_DIR=$(mktemp -d)
    trap 'rm -rf "$WORK_DIR"' EXIT
    if curl -fsSL -o "$WORK_DIR/JetBrainsMono.tar.xz" "$DOWNLOAD_URL" \
        && (tar -xf "$WORK_DIR/JetBrainsMono.tar.xz" -C "$NERD_FONT_DIR" --wildcards '*.ttf' 2>/dev/null \
            || tar -xf "$WORK_DIR/JetBrainsMono.tar.xz" -C "$NERD_FONT_DIR"); then
        log_ok "JetBrainsMono Nerd Font installed to $NERD_FONT_DIR."
    else
        log_warn "JetBrainsMono download/extract failed - continuing without it."
    fi
    rm -rf "$WORK_DIR"
    trap - EXIT
fi

FONTCONF_DIR="$HOME/.config/fontconfig"
mkdir -p "$FONTCONF_DIR"
cat > "$FONTCONF_DIR/fonts.conf" << 'EOF'
<?xml version='1.0'?>
<!DOCTYPE fontconfig SYSTEM 'fonts.dtd'>
<fontconfig>

  <!-- Monospace: Prefer JetBrainsMono Nerd Font, fallback to Noto Mono -->
  <alias>
    <family>monospace</family>
    <prefer>
      <family>JetBrainsMono Nerd Font Mono</family>
      <family>Noto Sans Mono</family>
      <family>DejaVu Sans Mono</family>
    </prefer>
  </alias>

  <!-- Sans-serif: Noto Sans + Arabic -->
  <alias>
    <family>sans-serif</family>
    <prefer>
      <family>Noto Sans</family>
      <family>Noto Sans Arabic</family>
      <family>Noto Color Emoji</family>
    </prefer>
  </alias>

  <!-- Serif: Noto Serif -->
  <alias>
    <family>serif</family>
    <prefer>
      <family>Noto Serif</family>
      <family>Noto Serif Arabic</family>
    </prefer>
  </alias>

  <!-- Emoji: Always use color emoji -->
  <match target="pattern">
    <test name="family"><string>emoji</string></test>
    <edit name="family" mode="assign" binding="same">
      <string>Noto Color Emoji</string>
    </edit>
  </match>

  <!-- Rendering: Subpixel hinting for LCD screens -->
  <match target="font">
    <edit name="antialias"  mode="assign"><bool>true</bool></edit>
    <edit name="hinting"    mode="assign"><bool>true</bool></edit>
    <edit name="hintstyle"  mode="assign"><const>hintslight</const></edit>
    <edit name="rgba"       mode="assign"><const>rgb</const></edit>
    <edit name="lcdfilter"  mode="assign"><const>lcddefault</const></edit>
  </match>

</fontconfig>
EOF
log_ok "fontconfig prefs written (JetBrainsMono for monospace, Noto for text)."
fc-cache -f >/dev/null 2>&1

# ---------------------------------------------------------------------------
# 3. Inter UI font + apply it as Cinnamon's desktop font (the "video" look)
# ---------------------------------------------------------------------------
FONT_DIR="$HOME/.local/share/fonts"
mkdir -p "$FONT_DIR"
if [ ! -f "$FONT_DIR/Inter.ttf" ]; then
    API_URL="https://api.github.com/repos/google/fonts/contents/ofl/inter"
    DL_URL=$(curl -fsSL "$API_URL" 2>/dev/null | python3 -c '
import json, sys
try:
    entries = json.load(sys.stdin)
    for e in entries:
        if e.get("name") == "Inter[opsz,wght].ttf":
            print(e["download_url"]); break
except Exception:
    pass
' 2>/dev/null)
    if [ -n "$DL_URL" ] && curl -fsSL -o "$FONT_DIR/Inter.ttf" "$DL_URL"; then
        fc-cache -f "$FONT_DIR" >/dev/null 2>&1
        log_ok "Inter installed to $FONT_DIR."
    else
        log_warn "Could not fetch Inter - skipping font install."
    fi
fi
if [ -f "$FONT_DIR/Inter.ttf" ] && [ "$HAVE_SESSION" -eq 1 ]; then
    user_gsettings set org.cinnamon.desktop.interface font-name "Inter 10"
    user_gsettings set org.cinnamon.desktop.interface document-font-name "Inter 10"
    user_gsettings set org.cinnamon.desktop.wm.preferences titlebar-font "Inter Bold 10"
    log_ok "Inter applied as desktop/document/titlebar font."
fi

# ---------------------------------------------------------------------------
# 4. Dev extras - btop, eza, bat, zoxide, KeePassXC (+ fd alias so tools
#    like Telescope/justaguy configs find it).
# ---------------------------------------------------------------------------
install_pkgs "Dev extras" btop eza bat zoxide keepassxc fd-find ripgrep fzf lazygit gum grc yq jq duf
if command_exists batcat && ! command_exists bat; then
    ln -sf "$(command -v batcat)" "$BIN_DIR/bat"
fi
if command_exists fdfind && ! command_exists fd; then
    ln -sf "$(command -v fdfind)" "$BIN_DIR/fd"
fi
log_ok "Dev extras installed."

# ---------------------------------------------------------------------------
# 5. Bash power-user stack - starship-prompt bash (no zsh; ButterBash is
#    already bash-native). Brings in VSCodium (VSCode-minus-telemetry) with a
#    full C++/Python toolchain + Graphite Amber, wired to Nemo/terminal.
# ---------------------------------------------------------------------------

# 5a. VSCodium - telemetry-free VSCode (official APT repo so it stays updated).
install_vscodium_apt

# 5b. Dev toolchain for C++ (clangd) and Python (Pylance-free: basedpyright).
vscodium_dev_toolchain

# 5c. VSCodium extensions (clangd/CodeLLDB/cmake + python/debugpy/basedpyright/ruff).
vscodium_install_extensions

# 5d. Starter project (C++ CMake + Python venv) + open-in-terminal helpers.
vscodium_starter_project

# 5e. Graphite Amber theme for VSCodium (built-in dark base + colorCustomizations).
apply_vscodium_graphite_amber

# 5f. Nemo "Open in VSCodium" action post-install (idempotent).
nemo_add_vscode_action

# 6. fastfetch - system info on terminal open, with curated presets
# ---------------------------------------------------------------------------
install_pkgs "fastfetch" fastfetch
FF_DIR="$HOME/.config/fastfetch"
mkdir -p "$FF_DIR"
BASE_URL="https://codeberg.org/justaguylinux/butterscripts/raw/branch/main/fastfetch"
if command_exists wget; then
    for f in config.jsonc minimal.jsonc fancy.jsonc neon.jsonc debian-red.jsonc justaguy.jsonc server.jsonc; do
        wget -q "$BASE_URL/$f" -O "$FF_DIR/$f" >/dev/null 2>&1 \
            && log_info "  fetched $f" \
            || log_warn "  failed to fetch $f"
    done
    for img in debian_swirl.png justaguylinux.png; do
        wget -q "$BASE_URL/$img" -O "$FF_DIR/$img" >/dev/null 2>&1 || log_warn "  failed to fetch $img"
    done
    if [ -f "$FF_DIR/neon.jsonc" ]; then
        cp "$FF_DIR/neon.jsonc" "$FF_DIR/config.jsonc"
        log_ok "fastfetch presets installed (Graphite Amber config applied below)."
    fi
else
    log_warn "wget not installed - skipping fastfetch presets (fastfetch binary still works with defaults)."
fi
# 04-theme's apply_fastfetch may not have been called if fastfetch lagged,
# so honor the palette here if the template-driven config exists.
if command_exists fastfetch && [ -f "$THEME_PALETTE" ]; then
    apply_fastfetch "$SCRIPT_DIR/../config/templates/fastfetch.config.tpl"
fi

echo -e "${GREEN}06 CLI Stack complete.${NC}"
log_warn "Log out and back in (or open a fresh zsh) to pick up the new shell + prompt."
log_warn "fastfetch presets: cp ~/.config/fastfetch/<name>.jsonc ~/.config/fastfetch/config.jsonc to switch."