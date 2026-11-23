![banner](assets/banner.svg)

# devuan-cinnamon-setup

takes an existing devuan cinnamon desktop past stock defaults with a graphite amber identity, a searchable launcher, hardened firefox esr and terminal ai agents, all on openrc.

[read the run steps](#quick-start)

| | |
| --- | --- |
| **steps** | ten numbered steps replace the old 33 per-feature scripts. each still runs standalone. |
| **runner** | `./install.sh` runs all ten unattended. `./install.sh` asks before each step. |
| **theme** | gtk apps, terminal and update window share one graphite amber palette. |
| **init** | native to openrc. no systemctl in the tree. |

## Quick start

```bash
cd devuan-cinnamon-setup
bash install.sh          # everything, fully unattended (runs a verify pass at the end)
bash install.sh --no-verify  # skip the end-state audit
# or the runner directly:
bash install.sh              # run all 10 steps (deterministic, no prompts)
bash install.sh --list       # show the ordered steps
bash install.sh --only 05    # run a single script by number
bash install.sh --no-update  # skip the apt-get update up front
bash install.sh --verify     # run scripts/verifySetup.sh (end-state audit) afterwards
bash install.sh --backup     # snapshot current config via scripts/configBackup.sh first
```

Run as your **normal user**, never `/root` and never `sudo bash ...`.
Every step calls `sudo` itself for what needs it — Firefox's profile,
`~/.zshrc`, Cinnamon's dconf settings, and `~/.local/bin` all have to land
in *your* `$HOME`.

Anything can be run standalone and re-run safely — every step is
idempotent (checks what's actually installed before installing/purging,
backs up configs as `*.bak.<timestamp>` before writing).

## What each step does

**01 System Setup**  — apt update + `full-upgrade` + autoremove; adds you
to `input`/`video`/`render`; weekly `fstrim` via cron (init-agnostic where
`fstrim.timer` needs systemd); installs Timeshift (setup via its first-run
wizard — disk choices are yours). Skips the apt refresh if
`DEBSWAY_SKIP_APT_UPDATE=1` (set automatically after the first success).

**02 Debloat** — purges only what's actually installed: Warpinator (open
discovery port), HexChat, redundant GNOME apps (Weather/Maps/To Do/
Contacts/Clocks/Pix), bundled games, then autoremove/clean and disables
GNOME Tracker indexing (rein it in — Tracker is session/dbus, works the
same under OpenRC). **Cinnamon's desktop effects are left ON** — this
toolkit leans into snappiness (05 speeds them up), not off.

**03 Hardware & Codecs** — WiFi/Bluetooth non-free firmware, auto-detected
CPU microcode, fwupd (+`gnome-firmware` when available), ffmpeg + full
GStreamer set + `libdvd-pkg` (builds libdvdcss non-interactively under a
5-minute timeout), and the ThinkPad-class input fixes: `usbhid mousepoll=2`
+ a safe libinput Xorg snippet (tap-to-click on, natural scroll off).

**04 Theme** — Mint-Y icons from Debian's repo + Mint-Y theme built from
upstream source (no Mint repo is ever added), stock Adwaita cursor + Arc/Papirus/
Materia packs, and a `Ctrl+Super+T` theme-picker. Then the identity pass:
a stock dark GTK/Cinnamon base + `prefer-dark` (incl. portal keys),
Papirus-Dark icons, a locally generated graphite/amber gradient wallpaper,
and the **palette rendered into every themed app** (gnome-terminal, btop,
bat, eza, starship, fastfetch) from `config/palette/graphite-amber.toml` via
`lib/theme_render.py`. No third-party GTK theme is downloaded; the graphite
+ amber identity lives in the palette and app colorCustomizations. Persists
the palette + `picker.colors` for the update GUI and menu.

