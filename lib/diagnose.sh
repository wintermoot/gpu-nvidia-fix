#!/bin/bash
# lib/diagnose.sh - GPU driver-state classifier. Sourced, not executed.
# Provides: gpu_diagnose
# Reads live `dkms status` / `lspci -k` output. For tests, shadow those
# commands (e.g. exported shell functions printing fixture files) before
# calling gpu_diagnose - no test hooks in this file by design.
# Verdicts: MATCH (this repo's fix applies), HEALTHY, UNCLEAR, plus
# built-but-unbound and no-DKMS-entry states with pointers.
gpu_diagnose() {
  local _diagd _diagb
  _diagd="$(dkms status 2>/dev/null | grep -i nvidia || true)"
  _diagb="$(lspci -k 2>/dev/null | grep -A3 -i vga | grep 'Kernel driver in use' || true)"
  echo "DKMS found: ${_diagd:-'(no nvidia DKMS entry)'}"
  echo "Driver bound: ${_diagb:-'(none bound)'}"
  if echo "$_diagd" | grep -q ': added'; then
    if [ -z "$_diagb" ] || echo "$_diagb" | grep -qi nouveau; then
      echo "VERDICT: MATCH - driver is registered but NOT built for this kernel."
      echo "Next step: bash gpu-fix-nvidia.sh (same folder as the debug script)."
    else
      echo "VERDICT: UNCLEAR - driver unbuilt but something else is bound."
      echo "Share the full log above when asking for help."
    fi
  elif echo "$_diagd" | grep -q ': installed'; then
    if echo "$_diagb" | grep -q 'nvidia'; then
      echo "VERDICT: HEALTHY - driver is built and bound. Your problem is"
      echo "likely elsewhere (compositor, Xorg config, cables). The fix script"
      echo "probably does not apply to you."
    else
      echo "VERDICT: driver is built but NOT bound - check the blacklist,"
      echo "modprobe, and cmdline sections above."
    fi
  else
    echo "VERDICT: no nvidia DKMS entry found - this repo's fix probably"
    echo "does not apply."
  fi
}
