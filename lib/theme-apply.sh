#!/usr/bin/env bash
# =======================================================
# lib/theme-apply.sh - bash helpers for the Graphite Amber theme system
# -------------------------------------------------------
# Source this from scripts/04-theme.sh (and 06-cliStack.sh for fastfetch):
#   source "$SCRIPT_DIR/../lib/theme-apply.sh"
#
# Provides:
#   - THEME_PALETTE  path to the canonical palette TOML
#   - theme_export_palette              -> exports DCS_THEME_* shell vars
#   - theme_render <template> <output>  -> renders {{ key }} template to file
#   - apply_gnome_terminal              -> Graphite Amber profile in gnome-terminal
#   - apply_btop <palette> <tpl>        -> write ~/.config/btop/themes/graphite-amber.theme
#   - apply_bat <theme_tmtheme>         -> install bat Graphite Amber theme
#   - apply_eza <theme_yml>             -> symlink eza theme
#   - apply_starship <palette> <tpl>    -> write ~/.config/starship.toml
#   - apply_fastfetch <palette> <tpl>   -> write ~/.config/fastfetch/config.jsonc
#   - apply_vscodium_graphite_amber     -> Graphite Amber theme + settings for VSCodium
#   - _backup <file>                    -> timestamped backup if file exists
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
# App-specific apply functions - each writes to ~/.config/ in a safe,
# idempotent way, backs up before clobbering.
# ---------------------------------------------------------------------------

