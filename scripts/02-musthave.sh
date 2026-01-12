#!/bin/bash

# ==============================================================================
# 02-musthave.sh - Essential Software, Drivers & Locale
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-utils.sh"

check_root

log ">>> Starting Phase 2: Essential (Must-have) Software & Drivers"
# ------------------------------------------------------------------------------
# 1. Btrfs Extras & GRUB (Config was done in 00-btrfs-init)
# ------------------------------------------------------------------------------
section "Step 1/8" "Btrfs Extras & GRUB"

ROOT_FSTYPE=$(findmnt -n -o FSTYPE /)

if [ "$ROOT_FSTYPE" == "btrfs" ]; then
    log "Btrfs filesystem detected."
    exe pacman -S --noconfirm --needed snapper snap-pac btrfs-assistant
    success "Snapper tools installed."

    log "Initializing Snapper 'root' configuration..."
    if ! snapper list-configs | grep -q "^root "; then
        if [ -d "/.snapshots" ]; then
            warn "Removing existing /.snapshots..."
            exe_silent umount /.snapshots
            exe_silent rm -rf /.snapshots
        fi
        if exe snapper -c root create-config /; then
            success "Snapper config created."
            log "Applying retention policy..."
            exe snapper -c root set-config ALLOW_GROUPS="wheel" TIMELINE_CREATE="no" TIMELINE_CLEANUP="yes" NUMBER_LIMIT="10" NUMBER_LIMIT_IMPORTANT="5" TIMELINE_LIMIT_HOURLY="5" TIMELINE_LIMIT_DAILY="7" TIMELINE_LIMIT_WEEKLY="0" TIMELINE_LIMIT_MONTHLY="0" TIMELINE_LIMIT_YEARLY="0"
            success "Policy applied."
        fi
    else
        log "Config exists."
    fi
    
    exe systemctl enable --now snapper-timeline.timer snapper-cleanup.timer

    # GRUB Integration
if [ -d "/boot/grub" ] || [ -f "/etc/default/grub" ]; then
        log "Checking GRUB..."
        
        # --- 核心修改开始：探测 GRUB 在 ESP 分区中的真实路径 ---
        TARGET_EFI_GRUB=""
        
        # 1. 优先检测 /efi/grub
        if [ -d "/efi/grub" ]; then
            TARGET_EFI_GRUB="/efi/grub"
        # 2. 其次检测 /boot/efi/grub
        elif [ -d "/boot/efi/grub" ]; then
            TARGET_EFI_GRUB="/boot/efi/grub"
        fi

        # 3. 如果找到了有效的 EFI GRUB 路径，则执行软链接检查与修复
        if [ -n "$TARGET_EFI_GRUB" ]; then
            # 检查 /boot/grub 是否已经是正确的软链接
            # readlink -f 能够获取链接的绝对路径，确保比对准确
            if [ ! -L "/boot/grub" ] || [ "$(readlink -f /boot/grub)" != "$TARGET_EFI_GRUB" ]; then
                warn "Fixing /boot/grub symlink to $TARGET_EFI_GRUB..."
                
                # 如果 /boot/grub 是一个存在的普通目录（非软链接），先进行备份
                if [ -d "/boot/grub" ] && [ ! -L "/boot/grub" ]; then
                    exe mv /boot/grub "/boot/grub.bak.$(date +%s)"
                fi
                
                # 创建指向真实路径的软链接
                exe ln -sf "$TARGET_EFI_GRUB" /boot/grub
                success "Symlink fix applied."
            fi
        fi
        # --- 核心修改结束 ---

        exe pacman -Syu --noconfirm --needed grub-btrfs inotify-tools
        exe systemctl enable --now grub-btrfsd

        if ! grep -q "grub-btrfs-overlayfs" /etc/mkinitcpio.conf; then
            log "Adding overlayfs hook to mkinitcpio..."
            sed -i 's/^HOOKS=(\(.*\))/HOOKS=(\1 grub-btrfs-overlayfs)/' /etc/mkinitcpio.conf
            exe mkinitcpio -P
        fi

        log "Regenerating GRUB..."
        exe grub-mkconfig -o /boot/grub/grub.cfg
    fi
