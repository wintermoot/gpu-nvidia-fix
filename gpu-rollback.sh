#!/bin/bash
# gpu-rollback.sh - undo gpu-fix-nvidia.sh and get back to a bootable system.
# Restores .bak configs, drops the script-created nouveau blacklist,
# rebuilds initramfs + GRUB, optionally removes NVIDIA packages (nouveau fallback).
# Usage: bash gpu-rollback.sh   (TTY-safe; prompts before changing anything)
set -e

MK=/etc/mkinitcpio.conf
GRUB=/etc/default/grub
BL=/etc/modprobe.d/blacklist-nouveau.conf

echo "=== Emergency Rollback: undo the NVIDIA repair ==="
[ -f "$MK.bak" ] || { echo "ERROR: $MK.bak missing - nothing to restore. No changes were made."; exit 1; }
[ -f "$GRUB.bak" ] || { echo "ERROR: $GRUB.bak missing - nothing to restore. No changes were made."; exit 1; }
echo "Found backups:"
ls -l "$MK.bak" "$GRUB.bak"
echo
echo "Planned steps:"
echo "  1. Restore $MK from backup"
echo "  2. Restore $GRUB from backup"
echo "  3. Remove $BL (script-created; lets nouveau bind again)"
echo "  4. Rebuild initramfs + GRUB config"
echo "  5. (optional) remove NVIDIA packages to fall back to nouveau"
echo
read -r -p "Restore backups and rebuild boot files? [y/N] " ans
[[ "$ans" =~ ^[Yy]$ ]] || { echo "Aborted. No changes were made."; exit 1; }

echo "Restoring $MK..."
sudo cp "$MK.bak" "$MK"
echo "Restoring $GRUB..."
sudo cp "$GRUB.bak" "$GRUB"
if [ -f "$BL" ]; then
  echo "Removing $BL..."
  sudo rm -f "$BL"
else
  echo "SKIP: $BL not present"
fi
echo "Regenerating initramfs..."
sudo mkinitcpio -P
echo "Regenerating GRUB..."
sudo grub-mkconfig -o /boot/grub/grub.cfg

echo
echo "Configuration rolled back. NVIDIA DKMS packages are still installed."
read -r -p "Also remove NVIDIA packages and fall back to nouveau? [y/N] " pans
if [[ "$pans" =~ ^[Yy]$ ]]; then
  REMOVE=()
  for pkg in nvidia-580xx-dkms nvidia-580xx-utils opencl-nvidia-580xx; do
    if pacman -Qq "$pkg" >/dev/null 2>&1; then
      REMOVE+=("$pkg")
    else
      echo "SKIP: $pkg not installed"
    fi
  done
  if [ "${#REMOVE[@]}" -gt 0 ]; then
    echo "Removing: ${REMOVE[*]}"
    sudo pacman -R "${REMOVE[@]}"
  else
    echo "No NVIDIA packages installed; nothing to remove."
  fi
else
  echo "Keeping NVIDIA packages (config-only rollback)."
fi
echo
echo "Done. Reboot with: sudo reboot"
echo "After reboot, run: bash gpu-debug.sh (expect nouveau/simpledrm state)"
