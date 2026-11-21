#!/usr/bin/env python3
"""
lib/theme_render.py - read a semantic Graphite Amber palette TOML,
derive ANSI color0-15 + cursor + selection + accent_ansi aliases, then
render {{ key }} templates.

Usage:
    python3 lib/theme_render.py palette.toml template.tpl > output
    python3 lib/theme_render.py palette.toml --export  # shell KEY=VALUE lines

Ported from ohmydebn's ohmydebn-theme-set-colors + ohmydebn-theme-set-templates
(https://github.com/dougburks/ohmydebn, MIT licensed), simplified for this toolkit.
"""

import re, sys, pathlib


def _parse_toml(text: str) -> dict[str, str]:
    d: dict[str, str] = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        m = re.match(r'(\w+)\s*=\s*"([^"]*)"', line)
        if m:
            d[m.group(1)] = m.group(2)
    return d


def _hex_to_rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


def _derive(pal: dict[str, str]) -> dict[str, str]:
    """Add legacy ANSI color0-15, cursor, selection, accent_ansi, rgb, ansi."""
    out = dict(pal)  # keep semantic keys too
    fg = pal.get("foreground", "#D8D3C8")
    bf = pal.get("bright_foreground", fg)
    muted = pal.get("muted", pal.get("dark_foreground", fg))
    sel = pal.get("selection", muted)
    accent = pal.get("accent", pal.get("blue", fg))
    bg = pal.get("background", "#000000")

    # ANSI colorN map (Graphite Amber semantic mapping)
    out["color0"] = bg
    out["color1"] = pal.get("red", fg)
    out["color2"] = pal.get("green", fg)
    out["color3"] = pal.get("yellow", fg)
    out["color4"] = pal.get("blue", fg)
    out["color5"] = pal.get("magenta", fg)
    out["color6"] = pal.get("cyan", fg)
    out["color7"] = fg
    out["color8"] = muted
    out["color9"] = pal.get("bright_red", out["color1"])
    out["color10"] = pal.get("bright_green", out["color2"])
    out["color11"] = pal.get("bright_yellow", out["color3"])
    out["color12"] = pal.get("bright_blue", out["color4"])
    out["color13"] = pal.get("bright_magenta", out["color5"])
    out["color14"] = pal.get("bright_cyan", out["color6"])
    out["color15"] = bf
    out["cursor"] = bf
    out["selection_foreground"] = bf
    out["selection_background"] = sel
    out["accent"] = accent

    # Derived forms
    for k in list(out):
        v = out[k]
        if v.startswith("#") and len(v) == 7:
            r, g, b = _hex_to_rgb(v)
            out[f"{k}_strip"] = v[1:]
            out[f"{k}_rgb"] = f"{r},{g},{b}"
            out[f"{k}_ansi"] = f"38;2;{r};{g};{b}"
            out[f"{k}_bg_ansi"] = f"48;2;{r};{g};{b}"
    return out


def render(template: str, values: dict[str, str]) -> str:
    def repl(m: re.Match) -> str:
        key = m.group(1).strip()
        return values.get(key, m.group(0))
    return re.sub(r'\{\{\s*(\w+)\s*\}\}', repl, template)


def export_shell(pal: dict[str, str]) -> None:
    for k, v in sorted(pal.items()):
        # shell-safe: single-quote single quotes
        sv = v.replace("'", "'\\''")
        print(f"DCS_THEME_{k}='{sv}'")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: theme_render.py <palette.toml> <template.tpl> | --export", file=sys.stderr)
        sys.exit(1)
    pal = _parse_toml(pathlib.Path(sys.argv[1]).read_text())
    derived = _derive(pal)
    if sys.argv[2] == "--export":
        export_shell(derived)
    else:
        tpl = pathlib.Path(sys.argv[2]).read_text()
        sys.stdout.write(render(tpl, derived))