#!/bin/bash
set -e
KVER=$(uname -r)
echo "Kernel: $KVER"
sudo -v
echo "Patching nvidia source for kernel 7.2 (strncpy removed upstream)..."
SRC=/usr/src/nvidia-580.173.02
if grep -q "strncpy(buf, current->comm" $SRC/nvidia/os-interface.c; then
  sudo sed -i 's/strncpy(buf, current->comm, len - 1);/strscpy(buf, current->comm, len);/' $SRC/nvidia/os-interface.c
  sudo sed -i '/os_get_current_process_name/,/^}/ s/^    buf\[len - 1\].*$//' $SRC/nvidia/os-interface.c
fi
if grep -q "strncpy(regkey_val, regkey_val_start" $SRC/nvidia/linux_nvswitch.c; then
  sudo sed -i 's/strncpy(regkey_val, regkey_val_start, regkey_val_len);/memcpy(regkey_val, regkey_val_start, regkey_val_len);/' $SRC/nvidia/linux_nvswitch.c
fi
if grep -q "return strncpy(dest, src, length);" $SRC/nvidia/linux_nvswitch.c; then
  sudo sed -i 's/return strncpy(dest, src, length);/strscpy(dest, src, length);\n    return dest;/' $SRC/nvidia/linux_nvswitch.c
fi
if grep -q "return strncpy(dest, src, n);" $SRC/nvidia-modeset/nvidia-modeset-linux.c; then
  sudo sed -i 's/return strncpy(dest, src, n);/strscpy(dest, src, n);\n    return dest;/' $SRC/nvidia-modeset/nvidia-modeset-linux.c
fi
if grep -q 'strncpy(chunk_split_cache\[level\].name' $SRC/nvidia-uvm/uvm_pmm_gpu.c; then
  sudo sed -i 's/strncpy(chunk_split_cache\[level\].name, "uvm_gpu_chunk_t", sizeof(chunk_split_cache\[level\].name) - 1);/strscpy(chunk_split_cache[level].name, "uvm_gpu_chunk_t", sizeof(chunk_split_cache[level].name));/' $SRC/nvidia-uvm/uvm_pmm_gpu.c
fi
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
