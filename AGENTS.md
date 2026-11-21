# devuan-cinnamon-setup - project instructions

Post-install polish for Devuan systems where Cinnamon is already installed.
The toolkit does not install Cinnamon. It debloats the distro task, adds the
missing desktop pieces, and applies a Graphite Amber identity.

## Entry points

- `run.sh` runs a fixed ordered list of `scripts/[0-9][0-9]-*.sh` steps.
- `install.sh` is the unattended wrapper.
- `scripts/verifySetup.sh` is the read-only end-state audit.

## Conventions

- Run as a normal user. The shared helpers in `lib/common.sh` own package
  installs, purges and service dispatch. Keep new privileged calls there
  rather than adding a second escalation path.
- Service handling detects OpenRC first, then systemd, then sysvinit. Devuan
  targets should stay OpenRC-native; do not add direct `systemctl` calls to
  steps.
- Back up before replacing user config files. Steps must be safe to re-run.
- Config payloads live under `config/` and `skills/`; keep them portable,
  with no hard-coded usernames.
- Desktop-setting steps need an active local Cinnamon session to apply dconf
  values. Package-only steps may run over SSH.

## Verification

- `bash -n` on changed shell files.
- `bash scripts/verifySetup.sh` on a target system.
- `bash run.sh --list` after adding or renaming a step.
