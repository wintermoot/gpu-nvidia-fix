#!/bin/bash
# gpu-verify.sh - pre/post reboot checklist with PASS/FAIL verdicts.
# Usage: bash gpu-verify.sh pre    (after gpu-fix-nvidia.sh, before reboot)
#        bash gpu-verify.sh post   (after reboot)
MODE="${1:-}"
if [ "$MODE" != pre ] && [ "$MODE" != post ]; then
  echo "Usage: bash gpu-verify.sh pre|post"
  echo "  pre  - run after gpu-fix-nvidia.sh, before rebooting"
  echo "  post - run after rebooting"
  exit 2
fi
PASS=0
FAIL=0
check() {
  if eval "$1" >/dev/null 2>&1; then
    echo "PASS: $2"; PASS=$((PASS + 1))
  else
    echo "FAIL: $2"; FAIL=$((FAIL + 1))
  fi
}
if [ "$MODE" = pre ]; then
  echo "=== PRE-REBOOT checks (fix applied, reboot pending) ==="
  check "dkms status | grep -qiE 'nvidia.*: installed'" \
    "DKMS nvidia module is built (says 'installed', not 'added')"
  check "grep '^MODULES=' /etc/mkinitcpio.conf | grep -q nvidia" \
    "mkinitcpio MODULES includes nvidia"
  check "grep -q 'blacklist nouveau' /etc/modprobe.d/blacklist-nouveau.conf" \
    "nouveau is blacklisted"
  check "grep '^GRUB_CMDLINE_LINUX_DEFAULT' /etc/default/grub | grep -q 'nvidia_drm.modeset=1'" \
    "GRUB carries nvidia_drm.modeset (takes effect after reboot)"
  _IMG="$(ls -t /boot/initramfs-*.img 2>/dev/null | head -n 1)"
  check "[ -n '$_IMG' ] && [ '$_IMG' -nt /etc/mkinitcpio.conf ]" \
    "initramfs was rebuilt after the config change (else run: sudo mkinitcpio -P)"
else
  echo "=== POST-REBOOT checks ==="
  check "dkms status | grep -qiE 'nvidia.*: installed'" \
    "DKMS nvidia module is built"
  check "lspci -k | grep -A3 -i vga | grep -q 'Kernel driver in use: nvidia'" \
    "nvidia driver is bound to the card"
  check "! lsmod | grep -q '^nouveau'" \
    "nouveau is not loaded"
  check "command -v nvidia-smi && nvidia-smi" \
    "nvidia-smi runs and lists the GPU"
  check "grep -q 'nvidia_drm.modeset=1' /proc/cmdline" \
    "nvidia_drm boot params are active"
  if xrandr >/dev/null 2>&1; then
    check "! xrandr | grep -q 'current 640 x 480'" \
      "resolution is above the 640x480 fallback"
  else
    echo "SKIP: no display found (run this check from a GUI terminal, not TTY)"
  fi
fi
echo "---"
echo "$MODE: $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
  [ "$MODE" = pre ] && echo "Safe to reboot: sudo reboot"
  [ "$MODE" = post ] && echo "All green."
else
  echo "Fix the FAIL lines above before continuing."
fi
[ "$FAIL" -eq 0 ]
