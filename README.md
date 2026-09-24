# gpu-nvidia-fix

Helper scripts for surviving NVIDIA DKMS breakage on Arch Linux when a
kernel update removes APIs the proprietary module still uses, plus a hold
pattern that keeps `linux` / `nvidia` packages from updating underneath a
working driver until an official fixed release lands.

## Tested configuration

| Component | Tested |
|---|---|
| Kernel | `7.2.6-arch2-1` (Arch Linux, x86_64) |
| NVIDIA DKMS package | `nvidia-580xx-dkms 580.173.02-1` |
| GPU | GeForce GTX 1080 (GP104, Pascal) |
| Bootloader / initramfs | GRUB + mkinitcpio |
| Display | Xorg + i3WM under GDM |

Upstream fixed the underlying issue in driver series 580.178.04+.
Reinstalling the DKMS package wipes `/usr/src` patches — expected once
the official build lands. The repair script refuses to run against any
other driver version instead of guessing (see guards in
`gpu-fix-nvidia.sh`, rationale in `PATCH_NOTES.md`).

### Expected but unverified

- Same driver (580.173.02) on later 7.2.x kernels: the removed API stays
  removed, so the patches should still apply and DKMS should rebuild.
  The version guard pins the *driver*, not the kernel, so this path stays
  open.
- Other Pascal (GP10x) cards: same driver code paths, but not tested here.

### Unsupported / unknown

- Other driver series (470xx, 575xx, 590xx+, …): different sources — the
  patches will not apply, and the script aborts rather than modifying an
  unexpected tree.
- Non-GRUB bootloaders (systemd-boot, Limine, …) and non-mkinitcpio
  initramfs tools (dracut, …): the script only writes GRUB + mkinitcpio
  configuration and only verifies those two.
- Anything not x86_64, anything Wayland-first: not tested here. Run
  `gpu-debug.sh` and compare against the checklist before trusting the
  repair.


## Issue Description
You run a pacman -Syu and reboot only to find yourself in a 640x480 fallback 
state due to nvidia driver load failure.

Although I was still able to see the GUI login prompt and even log into i3WM.

The kitty terminals and other apps launched wouldn't properly refresh.. so I was
essentially blind.


## What the repair changes (read this first)

The repair does **two separate jobs**. They are related but not the same:

**Phase 1 — source compatibility.** Applies `patches/0001-0004` to the
DKMS sources so the driver compiles on kernel 7.2 at all. Without this,
nothing below matters. Details in `PATCH_NOTES.md`.

**Phase 2 — boot/module configuration.** Makes the built driver actually
load at boot:

- writes `/etc/modprobe.d/blacklist-nouveau.conf` (keeps nouveau from
  grabbing the card first)
- ensures `nvidia nvidia_modeset nvidia_uvm nvidia_drm` are in the
  `MODULES=` line of `/etc/mkinitcpio.conf` (early KMS) — existing
  entries are preserved, never replaced
- ensures `nvidia_drm.modeset=1 nvidia_drm.fbdev=1` are in
  `GRUB_CMDLINE_LINUX_DEFAULT` in `/etc/default/grub`
- rebuilds the initramfs (`mkinitcpio -P`) and GRUB config
  (`grub-mkconfig -o /boot/grub/grub.cfg`)

Every step is conditional: already-correct settings print `SKIP`, and if
nothing changed at all, the expensive rebuilds are skipped too.
`mkinitcpio.conf` and `grub` are copied to `.bak` before modification, so
`Emergency Rollback` below can restore them.

Everything below runs in a TTY text console, which works fine even when the
graphical driver is broken. Read this off your phone and type the commands —
they are kept short on purpose.

### 1. Get to a terminal

1. Press `Ctrl+Alt+F3`. The broken GUI disappears, a text login appears.
2. Type your username, Enter, then your password, Enter. Nothing shows while
   typing the password — that is normal.

<div align="center">
<i>Tip: scrollback in a TTY is <code>Shift+PageUp</code>. Back to the GUI anytime with <code>Ctrl+Alt+F1</code> (or <code>F2</code>).</i>
</div>

### 2. Check your network

You need internet to fetch the fix. Wired usually just works; for Wi-Fi:

