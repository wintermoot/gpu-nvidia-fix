# gpu-nvidia-fix

Helper scripts for surviving NVIDIA DKMS breakage on Arch Linux when a
kernel update removes APIs the proprietary module still uses, plus a hold
pattern that keeps `linux` / `nvidia` packages from updating underneath a
working driver until an official fixed release lands.

Developed against `linux 7.2.6` + `nvidia-580xx-dkms 580.173.02`
(kernel 7.2 removed `strncpy()` from the kernel API; fixed upstream in
driver series 580.178.04+). Reinstalling the DKMS package wipes
`/usr/src` patches, which is expected once the official build lands.


## Issue Description

You run a pacman -Syu and reboot only to find yourself in a 640x480 fallback 
state due to nvidia driver load failure.

Although I was still able to see the GUI login prompt and even log into i3WM.

The kitty terminals and other apps launched wouldn't properly refresh.. so you were
essentially blind.


## Emergency: fixing it from a text console

Everything below runs in a TTY text console, which works fine even when the
graphical driver is broken. Read this off your phone and type the commands —
they are kept short on purpose.

### 1. Get to a terminal

1. Press `Ctrl+Alt+F3`. The broken GUI disappears, a text login appears.
2. Type your username, Enter, then your password, Enter. Nothing shows while
   typing the password — that is normal.
3. Scrollback in a TTY is `Shift+PageUp`. Back to the GUI later with
   `Ctrl+Alt+F1` (or F2 — whichever shows your login screen).

### 2. Check your network

You need internet to fetch the fix. Wired usually just works; for Wi-Fi:

```bash
ping -c 3 archlinux.org
```

No reply? Run `nmtui`, select your network, activate it, then retry the ping.

### 3. Get these scripts

With git (preferred):

```bash
sudo pacman -S --needed git
git clone https://github.com/wintermoot/gpu-nvidia-fix.git
cd gpu-nvidia-fix
```

No git and don't want it? Grab the same files as a download instead:

```bash
sudo pacman -S --needed curl
curl -L https://github.com/wintermoot/gpu-nvidia-fix/archive/refs/heads/main.tar.gz -o fix.tar.gz
tar xzf fix.tar.gz
cd gpu-nvidia-fix-main
```

(Downloaded folder is named `gpu-nvidia-fix-main` — use that wherever the
rest of this guide says `gpu-nvidia-fix`.)

`sudo` asks for *your* password here, and that works in a TTY.

### 4. Confirm this is your problem

```bash
dkms status
lspci -k | grep -A3 -i vga
pacman -Q linux linux-headers
pacman -Qs nvidia
```

You are in the right place if DKMS says `added` instead of `installed`
for the nvidia module and no `nvidia` driver is bound to the card.
These scripts target `nvidia-580xx-dkms 580.173.02` on kernel 7.2.x —
if your versions differ, the steps still apply, but read error output
carefully instead of assuming the same failure.

### 5. Apply the fix

```bash
bash gpu-debug.sh       # saves a "before" log to ~/logs for comparison
bash gpu-fix-nvidia.sh  # patches sources, rebuilds DKMS, sets blacklist,
                        # modules, and boot params (asks for sudo password)
```

The fix script is idempotent — safe to re-run if it errors halfway. It
backs up `mkinitcpio.conf` and the GRUB config to `.bak` files first.

### 6. Pre-reboot checklist

```bash
dkms status              # must say 'installed', NOT 'added'
grep ^MODULES= /etc/mkinitcpio.conf
cat /proc/cmdline        # look for nvidia_drm.modeset=1
```

All three good? Then:

```bash
sudo reboot
```

### 7. Post-reboot verification

Log in normally (GUI should be back at full resolution), open a terminal:

```bash
nvidia-smi               # should list your GPU
dkms status              # should still say 'installed'
xrandr | head            # should show native resolution, not 640x480
cd ~/gpu-nvidia-fix && bash gpu-debug.sh   # saves an "after" log to ~/logs
```

(`xrandr` only works inside the GUI, not from a TTY — that error is
expected, not a problem.)



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
