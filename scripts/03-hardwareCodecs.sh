#!/usr/bin/env bash
# =======================================================
# 03 Hardware & Codecs — firmware, microcode, media, input
# -------------------------------------------------------
# Merges the old hardwareSupport.sh / multimediaCodecs.sh /
# touchpadTrackpointFix.sh:
#   1. non-free WiFi/Bluetooth/Linux firmware + CPU microcode
#      (auto-detected Intel vs AMD, never both)
#   2. fwupd for BIOS/UEFI + peripheral updates via LVFS
#   3. ffmpeg + GStreamer codecs + libdvdcss (libdvd-pkg,
#      built non-interactively under a hard timeout)
#   4. ThinkPad-class input fixes: usbhid mousepoll (laggy
#      trackpoints) + sane libinput defaults under Xorg
# All of this is inert on hardware it doesn't apply to.
# =======================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_not_root
log_head "03 Hardware & Codecs"

apt_update

# ---------------------------------------------------------------------------
# 1. Common WiFi/Bluetooth firmware
# ---------------------------------------------------------------------------
install_pkgs "WiFi/Bluetooth firmware" \
    firmware-iwlwifi firmware-realtek firmware-atheros \
    firmware-brcm80211 firmware-misc-nonfree firmware-linux

# ---------------------------------------------------------------------------
# 2. CPU microcode — auto-detected, never both
# ---------------------------------------------------------------------------
VENDOR="$(grep -m1 -oE 'GenuineIntel|AuthenticAMD' /proc/cpuinfo || true)"
case "$VENDOR" in
    GenuineIntel)
        log_info "Detected Intel CPU."
        install_pkgs "Intel microcode" intel-microcode
        ;;
    AuthenticAMD)
        log_info "Detected AMD CPU."
        install_pkgs "AMD microcode" amd64-microcode
        ;;
    *)
        log_warn "Could not detect CPU vendor from /proc/cpuinfo — skipping microcode."
        ;;
esac

# ---------------------------------------------------------------------------
# 3. fwupd — BIOS/UEFI + peripheral firmware via LVFS; gnome-firmware is
#    Cinnamon's closest "app you can click" front-end (skipped if absent).
# ---------------------------------------------------------------------------
install_pkgs "fwupd" fwupd
if apt-cache show gnome-firmware >/dev/null 2>&1; then
    install_pkgs "fwupd GUI front-end (gnome-firmware)" gnome-firmware
fi
if is_installed fwupd; then
    service_enable_now fwupd
    log_ok "fwupd enabled and started via $(init_system)."
    log_ok "Check any time with: fwupdmgr get-updates"
    [ -x "$(command -v gnome-firmware)" ] && log_ok "...or via the 'Firmware' app (gnome-firmware) in the menu."
fi

# ---------------------------------------------------------------------------
# 4. Multimedia codecs — the "why doesn't MP3/MP4/DVD just work" fix
# ---------------------------------------------------------------------------
install_pkgs "Codec packages" \
    ffmpeg \
    gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly \
    gstreamer1.0-libav libavcodec-extra

if is_installed libdvd-pkg && is_installed libdvdcss2; then
    log_ok "libdvd-pkg already installed and libdvdcss already built."
else
    log_info "Installing libdvd-pkg (builds libdvdcss from source)..."
    if sudo DEBIAN_FRONTEND=noninteractive apt-get install -y libdvd-pkg; then
        log_info "Building libdvdcss (non-interactive, capped at 5 minutes)..."
        if sudo timeout 300 env DEBIAN_FRONTEND=noninteractive dpkg-reconfigure libdvd-pkg; then
            log_ok "libdvd-pkg configured."
        else
            log_warn "libdvd-pkg's build step timed out — retry later with: sudo dpkg-reconfigure libdvd-pkg"
        fi
        if is_installed libdvdcss2; then
            log_ok "libdvdcss built successfully."
        else
            log_warn "Could not confirm libdvdcss built — copy-protected DVDs may not play."
        fi
    else
        log_err "Failed to install libdvd-pkg."
    fi
fi

# ---------------------------------------------------------------------------
# 5. Touchpad / trackpoint fix — the classic laggy-USB-device fix
# ---------------------------------------------------------------------------
MODPROBE_FILE="/etc/modprobe.d/mousepoll.conf"
if [ -f "$MODPROBE_FILE" ] && grep -q "mousepoll=2" "$MODPROBE_FILE" 2>/dev/null; then
    log_ok "$MODPROBE_FILE already sets mousepoll=2 — skipping."
else
    if [ -f "$MODPROBE_FILE" ]; then
        BACKUP="${MODPROBE_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
        sudo cp "$MODPROBE_FILE" "$BACKUP"
        log_info "Existing $MODPROBE_FILE backed up to $BACKUP"
    fi
    if ! echo "options usbhid mousepoll=2" | sudo tee "$MODPROBE_FILE" > /dev/null; then
        log_err "Failed to write $MODPROBE_FILE"
    else
        log_ok "Wrote $MODPROBE_FILE (options usbhid mousepoll=2)"
        if command -v update-initramfs >/dev/null 2>&1; then
            log_info "Updating initramfs..."
            sudo update-initramfs -u || log_warn "update-initramfs failed (non-fatal)."
        fi
        if command -v modprobe >/dev/null 2>&1; then
            log_info "Reloading usbhid now (USB input may briefly disconnect)..."
            if sudo modprobe -r usbhid 2>/dev/null && sudo modprobe usbhid 2>/dev/null; then
                log_ok "usbhid reloaded — fix is active immediately."
            else
                log_warn "Could not hot-reload usbhid — a reboot will apply it."
            fi
        fi
    fi
fi

# ---------------------------------------------------------------------------
# 6. Sane libinput defaults — tap-to-click on, natural scroll off. Xorg-only
#    snippet; Cinnamon's Touchpad settings still override it if you change
#    them afterward.
# ---------------------------------------------------------------------------
XORG_CONF_DIR="/etc/X11/xorg.conf.d"
XORG_CONF_FILE="$XORG_CONF_DIR/30-touchpad.conf"
sudo mkdir -p "$XORG_CONF_DIR"
if [ -f "$XORG_CONF_FILE" ]; then
    sudo cp "$XORG_CONF_FILE" "${XORG_CONF_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
fi
sudo tee "$XORG_CONF_FILE" > /dev/null <<'EOF'
Section "InputClass"
    Identifier "libinput touchpad defaults"
    MatchIsTouchpad "on"
    Driver "libinput"
    Option "Tapping" "on"
    Option "TappingButtonMap" "lrm"
    Option "NaturalScrolling" "false"
    Option "DisableWhileTyping" "true"
    Option "ClickMethod" "clickfinger"
EndSection

Section "InputClass"
    Identifier "libinput pointstick defaults"
    MatchIsPointer "on"
    MatchProduct "TrackPoint|trackpoint|Trackpoint|DualPoint Stick"
    Driver "libinput"
    Option "AccelSpeed" "0.3"
EndSection
EOF
log_ok "Wrote $XORG_CONF_FILE (tap-to-click on, natural scroll off)."

echo -e "${GREEN}03 Hardware & Codecs complete.${NC}"
log_warn "A reboot is recommended so firmware/microcode/mousepoll changes take full effect."