```bash
ping -c 3 archlinux.org
```

No reply? Run `nmtui`, select your network, activate it, then retry the ping.

### 3. Get these scripts

With git (preferred):

```bash
sudo pacman -S git
git clone https://github.com/wintermoot/gpu-nvidia-fix.git
cd gpu-nvidia-fix
```

No git and don't want it? Grab the same files as a download instead:

```bash
sudo pacman -S curl
curl -L https://github.com/wintermoot/gpu-nvidia-fix/archive/refs/heads/main.tar.gz -o fix.tar.gz
tar xzf fix.tar.gz
cd gpu-nvidia-fix-main
```

(Downloaded folder is named `gpu-nvidia-fix-main` — use that wherever the
rest of this guide says `gpu-nvidia-fix`.)

`sudo` asks for *your* password here, and that works in a TTY.

### 4. Let the script confirm this is your problem

```bash
bash gpu-debug.sh
```

Wait for it to finish, then read the last lines (`VERDICT`). It saves the
full log to `~/logs` either way.

- `VERDICT: MATCH` — this is your issue, continue to step 5.
- `VERDICT: HEALTHY` — your driver is built and bound; the fix below does
  not apply. Look at the compositor, Xorg config, or cables instead.
- Anything else — stop here and share the saved log when asking for help.

These scripts target `nvidia-580xx-dkms 580.173.02` on kernel 7.2.x — with
different versions, treat any non-MATCH verdict as "ask a human".

### 5. Apply the fix

```bash
cd ~/gpu-nvidia-fix   # or gpu-nvidia-fix-main for the download; skip if already there
bash gpu-debug.sh       # saves a "before" log to ~/logs for comparison
bash gpu-fix-nvidia.sh  # patches sources, rebuilds DKMS, sets blacklist,
                        # modules, and boot params (asks for sudo password)
```

The fix script is idempotent — safe to re-run if it errors halfway. It
backs up `mkinitcpio.conf` and the GRUB config to `.bak` files first.

### 6. Pre-reboot checklist

```bash
cd ~/gpu-nvidia-fix   # skip if your prompt already shows it
bash gpu-verify.sh pre
```

Want 5x PASS and `Safe to reboot`. Fix any FAIL line first (it tells you
the exact command). Then:

```bash
sudo reboot
```

### 7. Post-reboot verification

Log in normally (GUI should be back at full resolution), open a terminal.
You start in your home folder, so go back to the project first:

```bash
cd ~/gpu-nvidia-fix   # or gpu-nvidia-fix-main if you downloaded the zip
bash gpu-verify.sh post
bash gpu-debug.sh     # saves an "after" log to ~/logs
```

Want 6x PASS and `All green.` (The resolution check SKIPs in a TTY —
run it from a GUI terminal instead; that SKIP is expected, not a problem.)



## Scripts

- `gpu-debug.sh` — collects kernel version, driver binding, DKMS status,
  modprobe.d, kernel cmdline, journal errors, Xorg log, and display state
  into a timestamped log (`$LOG_DIR`, defaults to `~/logs`), then prints a
  plain-English `VERDICT` saying whether the fix applies to you. No GUI
  required; the `dmesg` section needs a terminal for `sudo`.
- `gpu-fix-nvidia.sh` — repair: applies the version-checked patch files in
  `patches/` to the DKMS sources (refuses unexpected source trees, skips
  already-applied), then `dkms install`, nouveau blacklist, mkinitcpio
  `MODULES`, GRUB `nvidia_drm` parameters, initramfs + GRUB rebuild.
  Idempotent, re-run safe.
- `patches/0001-0004` — the kernel-7.2 `strncpy` compatibility patches for
  nvidia-580.173.02, applied with `git apply` (exact match, no fuzz).
  `PATCH_NOTES.md` explains why each replacement preserves semantics.
- `gpu-update-nvidia.sh` — updates the held kernel/driver packages
  together (the `nvidia-580xx` split packages must upgrade as a set),
  then verifies DKMS status and config.
- `gpu-verify.sh pre|post` — pre/post reboot checklists with PASS/FAIL per
  item (DKMS, blacklist, mkinitcpio, GRUB, binding, nvidia-smi,
  resolution). Exit code 0 means proceed.
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