else
    log "Root is not Btrfs. Skipping Snapper setup."
fi

# ------------------------------------------------------------------------------
# 2. Audio & Video
# ------------------------------------------------------------------------------
section "Step 2/8" "Audio & Video"

log "Installing firmware..."
exe pacman -S --noconfirm --needed sof-firmware alsa-ucm-conf alsa-firmware

log "Installing Pipewire stack..."
exe pacman -S --noconfirm --needed pipewire wireplumber pipewire-pulse pipewire-alsa pipewire-jack pavucontrol

exe systemctl --global enable pipewire pipewire-pulse wireplumber
success "Audio setup complete."

# ------------------------------------------------------------------------------
# 3. Locale
# ------------------------------------------------------------------------------
section "Step 3/8" "Locale Configuration"

if locale -a | grep -iq "zh_CN.utf8"; then
    success "Chinese locale (zh_CN.UTF-8) is active."
else
    log "Generating zh_CN.UTF-8..."
    sed -i 's/^#\s*zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
    if exe locale-gen; then
        success "Locale generated."
    else
        error "Locale generation failed."
    fi
fi

# ------------------------------------------------------------------------------
# 4. Input Method
# ------------------------------------------------------------------------------
section "Step 4/8" "Input Method (Fcitx5)"

exe pacman -S --noconfirm --needed fcitx5-im fcitx5-rime rime-ice-pinyin-git fcitx5-mozc

success "Fcitx5 installed."

# ------------------------------------------------------------------------------
# 5. Bluetooth (Smart Detection)
# ------------------------------------------------------------------------------
section "Step 5/8" "Bluetooth"

# Ensure detection tools are present
log "Detecting Bluetooth hardware..."
exe pacman -S --noconfirm --needed usbutils pciutils

BT_FOUND=false

# 1. Check USB
if lsusb | grep -qi "bluetooth"; then BT_FOUND=true; fi
# 2. Check PCI
if lspci | grep -qi "bluetooth"; then BT_FOUND=true; fi
# 3. Check RFKill
if rfkill list bluetooth >/dev/null 2>&1; then BT_FOUND=true; fi

if [ "$BT_FOUND" = true ]; then
    info_kv "Hardware" "Detected"

    log "Installing Bluez "
    exe pacman -S --noconfirm --needed bluez

    exe systemctl enable --now bluetooth
    success "Bluetooth service enabled."
else
    info_kv "Hardware" "Not Found"
    warn "No Bluetooth device detected. Skipping installation."
fi

# ------------------------------------------------------------------------------
# 6. Power
# ------------------------------------------------------------------------------
section "Step 6/8" "Power Management"

exe pacman -S --noconfirm --needed power-profiles-daemon
exe systemctl enable --now power-profiles-daemon
success "Power profiles daemon enabled."

# ------------------------------------------------------------------------------
# 7. Fastfetch
# ------------------------------------------------------------------------------
section "Step 7/8" "Fastfetch"

exe pacman -S --noconfirm --needed fastfetch
success "Fastfetch installed."

log "Module 02 completed."

# ------------------------------------------------------------------------------
# 9. flatpak
# ------------------------------------------------------------------------------

exe pacman -S --noconfirm --needed flatpak
exe flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

CURRENT_TZ=$(readlink -f /etc/localtime)
IS_CN_ENV=false
if [[ "$CURRENT_TZ" == *"Shanghai"* ]] || [ "$CN_MIRROR" == "1" ] || [ "$DEBUG" == "1" ]; then
  IS_CN_ENV=true
  info_kv "Region" "China Optimization Active"
fi

if [ "$IS_CN_ENV" = true ]; then
  select_flathub_mirror
else
  log "Using Global Sources."
fi