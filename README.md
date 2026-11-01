# gpu-nvidia-fix

[![shell](https://github.com/wintermoot/gpu-nvidia-fix/actions/workflows/shell.yml/badge.svg)](https://github.com/wintermoot/gpu-nvidia-fix/actions/workflows/shell.yml)

Helper scripts for surviving NVIDIA DKMS breakage on Arch Linux when a
kernel update removes APIs the proprietary module still uses, plus a hold
pattern that keeps `linux` / `nvidia` packages from updating underneath a
working driver until an official fixed release lands.

The original 580.173.02 / kernel-7.2 incident this repo was built for is
**resolved**: upstream fixed the API breakage in 580.178.04+, and the
reference host moved to 580.196.07 on 2026-11-01 (hold retired).

## Tested configuration

| Component | Broken (patched, historical) | Resolved |
|---|---|---|
| Kernel | `7.2.6-arch2-1` (Arch Linux, x86_64) | `7.2.6-arch2-1` |
| NVIDIA DKMS package | `nvidia-580xx-dkms 580.173.02-1` | `nvidia-580xx-dkms 580.196.07-1` |
| 32-bit GL package | (not installed) | `lib32-nvidia-580xx-utils 580.196.07-1` |
| GPU | GeForce GTX 1080 (GP104, Pascal) | GeForce GTX 1080 (GP104, Pascal) |
| Bootloader / initramfs | GRUB + mkinitcpio | GRUB + mkinitcpio |
| Display | Xorg + i3WM under GDM | Xorg + i3WM under GDM |

Upstream fixed the underlying issue in driver series 580.178.04+. On
2026-11-01 the reference host upgraded the whole 580xx set to `580.196.07`
(64-bit utils + DKMS + `lib32-nvidia-580xx-utils` together), rebuilt the
initramfs so early KMS embeds the new module, and verified DKMS,
`nvidia-smi`, the 32-bit GL libraries, and a 32-bit OpenGL game after
reboot. The manual `strncpy` patches and the hold pattern below are
therefore historical: they still apply to `580.173.02`, but are not needed
on `580.178.04+`.

Reinstalling the DKMS package wipes `/usr/src` patches — expected once
the official build lands. The repair script refuses to run against any
other driver version instead of guessing (see guards in
`gpu-fix-nvidia.sh`, rationale in `PATCH_NOTES.md`).

### 32-bit OpenGL note

The 32-bit userspace libraries are a separate package. If a 32-bit OpenGL
game exits immediately (e.g. Noita logs `Window creation failed: Invalid
window`), install `lib32-nvidia-580xx-utils` at the **same version** as
`nvidia-580xx-utils` / `nvidia-580xx-dkms`, then rebuild the initramfs and
reboot so the 32-bit client matches the loaded kernel module.

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
`mkinitcpio.conf` and `grub` are copied to `.bak` before modification —
first run only, so re-running the repair can never overwrite the original
rollback point. `Emergency Rollback` below restores from those backups.

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
  then verifies DKMS status and config. Add `lib32-nvidia-580xx-utils` by
  hand when 32-bit OpenGL apps are in use.
- `gpu-verify.sh pre|post` — pre/post reboot checklists with PASS/FAIL per
  item (DKMS, blacklist, mkinitcpio, GRUB, binding, nvidia-smi,
  resolution). Exit code 0 means proceed.
- `gpu-rollback.sh` — undoes the repair: restores `.bak` configs, drops
  the blacklist, rebuilds initramfs + GRUB, optionally removes NVIDIA
  packages (nouveau fallback). Prompts before changing anything.
- `lib/diagnose.sh` — the driver-state classifier (`MATCH` / `HEALTHY` /
  `UNCLEAR` / built-unbound / no-entry) shared by `gpu-debug.sh`.
- `tests/` — fixtures (`dkms status` + `lspci -k` samples) and `run.sh`,
  which runs the classifier against them with no hardware. Also runs in CI.
- `gpu-hold-reminder.hook` — pacman `PreTransaction` hook that warns when
  a transaction touches held packages (install to
  `/etc/pacman.d/hooks/`).

## The hold (retired 2026-11-01)

The hold kept the broken 580.173.02 set in place until a fixed driver
landed. It consisted of:

1. `IgnorePkg = linux linux-headers nvidia-580xx-dkms nvidia-580xx-utils`
   in `pacman.conf`.
2. The hook above as a reminder on every relevant transaction.
3. A `yay` shell wrapper that auto-appends `--ignore` for the same set
   on `-Syu` and points at `gpu-update-nvidia.sh` instead.

Once a fixed driver is installed and verified, retire it:

```bash
sudo rm /etc/pacman.d/hooks/gpu-hold-reminder.hook
sudo sed -i '/^IgnorePkg = .*nvidia-580xx/d' /etc/pacman.conf
# delete the GPU_HOLD / yay() wrapper block from ~/.bashrc, then open a new shell
```

Confirm with `grep '^IgnorePkg' /etc/pacman.conf` (no match desired) and
`type yay` in a new shell (should resolve to `/usr/bin/yay`, not a function).

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

Once those pass, retire the hold as shown in
[The hold](#the-hold-retired-2026-11-01).

## Emergency Rollback

If the repair made things worse, or you simply want nouveau back, undo it:

```bash
cd ~/gpu-nvidia-fix   # or gpu-nvidia-fix-main if you downloaded the zip
bash gpu-rollback.sh
```

The script prompts before changing anything, then restores the `.bak`
backups, removes the script-created nouveau blacklist, and rebuilds the
initramfs + GRUB config. It then asks whether to also remove the NVIDIA
packages for a full nouveau fallback. Reboot with `sudo reboot`, then run
`bash gpu-debug.sh` (expect the nouveau/simpledrm state, not nvidia).

Without the script, the same steps by hand:

```bash
sudo cp /etc/mkinitcpio.conf.bak /etc/mkinitcpio.conf
sudo cp /etc/default/grub.bak /etc/default/grub
sudo rm -f /etc/modprobe.d/blacklist-nouveau.conf
sudo mkinitcpio -P
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo pacman -R nvidia-580xx-dkms nvidia-580xx-utils   # nouveau fallback only
sudo reboot
```

(If a `.bak` file is missing, stop — there is no known-good state to
restore. The script checks this first and refuses to continue.)
