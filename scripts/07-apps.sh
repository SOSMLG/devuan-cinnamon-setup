#!/usr/bin/env bash
# =======================================================
# 07 Apps — the desktop completeness pass
# -------------------------------------------------------
# Merges the old desktopEssentials.sh / usefulApps.sh /
# vesktopTelegram.sh:
#   * Flatpak + Flathub + GNOME Software (a unified software center)
#   * Printing (CUPS + drivers + lpadmin group) + GParted + gufw
#     (firewall INSTALLED but not enabled — enable it yourself once
#      you've confirmed it won't break SSH/file sharing)
#   * VLC as default media player, archive/thumbnailer support,
#     qBittorrent, TLP for battery/power management
#   * Vesktop (Discord, latest GitHub .deb) + Telegram Desktop
#     (official tar.xz into ~/.local/opt, no sudo needed)
# =======================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_not_root
log_head "07 Apps"

BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"

apt_update

# ---------------------------------------------------------------------------
# 1. Flatpak + Flathub + GNOME Software — closer to Mint's Software Manager
# ---------------------------------------------------------------------------
install_pkgs "Flatpak + software center" flatpak gnome-software gnome-software-plugin-flatpak
if command_exists flatpak; then
    if sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; then
        log_ok "Flathub remote added system-wide."
    else
        log_warn "Could not add the Flathub remote (may already exist)."
    fi
fi

# ---------------------------------------------------------------------------
# 2. Printing — CUPS + drivers + auto-discovery; user gets lpadmin rights
# ---------------------------------------------------------------------------
install_pkgs "Printing" cups cups-browsed printer-driver-all system-config-printer
if is_installed cups; then
    service_enable_now cups
    log_ok "CUPS enabled and started via $(init_system)."
fi
if getent group lpadmin >/dev/null 2>&1; then
    if id -nG "$ACTUAL_USER" 2>/dev/null | tr ' ' '\n' | grep -qx lpadmin; then
        log_ok "$ACTUAL_USER already in lpadmin."
    elif sudo usermod -aG lpadmin "$ACTUAL_USER"; then
        log_ok "Added $ACTUAL_USER to lpadmin."
        log_warn "Log out and back in for this to take effect."
    fi
fi

# ---------------------------------------------------------------------------
# 3. GParted — partition manager
# ---------------------------------------------------------------------------
install_pkgs "GParted" gparted

# ---------------------------------------------------------------------------
# 4. Firewall control panel — installed only, NOT enabled. Turning on
#    default-deny-incoming automatically could silently break SSH/file
#    sharing; that's a deliberate decision for you to make yourself.
# ---------------------------------------------------------------------------
install_pkgs "Firewall" gufw ufw
log_warn "ufw/gufw installed but NOT enabled. When ready: sudo ufw default deny incoming && sudo ufw default allow outgoing && sudo ufw --force enable"
log_warn "(and 'sudo ufw allow ssh' first if you SSH into this machine.)"

# ---------------------------------------------------------------------------
# 5. VLC — default media player + default MIME handling for common types
# ---------------------------------------------------------------------------
install_pkgs "VLC" vlc
if is_installed vlc && command_exists xdg-mime; then
    if xdg-mime default vlc.desktop \
        video/mp4 video/x-matroska video/webm video/x-msvideo video/quicktime video/mpeg \
        audio/mpeg audio/mp4 audio/flac audio/x-wav audio/ogg 2>/dev/null; then
        log_ok "VLC set as default for common video/audio types."
    else
        log_warn "Could not set MIME defaults (non-fatal)."
    fi
fi

# ---------------------------------------------------------------------------
# 6. Archive support + thumbnailers — makes Nemo feel complete
# ---------------------------------------------------------------------------
install_pkgs "Archive support" p7zip-full unrar-free file-roller nemo-fileroller
install_pkgs "Thumbnailers" ffmpegthumbnailer gnome-video-effects raw-thumbnailer webp-pixbuf-loader