apply_gnome_terminal() {
    # Themes the gnome-terminal profile with the Graphite Amber palette so the
    # default terminal keeps the themed look of the rest of the app layer.
    # Creates/reuses a "Graphite Amber" profile and sets it as default.
    local src_palette="${1:-$THEME_PALETTE}"
    if ! command_exists python3 || ! command_exists gsettings; then
        echo "[!] python3/gsettings unavailable - skipping gnome-terminal theme."
        return 0
    fi
    log_ok "Applying Graphite Amber to the gnome-terminal profile..."
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
    if nm == "Graphite Amber":
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

c = lambda name: colors.get(name, "#16181D")
palette = [
    c("background"), c("red"), c("green"), c("yellow"),
    c("blue"), c("magenta"), c("cyan"), c("foreground"),
    c("dark_foreground"), c("red"), c("green"), c("yellow"),
    c("blue"), c("magenta"), c("cyan"), c("bright_foreground"),
]
palette_str = "[" + ", ".join("'" + rgb(h) + "'" for h in palette) + "]"

sets = {
    "visible-name": "'Graphite Amber'",
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
print("[OK] gnome-terminal 'Graphite Amber' profile created and set as default.")
PYEOF
}

apply_btop() {
    local theme_dir="$HOME/.config/btop/themes"
    local theme_out="$theme_dir/graphite-amber.theme"
    local conf="$HOME/.config/btop/btop.conf"
    mkdir -p "$theme_dir"
    _backup "$theme_out"
    theme_render "$1" "$theme_out"
    # Set theme in btop.conf if present
    if [ -f "$conf" ]; then
        if grep -qE '^\s*color_theme\s*=' "$conf"; then
            _backup "$conf"
            sed -i 's|color_theme = ".*"|color_theme = "graphite-amber"|' "$conf"
        fi
    fi
    echo "[OK] btop Graphite Amber theme installed."
}

apply_bat() {
    local src="$1"
    local bat_themes="$HOME/.config/bat/themes"
    local bat_config="$HOME/.config/bat/config"
    mkdir -p "$bat_themes"
    _backup "$bat_themes/Graphite Amber.tmTheme"
    cp "$src" "$bat_themes/Graphite Amber.tmTheme"
    # Rebuild bat cache
    command_exists bat && bat cache --build >/dev/null 2>&1
    # Set theme in bat config
    if [ -f "$bat_config" ]; then
        if ! grep -qF 'Graphite Amber' "$bat_config"; then
            _backup "$bat_config"
            # Append --theme if not present, or replace existing --theme line
            if grep -qE '^\s*--theme\s*=' "$bat_config"; then
                sed -i 's|--theme=".*"|--theme="Graphite Amber"|' "$bat_config"
            else
                echo '--theme="Graphite Amber"' >> "$bat_config"
            fi
        fi
    else
        echo '--theme="Graphite Amber"' > "$bat_config"
    fi
    echo "[OK] bat Graphite Amber theme installed."
}

apply_eza() {
    local src="$1"
    local out="$HOME/.config/eza/theme.yml"
    mkdir -p "$HOME/.config/eza"
    _backup "$out"
    cp "$src" "$out"
    echo "[OK] eza Graphite Amber theme installed."
}

apply_starship() {
    local out="$HOME/.config/starship.toml"
    mkdir -p "$HOME/.config"
    _backup "$out"
    theme_render "$1" "$out"
    echo "[OK] starship Graphite Amber config written to $out"
}

apply_fastfetch() {
    local out="$HOME/.config/fastfetch/config.jsonc"
    mkdir -p "$HOME/.config/fastfetch"
    _backup "$out"
    theme_render "$1" "$out"
    echo "[OK] fastfetch Graphite Amber config written to $out"
}

apply_vscodium_graphite_amber() {
    if ! command_exists codium; then
        echo "[!] VSCodium not installed yet (06-cliStack installs it) - skipping VSCodium theme."
        return 0
    fi
    local settings="$HOME/.config/VSCodium/User/settings.json"
    mkdir -p "$(dirname "$settings")"

    # Built-in dark base + colorCustomizations; no extension install needed.
    if [ -f "$settings" ] && grep -q '"terminal.ansiYellow": "#E8A33D"' "$settings"; then
        echo "[OK] VSCodium already themed (Graphite Amber)."
        return 0
    fi
    _backup "$settings"

    cat > "$settings" << 'VSEOF'
{
    "workbench.colorTheme": "Default Dark Modern",
    "workbench.preferredDarkColorTheme": "Default Dark Modern",
    "workbench.iconTheme": "vs-seti",
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
        "editor.background": "#16181D",
        "editor.foreground": "#D8D3C8",
        "editorLine.foreground": "#30343B",
        "editor.selectionBackground": "#30343B",
        "editorCursor.foreground": "#E8A33D",
        "editorGutter.background": "#16181D",
        "sideBar.background": "#202329",
        "sideBar.foreground": "#D8D3C8",
        "panel.background": "#202329",
        "panel.foreground": "#D8D3C8",
        "titleBar.activeBackground": "#202329",
        "titleBar.activeForeground": "#D8D3C8",
        "statusBar.background": "#16181D",
        "statusBar.foreground": "#D8D3C8",
        "focusBorder": "#E8A33D",
        "terminal.background": "#16181D",
        "terminal.foreground": "#D8D3C8",
        "terminal.ansiBlack": "#30343B",
        "terminal.ansiRed": "#C97064",
        "terminal.ansiGreen": "#8FB57A",
        "terminal.ansiYellow": "#E8A33D",
        "terminal.ansiBlue": "#7E9DB5",
        "terminal.ansiMagenta": "#A78BB5",
        "terminal.ansiCyan": "#79A9A6",
        "terminal.ansiWhite": "#D8D3C8",
        "terminal.ansiBrightBlack": "#9A9AA2",
        "terminal.ansiBrightRed": "#C97064",
        "terminal.ansiBrightGreen": "#8FB57A",
        "terminal.ansiBrightYellow": "#D2992F",
        "terminal.ansiBrightBlue": "#7E9DB5",
        "terminal.ansiBrightMagenta": "#A78BB5",
        "terminal.ansiBrightCyan": "#79A9A6",
        "terminal.ansiBrightWhite": "#D8D3C8"
    }
}
VSEOF
    echo "[OK] VSCodium themed with Graphite Amber."
}
