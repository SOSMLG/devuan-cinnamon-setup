#!/usr/bin/env bash
# =======================================================
# 10 AI Agents + VSCodium — OpenCode + VSCodium
# -------------------------------------------------------
#   * OpenCode (https://opencode.ai) — open-source, multi-provider agent.
#     Installed via its official installer (fast prebuilt binary); npm is
#     only used as a fallback when the installer's download fails.
#   * VSCodium (https://vscodium.com) — telemetry-free VS Code build,
#     installed from its official APT repo.
#   * ~/.opencode/bin + ~/.local/bin put on PATH (without duplicating lines)
#   * Super+A -> open a terminal running opencode (Cinnamon keybinding)
#   * system skill file dropped to ~/.config/opencode/AGENTS.md (+ ~/AGENTS.md)
#     so the agent understands this Devuan/OpenRC/Cinnamon box.
# =======================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_not_root
log_head "10 AI Agents"

# ---------------------------------------------------------------------------
# 1. OpenCode — official installer, npm fallback
# ---------------------------------------------------------------------------
if command_exists opencode; then
    log_ok "OpenCode already installed ($(opencode --version 2>/dev/null || echo 'version unknown'))."
elif ! curl -fsSL https://opencode.ai/install | bash; then
    log_warn "Official OpenCode installer failed — trying npm."
    if ! command_exists npm; then
        log_info "npm not found — installing Node.js LTS + npm first."
        install_pkgs "Node.js + npm" nodejs npm
    fi
    if command_exists npm; then
        if npm install -g opencode-ai; then
            log_ok "OpenCode installed via npm."
        else
            log_err "npm install of opencode-ai failed — skipping OpenCode."
        fi
    else
        log_err "npm still unavailable — skipping OpenCode."
    fi
else
    log_ok "OpenCode installed."
fi

# Make sure ~/.opencode/bin / ~/bin are on PATH for future shells, without
# duplicating the line. Written to ~/.bashrc.local (sourced by ButterBash's
# .bashrc) so it survives re-runs and ButterBash overwriting ~/.bashrc.
BASH_LOCAL="$HOME/.bashrc.local"
for CANDIDATE in "$HOME/.opencode/bin" "$HOME/bin"; do
    if [ -d "$CANDIDATE" ] && ! grep -qF "$CANDIDATE" "$BASH_LOCAL" 2>/dev/null; then
        echo "export PATH=\"$CANDIDATE:\$PATH\"" >> "$BASH_LOCAL"
        log_ok "Added $CANDIDATE to PATH in ~/.bashrc.local."
    fi
done
# Ensure ~/.bashrc.local actually gets sourced (ButterBash's .bashrc does it;
# if ButterBash is absent, add the source line ourselves — idempotently).
if [ -f "$BASH_LOCAL" ] && ! grep -qF ".bashrc.local" "$HOME/.bashrc" 2>/dev/null \
    && ! grep -qF ".config/bash/bashrc.local" "$HOME/.bashrc" 2>/dev/null; then
    {
        echo ""
        echo "# devuan-cinnamon-setup: machine-specific overrides"
        echo "[ -f \"\$HOME/.bashrc.local\" ] && . \"\$HOME/.bashrc.local\""
    } >> "$HOME/.bashrc"
    log_ok "Ensured ~/.bashrc sources ~/.bashrc.local."
fi

# ---------------------------------------------------------------------------
# 2. VSCodium — official APT repo
# ---------------------------------------------------------------------------
install_vscodium_apt

# ---------------------------------------------------------------------------
# 3. Super+A hotkey — open a terminal running opencode
# ---------------------------------------------------------------------------
if command_exists opencode && cinnamon_custom_binding "OpenCode AI" "x-terminal-emulator -e opencode" "<Super>a"; then
    log_ok "Super+A now opens OpenCode in a terminal."
else
    log_warn "Could not bind Super+A (or opencode isn't on PATH yet) — bind it manually:"
    log_warn "Cinnamon Settings > Keyboard > Shortcuts > Custom, command: x-terminal-emulator -e opencode"
fi

# ---------------------------------------------------------------------------
# 4. System skill file — plain markdown the agent picks up
# ---------------------------------------------------------------------------
SKILL_SRC="$SCRIPT_DIR/../skills/devuan-cinnamon-SKILL.md"
if [ -f "$SKILL_SRC" ]; then
    mkdir -p "$HOME/.config/opencode"
    cp "$SKILL_SRC" "$HOME/.config/opencode/AGENTS.md" 2>/dev/null \
        && log_ok "Installed skill to ~/.config/opencode/AGENTS.md"
    if [ ! -f "$HOME/AGENTS.md" ]; then
        cp "$SKILL_SRC" "$HOME/AGENTS.md" 2>/dev/null
    fi
else
    log_warn "Skill file not found at $SKILL_SRC — skipping."
fi

echo -e "${GREEN}10 AI Agents + VSCodium complete.${NC}"
log_info "opencode: run 'opencode auth login' once to connect a provider, then 'opencode' (or 'c', or 'a')."
log_info "vscodium: run 'codium' to start (or find it in the app menu)."