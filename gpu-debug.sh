#!/bin/bash
# gpu-debug.sh - run after reboot (works from TTY, no GUI needed)
# Usage: ./gpu-debug.sh  or  bash ~/gpu-debug.sh
_SRC="${BASH_SOURCE[0]:-$0}"
while [ -L "$_SRC" ]; do _L="$(readlink "$_SRC")"; case "$_L" in /*) _SRC="$_L";; *) _SRC="$(dirname "$_SRC")/$_L";; esac; done
[ -f "$(dirname "$_SRC")/.env" ] && . "$(dirname "$_SRC")/.env"
LOG_DIR="${LOG_DIR:-$HOME/logs}"
OUT="$LOG_DIR/gpu-debug-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$LOG_DIR"
exec > >(tee "$OUT") 2>&1
echo "=== DATE / UPTIME ==="
date; uptime
echo
echo "=== UNAME / OS ==="
uname -a; cat /etc/os-release
echo
echo "=== GPU / DRIVER BINDING ==="
lspci -k | grep -A3 -i vga
echo
echo "=== LSMOD nvidia/nouveau ==="
lsmod | grep -E 'nvidia|nouveau' || echo "neither loaded"
echo
echo "=== PACMAN DRIVERS ==="
pacman -Qs 'nvidia|nouveau' 2>&1
pacman -Qs headers 2>&1 | grep linux
echo
echo "=== DKMS STATUS (root cause check) ==="
dkms status 2>&1
echo "want: 'installed' - if you see only 'added', DKMS failed to rebuild for this kernel"
echo
echo "=== MODPROBE / CMDLINE / MKINITCPIO ==="
ls -l /etc/modprobe.d/
cat /etc/modprobe.d/* 2>&1 | head -n 60
cat /proc/cmdline; echo
grep -E '^MODULES|^HOOKS' /etc/mkinitcpio.conf
echo
echo "=== JOURNAL ERRORS THIS BOOT ==="
journalctl -b -p err --no-pager 2>&1 | tail -n 100
echo
echo "=== XORG ==="
ls -lt ~/.local/share/xorg/ /var/log/Xorg* 2>&1 | head
tail -n 150 ~/.local/share/xorg/Xorg.0.log 2>/dev/null || tail -n 150 /var/log/Xorg.0.log 2>&1
echo
echo "=== DISPLAY / COMPOSITOR ==="
echo "XDG_SESSION_TYPE=$XDG_SESSION_TYPE DESKTOP=$XDG_CURRENT_DESKTOP DISPLAY=$DISPLAY WAYLAND=$WAYLAND_DISPLAY"
xrandr 2>&1 | head -n 40
ps aux 2>&1 | grep -iE 'Xorg|Xwayland|picom|kwin|mutter|gnome-shell|plasmashell' | grep -v grep
echo
echo "=== DMESG (needs sudo, will prompt) ==="
sudo dmesg 2>&1 | grep -iE 'nvidia|nouveau|drm|failed|firmware' | tail -n 120
echo
echo "=== DIAGNOSIS (do I need gpu-fix-nvidia.sh?) ==="
_DIAG_DKMS="$(dkms status 2>/dev/null | grep -i nvidia || true)"
_DIAG_BIND="$(lspci -k 2>/dev/null | grep -A3 -i vga | grep 'Kernel driver in use' || true)"
echo "DKMS found: ${_DIAG_DKMS:-'(no nvidia DKMS entry)'}"
echo "Driver bound: ${_DIAG_BIND:-'(none bound)'}"
if echo "$_DIAG_DKMS" | grep -q ': added'; then
  if [ -z "$_DIAG_BIND" ] || echo "$_DIAG_BIND" | grep -qi nouveau; then
    echo "VERDICT: MATCH - driver is registered but NOT built for this kernel."
    echo "Next step: bash gpu-fix-nvidia.sh (same folder as this script)."
  else
    echo "VERDICT: UNCLEAR - driver unbuilt but something else is bound."
    echo "Share the full log above when asking for help."
  fi
elif echo "$_DIAG_DKMS" | grep -q ': installed'; then
  if echo "$_DIAG_BIND" | grep -q 'nvidia'; then
    echo "VERDICT: HEALTHY - driver is built and bound. Your problem is"
    echo "likely elsewhere (compositor, Xorg config, cables). The fix script"
    echo "probably does not apply to you."
  else
    echo "VERDICT: driver is built but NOT bound - check the blacklist,"
    echo "modprobe, and cmdline sections above."
  fi
else
  echo "VERDICT: no nvidia DKMS entry found - this repo's fix probably"
  echo "does not apply to you."
fi
echo
echo "Saved to $OUT"
