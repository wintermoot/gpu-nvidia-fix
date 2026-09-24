#!/bin/bash
set -e
KVER=$(uname -r)
echo "Kernel: $KVER"
sudo -v
EXPECT_VER=580.173.02
SRC=/usr/src/nvidia-$EXPECT_VER
_FSRC="${BASH_SOURCE[0]:-$0}"
while [ -L "$_FSRC" ]; do _L="$(readlink "$_FSRC")"; case "$_L" in /*) _FSRC="$_L";; *) _FSRC="$(dirname "$_FSRC")/$_L";; esac; done
PATCHDIR="$(dirname "$_FSRC")/patches"

echo "Expecting NVIDIA source $EXPECT_VER at $SRC"
[ -d "$SRC" ] || { echo "ERROR: source tree $SRC not found. Is nvidia-580xx-dkms installed? No changes were made."; exit 1; }
pacman -Q nvidia-580xx-dkms 2>/dev/null | grep -q "$EXPECT_VER" || { echo "ERROR: installed nvidia-580xx-dkms does not match $EXPECT_VER. Refusing to patch an unexpected version. No changes were made."; exit 1; }
command -v git >/dev/null || { echo "ERROR: 'git' not found (install with: sudo pacman -S git). No changes were made."; exit 1; }
[ -d "$PATCHDIR" ] || { echo "ERROR: patch dir $PATCHDIR missing. Clone/download the full project. No changes were made."; exit 1; }

apply_patch() {
  local p="$1"
  if git -C "$SRC" apply --reverse --check -p1 < "$p" >/dev/null 2>&1; then
    echo "SKIP (already applied): $(basename "$p")"
  elif git -C "$SRC" apply --check -p1 < "$p" >/dev/null 2>&1; then
    echo "APPLY: $(basename "$p")"
    sudo git -C "$SRC" apply -p1 "$p" || { echo "ERROR: failed applying $(basename "$p"). No further changes."; exit 1; }
  else
    echo "ERROR: $(basename "$p") does not match the expected $EXPECT_VER source tree."
    echo "Refusing to modify an unexpected source tree. No changes were made."
    exit 1
  fi
}

echo "Applying kernel-7.2 compatibility patches from $PATCHDIR..."
for p in "$PATCHDIR"/000*.patch; do apply_patch "$p"; done
grep -rn "strncpy" $SRC --include="*.c" | grep -v Binary || echo "no strncpy left"
echo "Rebuilding nvidia DKMS..."
sudo dkms install -m nvidia -v 580.173.02 -k "$KVER"
echo "Blacklisting nouveau..."
echo -e "blacklist nouveau\noptions nouveau modeset=0" | sudo tee /etc/modprobe.d/blacklist-nouveau.conf > /dev/null
echo "Updating mkinitcpio MODULES..."
sudo cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf.bak
if ! grep -q "MODULES=(nvidia" /etc/mkinitcpio.conf; then
  sudo sed -i 's/^MODULES=.*/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
fi
grep "^MODULES=" /etc/mkinitcpio.conf
echo "Adding nvidia_drm.modeset kernel param..."
sudo cp /etc/default/grub /etc/default/grub.bak
if ! grep -q "nvidia_drm.modeset" /etc/default/grub; then
  sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 nvidia_drm.modeset=1 nvidia_drm.fbdev=1"/' /etc/default/grub
fi
grep "^GRUB_CMDLINE_LINUX_DEFAULT" /etc/default/grub
echo "Regenerating initramfs..."
sudo mkinitcpio -P
echo "Regenerating GRUB..."
sudo grub-mkconfig -o /boot/grub/grub.cfg
echo "Verifying..."
dkms status
echo "Done. Reboot with: sudo reboot"
