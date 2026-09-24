# gpu-nvidia-fix

Helper scripts for surviving NVIDIA DKMS breakage on Arch Linux when a
kernel update removes APIs the proprietary module still uses, plus a hold
pattern that keeps `linux` / `nvidia` packages from updating underneath a
working driver until an official fixed release lands.

Developed against `linux 7.2.6` + `nvidia-580xx-dkms 580.173.02`
(kernel 7.2 removed `strncpy()` from the kernel API; fixed upstream in
driver series 580.178.04+). Reinstalling the DKMS package wipes
`/usr/src` patches, which is expected once the official build lands.

## Scripts

- `gpu-debug.sh` — collects kernel version, driver binding, DKMS status,
  modprobe.d, kernel cmdline, journal errors, Xorg log, and display state
  into a timestamped log (`$LOG_DIR`, defaults to `~/logs`). No GUI
  required; the `dmesg` section needs a terminal for `sudo`.
- `gpu-fix-nvidia.sh` — repair: kernel-API compatibility patches to the
  DKMS sources, `dkms install`, nouveau blacklist, mkinitcpio `MODULES`,
  GRUB `nvidia_drm` parameters, initramfs + GRUB rebuild. Idempotent,
  re-run safe.
- `gpu-update-nvidia.sh` — updates the held kernel/driver packages
  together (the `nvidia-580xx` split packages must upgrade as a set),
  then verifies DKMS status and config.
- `gpu-hold-reminder.hook` — pacman `PreTransaction` hook that warns when
  a transaction touches held packages (install to
  `/etc/pacman.d/hooks/`).

## The hold

1. `IgnorePkg = linux linux-headers nvidia-580xx-dkms nvidia-580xx-utils`
   in `pacman.conf`.
2. The hook above as a reminder on every relevant transaction.
3. A `yay` shell wrapper that auto-appends `--ignore` for the same set
   on `-Syu` and points at `gpu-update-nvidia.sh` instead.

## Local config

Copy `.env.example` to `.env` (gitignored) for machine-specific values
such as log directory and PCI address.

## Unhold procedure

```bash
bash ~/gpu-update-nvidia.sh   # updates the held set together, verifies DKMS
sudo reboot
bash ~/gpu-debug.sh           # compare the new log against the checklist:
                              # DKMS 'installed', nvidia bound, nvidia-smi
                              # lists the GPU, native resolution, clean journal
```

Fallback if the driver misbehaves: remove the `nvidia-580xx-*` packages,
restore the mkinitcpio/GRUB backups, rebuild the initramfs, stay on
nouveau.
