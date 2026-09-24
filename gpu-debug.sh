#!/bin/bash
# gpu-debug.sh - run after reboot (works from TTY, no GUI needed)
# Usage: ./gpu-debug.sh  or  bash ~/gpu-debug.sh
_SRC="${BASH_SOURCE[0]:-$0}"
while [ -L "$_SRC" ]; do _L="$(readlink "$_SRC")"; case "$_L" in /*) _SRC="$_L";; *) _SRC="$(dirname "$_SRC")/$_L";; esac; done
# shellcheck source=/dev/null # .env is optional local overrides, see .env.example
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
lspci -k | grep -A3 -iE 'VGA compatible controller|3D controller'
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
# shellcheck disable=SC2012 # human-readable listing is the point of a debug collector
ls -lt ~/.local/share/xorg/ /var/log/Xorg* 2>&1 | head
tail -n 150 ~/.local/share/xorg/Xorg.0.log 2>/dev/null || tail -n 150 /var/log/Xorg.0.log 2>&1
echo
echo "=== DISPLAY / COMPOSITOR ==="
echo "XDG_SESSION_TYPE=$XDG_SESSION_TYPE DESKTOP=$XDG_CURRENT_DESKTOP DISPLAY=$DISPLAY WAYLAND=$WAYLAND_DISPLAY"
xrandr 2>&1 | head -n 40
# shellcheck disable=SC2009 # need the USER/TTY columns pgrep does not print
ps aux 2>&1 | grep -iE 'Xorg|Xwayland|picom|kwin|mutter|gnome-shell|plasmashell' | grep -v grep
echo
echo "=== DMESG (needs sudo, will prompt) ==="
sudo dmesg 2>&1 | grep -iE 'nvidia|nouveau|drm|failed|firmware' | tail -n 120
echo
echo "=== DIAGNOSIS (do I need gpu-fix-nvidia.sh?) ==="
_DIAGLIB="$(dirname "$_SRC")/lib/diagnose.sh"
if [ -f "$_DIAGLIB" ]; then
  # shellcheck source=lib/diagnose.sh
  . "$_DIAGLIB"
  gpu_diagnose
else
  echo "diagnose library missing ($_DIAGLIB); raw state only:"
  dkms status 2>&1 | grep -i nvidia || echo "(no nvidia DKMS entry)"
  lspci -k 2>/dev/null | grep -A3 -iE 'VGA compatible controller|3D controller' | grep 'Kernel driver in use' || echo "(none bound)"
fi
echo
echo "Saved to $OUT"
