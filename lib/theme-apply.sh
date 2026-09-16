#!/usr/bin/env bash
# =======================================================
# lib/theme-apply.sh — bash helpers for the Catppuccin theme system
# -------------------------------------------------------
# Source this from scripts/04-theme.sh (and 06-cliStack.sh for fastfetch):
#   source "$SCRIPT_DIR/../lib/theme-apply.sh"
#
# Provides:
#   - THEME_PALETTE  path to the canonical palette TOML
#   - theme_export_palette              → exports DCS_THEME_* shell vars
#   - theme_render <template> <output>  → renders {{ key }} template to file
#   - apply_gnome_terminal              → Catppuccin profile in gnome-terminal
#   - apply_btop <palette> <tpl>        → write ~/.config/btop/themes/catppuccin-mocha.theme
#   - apply_bat <theme_tmtheme>         → install bat Catppuccin Mocha theme
#   - apply_eza <theme_yml>             → symlink eza theme
#   - apply_starship <palette> <tpl>    → write ~/.config/starship.toml
#   - apply_fastfetch <palette> <tpl>   → write ~/.config/fastfetch/config.jsonc
#   - apply_vscodium_catppuccin         → Catppuccin Mocha theme + settings for VSCodium
#   - _backup <file>                    → timestamped backup if file exists
# =======================================================
if [ -n "${DCS_THEME_APPLY_LOADED:-}" ]; then return 0 2>/dev/null || exit 0; fi
DCS_THEME_APPLY_LOADED=1

RENDER="$SCRIPT_DIR/../lib/theme_render.py"

if ! command_exists python3; then
    echo "[!] python3 is required by theme-apply.sh" >&2
    exit 1
fi

_backup() {
    local f="$1"
    if [ -f "$f" ]; then
        cp "$f" "${f}.bak.$(date +%Y%m%d_%H%M%S)"
    fi
}

theme_export_palette() {
    # Exports DCS_THEME_* vars into the current shell from the palette TOML.
    # Requires THEME_PALETTE to be set.
    eval "$(python3 "$RENDER" "$THEME_PALETTE" --export)"
}

theme_render() {
    # $1 = template path, $2 = output path
    python3 "$RENDER" "$THEME_PALETTE" "$1" > "$2"
}

# ---------------------------------------------------------------------------
# App-specific apply functions — each writes to ~/.config/ in a safe,
# idempotent way, backs up before clobbering.
# ---------------------------------------------------------------------------