# ---------------------------------------------------------------------------
# 7. qBittorrent + TLP (laptop battery/power management)
# ---------------------------------------------------------------------------
install_pkgs "qBittorrent" qbittorrent
install_pkgs "TLP" tlp
if is_installed tlp; then
    service_enable_now tlp
    log_ok "TLP enabled and started via $(init_system)."
fi

# ---------------------------------------------------------------------------
# 8. Vesktop — Vencord's standalone Discord client, latest GitHub .deb
# ---------------------------------------------------------------------------
install_vesktop() {
    if is_installed vesktop; then
        log_ok "Vesktop already installed."
        return 0
    fi
    log_info "Looking up the latest Vesktop release..."
    local api_json deb_url tmp_deb
    if ! api_json=$(curl -fsSL "https://api.github.com/repos/Vencord/Vesktop/releases/latest"); then
        log_err "Could not reach the GitHub API for the Vesktop release."
        return 1
    fi
    deb_url=$(echo "$api_json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assets = data.get('assets', [])
candidates = [a['browser_download_url'] for a in assets if a['name'].lower().endswith('.deb')]
amd64 = [u for u in candidates if 'amd64' in u.lower() or 'x86_64' in u.lower()]
print((amd64 or candidates or [''])[0])
" 2>/dev/null)
    if [ -z "$deb_url" ]; then
        log_err "Could not find a .deb asset in the latest Vesktop release."
        return 1
    fi
    log_info "Downloading: $deb_url"
    tmp_deb="$(mktemp --suffix=.deb)"
    if ! curl -fL -o "$tmp_deb" "$deb_url"; then
        log_err "Download failed."
        rm -f "$tmp_deb"
        return 1
    fi
    if sudo apt-get install -y "$tmp_deb"; then
        log_ok "Vesktop installed."
    elif sudo dpkg -i "$tmp_deb" && sudo apt-get install -f -y; then
        log_ok "Vesktop installed after dependency fix-up."
    else
        log_err "Vesktop install failed."
        rm -f "$tmp_deb"
        return 1
    fi
    rm -f "$tmp_deb"
}
install_vesktop

# ---------------------------------------------------------------------------
# 9. Telegram Desktop — official tar.xz into ~/.local/opt, no sudo needed
# ---------------------------------------------------------------------------
install_telegram() {
    if [ -x "$HOME/.local/opt/Telegram/Telegram" ]; then
        log_ok "Telegram already installed at $HOME/.local/opt/Telegram."
        return 0
    fi
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp_dir'" RETURN
    if ! command_exists wget; then
        log_err "wget not found — needed for the Telegram download."
        return 1
    fi
    log_info "Downloading Telegram Desktop..."
    if ! wget -q -O "$tmp_dir/telegram.tar.xz" "https://telegram.org/dl/desktop/linux"; then
        log_err "Failed to download Telegram."
        return 1
    fi
    mkdir -p "$HOME/.local/opt"
    rm -rf "$HOME/.local/opt/Telegram"
    if ! tar -xf "$tmp_dir/telegram.tar.xz" -C "$HOME/.local/opt"; then
        log_err "Failed to extract Telegram."
        return 1
    fi
    chmod +x "$HOME/.local/opt/Telegram/Telegram"
    ln -sf "$HOME/.local/opt/Telegram/Telegram" "$BIN_DIR/telegram"
    mkdir -p "$HOME/.local/share/applications"
    cat > "$HOME/.local/share/applications/telegram.desktop" << EOF
[Desktop Entry]
Name=Telegram
Comment=Fast and secure messaging app
Exec=$BIN_DIR/telegram
Icon=telegram
Type=Application
Categories=Network;InstantMessaging;
Terminal=false
EOF
    log_ok "Telegram installed at $HOME/.local/opt/Telegram (launcher: telegram)."
    ! echo "$PATH" | tr ':' '\n' | grep -qx "$BIN_DIR" \
        && log_warn "$BIN_DIR is not in your PATH — add 'export PATH=\$HOME/.local/bin:\$PATH' to your shell rc."
}
install_telegram

echo -e "${GREEN}07 Apps complete.${NC}"