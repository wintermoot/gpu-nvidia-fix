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
    PATCHED=1
  else
    echo "ERROR: $(basename "$p") does not match the expected $EXPECT_VER source tree."
    echo "Refusing to modify an unexpected source tree. No changes were made."
    exit 1
  fi
}

PATCHED=0
CHANGED=0
echo "=== Phase 1: source compatibility (patches) ==="
echo "Applying kernel-7.2 compatibility patches from $PATCHDIR..."
for p in "$PATCHDIR"/000*.patch; do apply_patch "$p"; done
grep -rn "strncpy" $SRC --include="*.c" | grep -v Binary || echo "no strncpy left"
echo "Rebuilding nvidia DKMS..."
sudo dkms install -m nvidia -v 580.173.02 -k "$KVER"
echo "=== Phase 2: boot/module configuration ==="
echo "Phase 1 fixed the source code. This phase configures module loading"
echo "and early KMS so the built driver actually loads at boot."
echo "Each step is skipped when already correct; originals are backed up to"
echo ".bak on the first run only - re-runs keep the original rollback point."
echo "--- nouveau blacklist ---"
if [ -f /etc/modprobe.d/blacklist-nouveau.conf ] \
  && grep -q '^blacklist nouveau' /etc/modprobe.d/blacklist-nouveau.conf \
  && grep -q '^options nouveau modeset=0' /etc/modprobe.d/blacklist-nouveau.conf; then
  echo "SKIP: blacklist already in place"
else
  echo "Writing /etc/modprobe.d/blacklist-nouveau.conf"
  printf 'blacklist nouveau\noptions nouveau modeset=0\n' | sudo tee /etc/modprobe.d/blacklist-nouveau.conf > /dev/null
  CHANGED=1
fi
echo "--- mkinitcpio MODULES (early KMS; existing entries preserved) ---"
if [ ! -e /etc/mkinitcpio.conf.bak ]; then
  sudo cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf.bak
else
  echo "(keeping existing rollback backup /etc/mkinitcpio.conf.bak)"
fi
WANT_MODS=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
if grep -q '^MODULES=' /etc/mkinitcpio.conf; then
  CURRENT="$(grep '^MODULES=' /etc/mkinitcpio.conf | sed 's/^MODULES=(//; s/)$//')"
  MISSING_MODS=()
  for m in "${WANT_MODS[@]}"; do
    case " $CURRENT " in *" $m "*) ;; *) MISSING_MODS+=("$m");; esac
  done
  if [ "${#MISSING_MODS[@]}" -eq 0 ]; then
    echo "SKIP: MODULES already contains the nvidia modules"
  else
    echo "Adding to MODULES: ${MISSING_MODS[*]}"
    sudo sed -i "s|^MODULES=.*|MODULES=($CURRENT ${MISSING_MODS[*]})|" /etc/mkinitcpio.conf
    CHANGED=1
  fi
else
  echo "No MODULES line found; appending one"
  echo "MODULES=(${WANT_MODS[*]})" | sudo tee -a /etc/mkinitcpio.conf > /dev/null
  CHANGED=1
fi
grep "^MODULES=" /etc/mkinitcpio.conf
echo "--- GRUB kernel params (nvidia_drm modeset + fbdev) ---"
if [ ! -e /etc/default/grub.bak ]; then
  sudo cp /etc/default/grub /etc/default/grub.bak
else
  echo "(keeping existing rollback backup /etc/default/grub.bak)"
fi
grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub || { echo "ERROR: no GRUB_CMDLINE_LINUX_DEFAULT line in /etc/default/grub; add kernel params manually. GRUB left unchanged."; exit 1; }
for gp in nvidia_drm.modeset=1 nvidia_drm.fbdev=1; do
  gkey="${gp%%=*}"
  if grep '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub | grep -qF "$gkey"; then
    echo "SKIP: $gkey already present"
  else
    echo "Adding $gp"
    sudo sed -i "s|^\(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*\)\"|\1 $gp\"|" /etc/default/grub
    CHANGED=1
  fi
done
grep "^GRUB_CMDLINE_LINUX_DEFAULT" /etc/default/grub
if [ "$CHANGED" -eq 0 ] && [ "$PATCHED" -eq 0 ]; then
  echo "Neither sources nor configuration changed - skipping initramfs/GRUB rebuild."
else
  echo "Regenerating initramfs..."
  sudo mkinitcpio -P
  echo "Regenerating GRUB..."
  sudo grub-mkconfig -o /boot/grub/grub.cfg
fi
echo "Verifying..."
dkms status
echo "Done. Reboot with: sudo reboot"
