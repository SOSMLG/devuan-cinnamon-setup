# System skill: Devuan Cinnamon Setup

You are running on a Devuan GNU/Linux system that has been set up with the
**devuan-cinnamon-setup** toolkit — a Cinnamon desktop on Devuan instead of
Debian (binary-compatible with Debian trixie), with OpenRC running on top of
sysvinit as the init setup instead of systemd. The desktop is themed to a
**Graphite Amber** palette (accent `#E8A33D`, canvas `#16181D`,
foreground `#D8D3C8`) with ohmydebn-style power-user conveniences. Keep the
following in mind for any system-level help you give:

## Init system: OpenRC (not systemd)

- This box does **not** run systemd. Do not suggest `systemctl`,
  `journalctl`, `systemd-analyze`, or unit files as solutions.
- Use `rc-service <name> start|stop|restart|status` to control services.
- Use `rc-update add <name> default` / `rc-update del <name> default` to
  enable/disable services at boot.
- Logs generally live under `/var/log/` (syslog via a traditional logger
  like rsyslog or syslog-ng), not in a systemd journal.
- Some Devuan boxes run plain sysvinit instead of OpenRC — if `rc-service`
  isn't found, fall back to `service <name> start` and `update-rc.d
  <name> defaults`, which work under both sysvinit and OpenRC.
- Power operations go through the **Devuan Menu**'s System section
  (`config/menu/devuan-menu.py`): `sudo pm-suspend` / `sudo shutdown -r
  now` / `sudo shutdown -h now` under the hood.
- Cron (not systemd timers) is used for anything scheduled — see
  `crontab -l` for the current user's jobs (updates check at 09:00/18:00,
  weekly SSD TRIM on Sundays).

## Package management

- Standard Debian-family `apt` / `apt-get` / `dpkg`. Devuan tracks Debian's
  package base closely, so most Debian documentation and packages apply
  directly. Never use `pacman`/`dnf`.
- Check whether a package is installed with:
  `dpkg-query -W -f='${Status}' <pkg> | grep -q "install ok installed"`
  rather than assuming.
- Root escalation in this toolkit is plain `sudo` (run as your normal user;
  the scripts escalate per-command). Never run the scripts as root.

## Desktop environment: Cinnamon

- File manager is **Nemo**, not Nautilus/Dolphin. Default text editor is
  **Xed**. **gnome-terminal** is the default terminal (`x-terminal-emulator`,
  `org.cinnamon.desktop.default-applications.terminal`) and your login shell
  is **bash** (starship-powered prompt; CLI convenience aliases live in
  `~/.bashrc`).
- Desktop settings live in dconf/gsettings under schemas like
  `org.cinnamon.*`, `org.cinnamon.desktop.*`, and (for compatibility)
  some `org.gnome.desktop.*` keys. Changing them requires an active
  graphical session as the target user — `gsettings set <schema> <key>
  <value>` run as root or without `DISPLAY`/`DBUS_SESSION_BUS_ADDRESS`
  set will silently fail or write nowhere useful.
- Look: LMDE-flavored base (Mint-Y icons; mint-themes) carried into
  Graphite Amber by `scripts/04-theme.sh` — a dark stock GTK shell
  theme plus a palette-faithful **app layer**: gnome-terminal (Graphite Amber
  profile), btop, bat, eza, starship (prompt), fastfetch. The stock dark
  GTK base carries the identity through the app palette. Desktop effects stay ON.
- Custom keybindings merge into `org.cinnamon.desktop.keybindings`
  custom-list invariantly (use `cinnamon_custom_binding` from
  `lib/common.sh`, never a bulk overwrite). Highlights: Super+Return
  terminal, Super+M Devuan Menu, Super+A OpenCode, Ctrl+Super+E Xed,
  Ctrl+Shift+Escape system monitor, Ctrl+Super+T theme picker.
- Power-user conveniences to know about:
  - **Devuan Menu** (`devuan-menu`, `Super+M`) — searchable GTK launcher
    for Apps/AI/Terminals/Editors/Browsers/Update/System.
  - **Update GUI** (`devuan-update-gui`) — GTK+VTE window running
    `sudo apt-get update && sudo apt-get full-upgrade`; the update
    notification has a clickable "Update now" action.
  - **Terminal AI agents**: `opencode` (alias `c`); a `function a()` opens
    OpenCode in that terminal. **VSCodium** (`codium`) is the installed
    editor (telemetry-free VS Code).
- The canonical palette lives in
  `config/palette/graphite-amber.toml`; templates in
  `config/templates/*.tpl` are `{{ key }}`-rendered by
  `lib/theme_render.py`, and `lib/theme-apply.sh` applies them.
  `~/.config/devuan-cinnamon/current/` holds the active palette copy and
  `picker.colors` (`bg0`/`bg1`/`bg3`/`fg0` keys) used by the menu and
  update GUI for their styling.

## Toolkit layout (if asked about "this setup" or shown this repo)

```
devuan-cinnamon-setup/
├── install.sh              # one-command unattended installer (runs --verify at the end)
├── run.sh                  # ordered runner: --list / --only N / --yes / --no-update / --verify / --backup
├── lib/                    # shared helpers (see "Init system" + "DEBSWAY_*" vars)
│   ├── common.sh           # ask/log/apt_update/service/power/gsettings helpers (+ cinnamon_custom_binding)
│   ├── theme-apply.sh      # palette-driven app-theme appliers
│   ├── theme_render.py     # renders {{ key }} templates from palette TOML
│   ├── install-spice.py    # fetches one Cinnamon Spice from the official repo
│   ├── dconf-list-add.py   # idempotent "add to a dconf string-array"
│   ├── dconf-list-remove.py# idempotent "remove from a dconf string-array"
│   ├── panel-applet-add.py # adds an applet to the panel safely
│   ├── set-panel-layout.py # rebuilds panel layout (launchers/quick-list/trash)
│   ├── apply-burnmywindows-settings.py  # pre-writes Burn My Windows (Glide)
│   └── apply-blur-cinnamon-settings.py  # pre-writes Blur Cinnamon settings
├── config/                 # palette, templates, eza/bat themes, menu app
├── scripts/                # ten numbered, independently runnable steps
│   ├── 01-systemSetup.sh ... 10-aiAgents.sh
│   ├── verifySetup.sh      # end-state audit (run.sh --verify)
│   ├── configBackup.sh     # snapshot/restore per-user config (run.sh --backup)
│   └── policies.json       # Firefox enterprise policy used by 08
├── skills/                 # this file
└── butterbash/             # bundled shell QoL layer
```

The ten steps: `01` update+groups+SSD trim+Timeshift, `02` debloat+
Tracker-off, `03` firmware/microcode/codecs/touchpad, `04` theme + palette
layer, `05` Cinnamon extensions/applets/hotkeys/polish/Nemo actions,
`06` CLI stack (starship/gnome-terminal/fonts/dev tools), `07` apps
(Flatpak/printing/VLC/etc), `08` Firefox ESR hardening, `09` update
notifier + GUI + Devuan Menu + first-run wizard, `10` AI agents + VSCodium
+ keybindings.

Every script in `scripts/` is safe to re-run (checks what's already
installed/applied before acting) and never prompts during a full
`install.sh` run (`DEBSWAY_ASSUME_YES=1`). Nothing runs silently or
destructively. When helping debug or extend this system, follow the same
pattern: check `is_installed`, `command_exists`, or the current dconf
value before changing anything, and prefer additive/idempotent changes.
No script ever calls `systemctl`; services go through
`service_enable_now`/`service_start`/`service_restart` from `lib/common.sh`.
`apt_update` refreshes the package lists exactly once per run (it flips
`DEBSWAY_SKIP_APT_UPDATE=1` after the first success), and
`cinnamon_custom_binding` merges a keybinding into Cinnamon's
custom-list invariantly by name.

## Notes

- Env vars honored: `DEBSWAY_ASSUME_YES` (auto-approve prompts),
  `DEBSWAY_SKIP_APT_UPDATE` (skip apt-get update),
  `CONFIG_BACKUP_DIR` (configBackup.sh output dir),
  `BETTERFOX_TAG` (pinned Betterfox tag for 08).
- This is a post-install toolkit only — the ISO/respin half of the original
  project was abandoned; do not suggest it.
- State log of the last run:
  `~/.local/state/devuan-cinnamon-setup/last-run.log`.

## Attribution

This toolkit's structure follows the "ordered runner + flat scripts/ dir"
pattern used by DebianSway and this author's own devuan-kde-setup. Several
features — the OpenCode agent setup and system skill file, the update
window concept, the GTK-picker styling, the power-menu concept, the Cinnamon
polish hints, the CLI-tool selection — are adapted from
[OhMyDebn](https://github.com/dougburks/ohmydebn) (MIT licensed), and the
palette is Graphite Amber, maintained locally and reworked
here for Cinnamon-on-Devuan with OpenRC instead of OhMyDebn's Debian +
systemd base.