apply_gnome_terminal() {
    # Themes the gnome-terminal profile with the Catppuccin palette so the
    # default terminal keeps the themed look of the rest of the app layer.
    # Creates/reuses a "Catppuccin Mocha" profile and sets it as default.
    local src_palette="${1:-$THEME_PALETTE}"
    if ! command_exists python3 || ! command_exists gsettings; then
        echo "[!] python3/gsettings unavailable — skipping gnome-terminal theme."
        return 0
    fi
    log_ok "Applying Catppuccin Mocha to the gnome-terminal profile..."
    python3 - "$src_palette" << 'PYEOF'
import os, re, subprocess, sys, uuid

palette_path = sys.argv[1]
colors = {}
try:
    for line in open(palette_path, encoding="utf-8"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        m = re.match(r'(\w+)\s*=\s*"([^"]*)"', line)
        if m and len(m.group(2)) == 7 and m.group(2).startswith("#"):
            colors[m.group(1)] = m.group(2)
except OSError:
    sys.exit(0)

def run(args):
    subprocess.run(args, capture_output=True, text=True, check=False)

def gget(*a):
    out = subprocess.run(["gsettings", "get", *a], capture_output=True, text=True)
    return out.stdout.strip()

def gset(*a):
    subprocess.run(["gsettings", "set", *a], capture_output=True, text=True)

base = "org.gnome.Terminal.ProfilesList"
schema = "org.gnome.Terminal.Legacy.Profile"
uuids = gget(base, "list").strip("[]@'\" ").split(",")
profile_uuid = None
for u in uuids:
    u = u.strip().strip("'\"")
    if not u:
        continue
    nm = gget(f"{schema}:/org/gnome/terminal/legacy/profiles:/:{u}/", "visible-name").strip("'\"")
    if nm == "Catppuccin Mocha":
        profile_uuid = u
        break

if profile_uuid is None:
    profile_uuid = str(uuid.uuid4())
    current = gget(base, "list")
    # append to list; handle quoted-gvariant
    items = [i.strip().strip("'\"") for i in current.strip().strip("[]").split(",") if i.strip()]
    items.append(profile_uuid)
    new_list = "'" + "', '".join(items) + "'"
    run(["gsettings", "set", base, "list", f"[{new_list}]"])

path = f"/org/gnome/terminal/legacy/profiles:/:{profile_uuid}/"
def key(k):
    return f"{schema}:{path}".replace("::", ":")

def rgb(h):
    h = h.lstrip("#")
    return f"rgb({int(h[0:2],16)},{int(h[2:4],16)},{int(h[4:6],16)})"

c = lambda name: colors.get(name, "#1e1e2e")
palette = [
    c("background"), c("red"), c("green"), c("yellow"),
    c("blue"), c("magenta"), c("cyan"), c("foreground"),
    c("dark_foreground"), c("red"), c("green"), c("yellow"),
    c("blue"), c("magenta"), c("cyan"), c("bright_foreground"),
]
palette_str = "[" + ", ".join("'" + rgb(h) + "'" for h in palette) + "]"

sets = {
    "visible-name": "'Catppuccin Mocha'",
    "use-theme-colors": "false",
    "use-theme-transparency": "false",
    "use-transparent-background": "false",
    "background-color": f"'{rgb(c('background'))}'",
    "foreground-color": f"'{rgb(c('foreground'))}'",
    "bold-color": f"'{rgb(c('foreground'))}'",
    "bold-is-bright": "true",
    "palette": palette_str,
    "scrollback-lines": "10000",
}
# write via dconf path in one pass
for k, v in sets.items():
    run(["gsettings", "set", key(k), k, v])
run(["gsettings", "set", base, "default", f"'{profile_uuid}'"])
print("[OK] gnome-terminal 'Catppuccin Mocha' profile created and set as default.")
PYEOF
}

apply_btop() {
    local theme_dir="$HOME/.config/btop/themes"
    local theme_out="$theme_dir/catppuccin-mocha.theme"
    local conf="$HOME/.config/btop/btop.conf"
    mkdir -p "$theme_dir"
    _backup "$theme_out"
    theme_render "$1" "$theme_out"
    # Set theme in btop.conf if present
    if [ -f "$conf" ]; then
        if grep -qE '^\s*color_theme\s*=' "$conf"; then
            _backup "$conf"
            sed -i 's|color_theme = ".*"|color_theme = "catppuccin-mocha"|' "$conf"
        fi
    fi
    echo "[OK] btop Catppuccin Mocha theme installed."
}

apply_bat() {
    local src="$1"
    local bat_themes="$HOME/.config/bat/themes"
    local bat_config="$HOME/.config/bat/config"
    mkdir -p "$bat_themes"
    _backup "$bat_themes/Catppuccin Mocha.tmTheme"
    cp "$src" "$bat_themes/Catppuccin Mocha.tmTheme"
    # Rebuild bat cache
    command_exists bat && bat cache --build >/dev/null 2>&1
    # Set theme in bat config
    if [ -f "$bat_config" ]; then
        if ! grep -qF 'Catppuccin Mocha' "$bat_config"; then
            _backup "$bat_config"
            # Append --theme if not present, or replace existing --theme line
            if grep -qE '^\s*--theme\s*=' "$bat_config"; then
                sed -i 's|--theme=".*"|--theme="Catppuccin Mocha"|' "$bat_config"
            else
                echo '--theme="Catppuccin Mocha"' >> "$bat_config"
            fi
        fi
    else
        echo '--theme="Catppuccin Mocha"' > "$bat_config"
    fi
    echo "[OK] bat Catppuccin Mocha theme installed."
}

apply_eza() {
    local src="$1"
    local out="$HOME/.config/eza/theme.yml"
    mkdir -p "$HOME/.config/eza"
    _backup "$out"
    cp "$src" "$out"
    echo "[OK] eza Catppuccin Mocha theme installed."
}

apply_starship() {
    local out="$HOME/.config/starship.toml"
    mkdir -p "$HOME/.config"
    _backup "$out"
    theme_render "$1" "$out"
    echo "[OK] starship Catppuccin config written to $out"
}

apply_fastfetch() {
    local out="$HOME/.config/fastfetch/config.jsonc"
    mkdir -p "$HOME/.config/fastfetch"
    _backup "$out"
    theme_render "$1" "$out"
    echo "[OK] fastfetch Catppuccin config written to $out"
}

apply_vscodium_catppuccin() {
    if ! command_exists codium; then
        echo "[!] VSCodium not installed yet (06-cliStack installs it) — skipping VSCodium theme."
        return 0
    fi
    local settings="$HOME/.config/VSCodium/User/settings.json"
    local ext_dir="$HOME/.vscode-oss/extensions"
    mkdir -p "$(dirname "$settings")"

    # Ensure the Catppuccin extension is present (VSCodium uses Open VSX)
    if command_exists codium && ! ls "$ext_dir" 2>/dev/null | grep -qi catppuccin; then
        codium --install-extension "Catppuccin.catppuccin-vsc" --force >/dev/null 2>&1             || echo "[!] Could not install Catppuccin extension (network?) — settings still written."
    fi

    if [ -f "$settings" ] && grep -q 'Catppuccin Mocha' "$settings"; then
        echo "[OK] VSCodium already themed (Catppuccin Mocha)."
        return 0
    fi
    _backup "$settings"

    cat > "$settings" << 'VSEOF'
{
    "workbench.colorTheme": "Catppuccin Mocha",
    "workbench.iconTheme": "catppuccin-mocha",
    "editor.fontFamily": "JetBrainsMono Nerd Font Mono, monospace",
    "editor.fontSize": 13,
    "editor.lineHeight": 1.6,
    "editor.stickyScroll.enabled": true,
    "editor.bracketPairColorization.enabled": true,
    "editor.guides.bracketPairs": true,
    "files.autoSave": "afterDelay",
    "files.autoSaveDelay": 1000,
    "terminal.integrated.fontFamily": "JetBrainsMono Nerd Font Mono",
    "window.titleBarStyle": "custom",
    "window.commandCenter": true,
    "workbench.colorCustomizations": {
        "terminal.background": "#1e1e2e",
        "terminal.foreground": "#cdd6f4",
        "terminal.ansiBlack": "#45475a",
        "terminal.ansiRed": "#f38ba8",
        "terminal.ansiGreen": "#a6e3a1",
        "terminal.ansiYellow": "#f9e2af",
        "terminal.ansiBlue": "#89b4fa",
        "terminal.ansiMagenta": "#f5c2e7",
        "terminal.ansiCyan": "#94e2d5",
        "terminal.ansiWhite": "#bac2de",
        "terminal.ansiBrightBlack": "#585b70",
        "terminal.ansiBrightRed": "#f38ba8",
        "terminal.ansiBrightGreen": "#a6e3a1",
        "terminal.ansiBrightYellow": "#f9e2af",
        "terminal.ansiBrightBlue": "#89b4fa",
        "terminal.ansiBrightMagenta": "#f5c2e7",
        "terminal.ansiBrightCyan": "#94e2d5",
        "terminal.ansiBrightWhite": "#a6adc8"
    }
}
VSEOF
    echo "[OK] VSCodium themed with Catppuccin Mocha."
}
