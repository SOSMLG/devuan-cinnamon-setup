#!/usr/bin/env bash
# ==========================================
# 🌿  Devuan Cinnamon Setup — one-command installer
# Fully unattended: answers every "should I?" question
# with yes (DEBSWAY_ASSUME_YES=1) and runs the whole
# ordered runner. You never press a key.
#
#   bash install.sh          # everything, unattended
#   bash install.sh --only 05
#   bash install.sh --list
#   bash install.sh --verify # also run the end-state audit afterwards
#   bash install.sh --backup # snapshot current config first
#
# For anything interactive once installed, run the
# individual scripts directly with bash scripts/<name>.sh.
# ==========================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "\033[1;34m=========================================================\033[0m"
echo -e "\033[1;34m   Devuan Cinnamon Setup — unattended install\033[0m"
echo -e "\033[1;34m=========================================================\033[0m\n"

export DEBSWAY_ASSUME_YES=1
# Verify by default on a full unattended run so a broken install can't pass
# silently; --no-verify opts back out. --verify is still honored if given.
NO_VERIFY=0
EXTRA=()
for arg in "$@"; do
    if [ "$arg" = "--no-verify" ]; then
        NO_VERIFY=1
    else
        EXTRA+=("$arg")
    fi
done
if [ "$NO_VERIFY" -eq 0 ]; then
    EXTRA+=(--verify)
fi
exec bash "$SCRIPT_DIR/run.sh" "${EXTRA[@]}"