**05 Cinnamon Setup**  — verified Spices from the official
cinnamon-spices repos: Maximus (hide titlebar on maximize), Blur Cinnamon,
gTile (Super+G), Burn My Windows (Glide effect, minimize/tile disabled),
Color Picker applet, the weather + SpicesUpdate + transparency + quality-of-
life applets, plus built-in Workspace Switcher + grouped Window List
applets, Night
Light, Super+L lock, the custom hotkey set (Super+Return terminal, Super+F
Nemo, Ctrl+Super+E Xed, Ctrl+Shift+Escape monitor), and the polish pass:
sounds off, effect speed maxed, alt-tab icons+preview across workspaces,
ibus tray icon hidden, kernel-hardening module blacklists (algif_aead/
esp4/esp6/rxrpc). Ends with the Nemo right-click actions: Compress PDF,
Compress Image, Open in VS Code (only if `code`/`codium` exists), Open in
OpenCode.

**06 CLI Stack** — bundled ButterBash (works offline); fonts (Noto +
Font Awesome via apt, JetBrainsMono Nerd Font from the latest GitHub
release with a pinned fallback, fontconfig prefs, and the Inter UI font
applied as the desktop font); the power-user shell (zsh + Oh My Zsh +
autosuggestions + syntax-highlighting + starship, `chsh` to zsh,
gnome-terminal set as system + Cinnamon default terminal with the
Graphite Amber profile (Alacritty, if a previous run installed it, is
purged); dev extras (btop, eza, bat,
zoxide, KeePassXC — no Neovim/LazyVim, dropped as too-heavy); fastfetch +
curated presets.

**07 Apps** — Flatpak + Flathub + GNOME Software as the app center; CUPS
printing (+lpadmin rights); GParted; gufw firewall (installed but **not
enabled** — enable it yourself once you've confirmed it won't break
SSH/file sharing); VLC as the default media player; archive support +
thumbnailers for Nemo; qBittorrent; TLP (enabled via OpenRC); Vesktop
(Discord, latest GitHub .deb) + Telegram Desktop (official tar.xz into
`~/.local/opt`, no sudo).

**08 Firefox** — installs `firefox-esr`, fetches the pinned Betterfox
`user.js` (+ Linux additions: autofill-off, no geoclue geo, PDF fit width),
installs `policies.json` (telemetry/Pocket/sponsored off, uBlock Origin),
de-brands the .desktop, and drops a `~/.local/bin` wrapper that re-applies
the latest user.js on every launch. A separate `firefox` (latest) install,
if present, is hardened too. `BETTERFOX_TAG` overrides the pinned tag.

**09 Update System**  — a cron checker (09:00 + 18:00) that pops a
notification with a clickable **Update now** action (no systemd timers —
cron is init-agnostic; DISPLAY/DBus are auto-detected at run time), the
Graphite Amber themed GTK3 update window with an embedded VTE terminal that
runs the real `apt-get full-upgrade` (the pretty layer never performs the
update itself; the button stays busy until the pty exits and notifies on
completion), the **Devuan Menu** — a searchable, theme-aware power-user
launcher (Apps/AI/Terminals/Editors/Browsers/Update/System with OpenRC-safe
power helpers) bound to Super+M — and a **first-run wizard** that greets a
fresh install's user once, offering a first update + Timeshift setup
(`~/.local/bin/devuan-first-run`, done-file gated).

**10 AI Agents**  — [OpenCode](https://opencode.ai) (official installer,
npm fallback) and VSCodium (official APT repo — telemetry-free VS Code,
with a C++/Python toolchain + Graphite Amber theme) with their shells on
PATH, `Super+A` → open a terminal running OpenCode, and the system
skill file copied to `~/.config/opencode/AGENTS.md` + `~/AGENTS.md` so
either agent knows this is a Devuan/OpenRC/Cinnamon box. Run
`opencode auth login` once to connect a provider.

## Why OpenRC gets special treatment

`lib/common.sh` ships a real service abstraction — `service_enable_now`,
`service_start`, `service_restart` — that detects the init system
(`rc-service`+`rc-update`+`/etc/runlevels` → OpenRC; systemd → systemd;
else sysvinit/`service`) and dispatches accordingly. Every script that
touches a service (cron, CUPS, fwupd, TLP) goes through this, and no
script ever calls `systemctl` directly.

## Environment variables

| Variable | Effect |
|---|---|
| `DEBSWAY_ASSUME_YES=1` | auto-approve every `ask()` prompt (set by `install.sh`) |
| `DEBSWAY_SKIP_APT_UPDATE=1` | skip `apt-get update` (auto-set after the first success) |
| `CONFIG_BACKUP_DIR=/path` | where `scripts/configBackup.sh` writes its archive (default: `$HOME`) |
| `BETTERFOX_TAG=150.0` | pinned Betterfox tag used by 08 |

## Verification

```bash
bash scripts/verifySetup.sh
```

The verifier is read-only. It reports the expected packages, configs, services
and theme markers, and exits nonzero when a required item is missing.

## Notes

- Nothing auto-enables a firewall deny rule or adds a third-party APT repo.
- Boot-time "update everything freshly" is always `apt`-based (Devuan/
  Debian) — never `pacman`/`dnf`.
- Desktop-setting steps need an **active local Cinnamon session** to apply
  dconf changes — over SSH before your first graphical login they install
  packages fine but skip the "apply to my session" part. Re-run once
  logged in locally.
- Log out/in (or reboot) after a full run — groups, mousepoll, firmware,
  theme, and keybindings all benefit from a fresh session.

## Attribution

- Runner/script-structure pattern: DebianSway, via this author's own
  [Devuan-Kde](https://github.com/SOSMLG/Devuan-Kde).
- AI tooling, the update-window concept, the GTK picker styling, the menu,
  Cinnamon polish hints, and curated dev extras: adapted from
  [OhMyDebn](https://github.com/dougburks/ohmydebn) by Doug Burks (MIT
  licensed) — a systemd+Cinnamon "power user" desktop with AI, containers,
  and VMs built in; this toolkit borrows the parts that fit an OpenRC,
  lighter scope and leaves the rest out.
- Palette + bat/eza theme files: Graphite Amber, maintained locally for this
  toolkit (no third-party theme download).
- Mint-Y/Mint-X icons + mint-themes source: [Linux Mint](https://linuxmint.com/)
   [linuxmint on GitHub](https://github.com/linuxmint), packaged for Debian
  by the Debian Cinnamon Team.
- Cinnamon extensions/applets: from
  `linuxmint/cinnamon-spices-{extensions,applets}` — each written and
  maintained by its own author (klangman, fmete, shuairan).
- Inter: [The Inter Project](https://github.com/rsms/inter) (OFL-1.1).
- Betterfox: [yokoffing/Betterfox](https://github.com/yokoffing/Betterfox),
  via [harden_firefox.sh (Butterbian)](https://github.com/justaguylinux/butterscripts)
  and the tonybanters/tonarchy concept.
- ButterBash: bundled from its own upstream repo (see `butterbash/`).

---

## License

MIT. See [LICENSE](LICENSE). Vendored components keep their own license files.

## Related repos

- [DebianSway](https://github.com/SOSMLG/DebianSway): Sway on Debian/Devuan.
- [DevuanSway](https://github.com/SOSMLG/DevuanSway): Sway on Devuan with OpenRC.
- [Devuan-Kde](https://github.com/SOSMLG/Devuan-Kde): KDE Plasma on Devuan.
- [DevuanDwm](https://github.com/SOSMLG/DevuanDwm): minimal dwm desktop for Devuan.
- [XfceMlg](https://github.com/SOSMLG/XfceMlg): XFCE desktop toolkit.
## Repository standard

This repo follows the SOSMLG standard: [contributing](CONTRIBUTING.md), [security](SECURITY.md), [changelog](CHANGELOG.md). Local workflow: [English guide](https://github.com/SOSMLG/.github/blob/main/docs/GIT_GUIDE.md) / [Arabic guide](https://github.com/SOSMLG/.github/blob/main/docs/GIT_GUIDE.ar.md). Visual standard: [theme](https://github.com/SOSMLG/.github/blob/main/docs/THEME.md) / [الطابع البصري](https://github.com/SOSMLG/.github/blob/main/docs/THEME.ar.md).
