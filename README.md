# 🔌 Jetson Root on USB

> Move your Jetson Nano’s root filesystem to a USB drive — boost performance, reduce SD card wear, and simplify development.

This project provides a safe, flexible script to install the root filesystem of a Jetson Nano (4GB or 2GB) onto a USB flash drive or SSD, and configure it to boot from that drive using `PARTUUID` for stability. Inspired by [JetsonHacksNano/rootOnUSB](https://github.com/JetsonHacksNano/rootOnUSB), this version adds modern enhancements and automation options.

---

## 🚀 Features

- ✅ **Interactive device selection** (`lsblk` with timeout)
- ✅ **Optional `--auto` mode for headless setup**
- ✅ **Automated partitioning, formatting, and setup**
- ✅ **Root filesystem copy with `rsync`**
- ✅ **Robust PARTUUID-based boot config**
- ✅ **Safe — backs up boot configuration**
- ✅ **Rebuilds initramfs to support USB boot**
- ✅ **Keeps existing system files (no config file overwrite prompts)**

---

## 🧰 Requirements

- NVIDIA Jetson Nano (4GB or 2GB)
- JetPack 4.5+ (e.g., 4.6.1)
- A USB 3.0 flash drive or SSD (≥16GB recommended)
- Internet connection for installing dependencies

---

## 📋 JetPack Setup Notes

**Do NOT run `apt upgrade -y` blindly.**

To avoid breaking the custom L4T kernel, follow these guidelines:

```bash
sudo apt update
sudo apt-mark hold nvidia-l4t-kernel nvidia-l4t-core nvidia-l4t-init initramfs-tools
```

---

## 📦 Installation

### 1. Clone the Repository

```bash
git clone https://github.com/trvqhuy/jetson-root-on-usb.git
cd jetson-root-on-usb
```

### 2. Run the Script (Interactive Mode)

```bash
chmod +x jetson-usb-boot-installer.sh
sudo ./jetson-usb-boot-installer.sh
```

- Prompts for USB device (defaults to `sda` after 10s)
- Confirms before wiping the device
- Backs up `/boot/extlinux/extlinux.conf`
- Rebuilds `initramfs`
- Edits `/etc/fstab` on the USB

---

## 🤖 Optional: Auto Mode (No Prompts)

To run non-interactively with all default values:

```bash
sudo ./jetson-usb-boot-installer.sh --auto
```

Ideal for automation, CI pipelines, or flashing farm use.

---

## ✅ Verifying USB Boot

After the first reboot, confirm the system is running from the USB:

```bash
mount | grep ' / '
```

You should see something like:

```
/dev/sda1 on / type ext4 ...
```

This confirms Jetson has successfully booted from USB.

You can also use:

```bash
df -h /
```

If you see `/dev/sda1` or another USB device (not `/dev/mmcblk0p1`), the root filesystem is running from USB.

---

## 🔄 Reverting Back to SD Card Boot

To revert to booting from the microSD card:

```bash
sudo cp /boot/extlinux/extlinux.conf.backup /boot/extlinux/extlinux.conf
sudo reboot
```

---

## ✅ Tested On

- Jetson Nano 4GB B01 – JetPack 4.6.1
- Jetson Nano 2GB – JetPack 4.6.1

Note: USB-only boot (without SD card) may require bootloader changes depending on board revision. Keeping the SD card inserted during boot usually ensures compatibility.

---

## ⚠️ Warnings

- This script **erases all contents** of the selected USB device.
- Do **not** run this on `/dev/mmcblk0` (your SD card) or your system disk.
- Make backups before starting.

---

## 🙌 Credits

- [JetsonHacksNano/rootOnUSB](https://github.com/JetsonHacksNano/rootOnUSB)
- NVIDIA Jetson Community

---

## 📜 License

MIT License — free to use, modify, and share.
