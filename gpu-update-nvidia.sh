#!/bin/bash
# gpu-update-nvidia.sh - safe manual updater for held GPU packages.
# The hold (see ~/.bashrc yay/pacman wrappers) skips these on normal -Syu:
#   linux, linux-headers, nvidia-580xx-dkms, nvidia-580xx-utils
# Run this script instead when you are ready, so the split AUR package
# updates TOGETHER (updating utils alone breaks the dkms dependency).
set -u
HOLD_PKGS=(linux linux-headers nvidia-580xx-dkms nvidia-580xx-utils)

echo "=== Current versions ==="
pacman -Q "${HOLD_PKGS[@]}" 2>&1
echo
echo "=== Pending updates ==="
echo "--- repo ---"
checkupdates 2>&1 | grep -E '^(linux|nvidia)' || echo "(no held repo updates pending)"
echo "--- aur ---"
yay -Qua 2>&1 | grep -E 'nvidia|linux' || echo "(no held AUR updates pending)"
echo
echo "This will run:"
echo "  yay -S nvidia-580xx-dkms nvidia-580xx-utils opencl-nvidia-580xx"
echo "plus kernel if you confirm. Fresh source wipes our manual strncpy"
echo "patches in /usr/src (expected on 580.178.04+, which fixes kernel 7.2"
echo "officially). Custom config (blacklist, mkinitcpio MODULES, grub params)"
echo "is verified afterwards, not overwritten."
echo
read -r -p "Proceed with AUR nvidia combo update? [y/N] " ans
[[ "$ans" =~ ^[Yy]$ ]] || { echo "Aborted. Hold stays active."; exit 1; }

yay -S nvidia-580xx-dkms nvidia-580xx-utils opencl-nvidia-580xx

echo
echo "=== Post-update verify ==="
dkms status
grep -E '^MODULES' /etc/mkinitcpio.conf
cat /etc/modprobe.d/blacklist-nouveau.conf 2>&1
grep ^GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub
echo
read -r -p "Also update kernel (linux + linux-headers) now? [y/N] " kans
if [[ "$kans" =~ ^[Yy]$ ]]; then
  sudo pacman -S linux linux-headers
  echo "Regenerating initramfs + grub for new kernel..."
  sudo mkinitcpio -P
  sudo grub-mkconfig -o /boot/grub/grub.cfg
  dkms status
fi
echo
nvidia-smi 2>&1 | head -n 12
echo
echo "If DKMS shows 'installed' and nvidia-smi lists your GTX 1080, reboot:"
echo "  sudo reboot"
echo "then run:  bash ~/gpu-debug.sh"
