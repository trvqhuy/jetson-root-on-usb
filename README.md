# 🔌 Jetson Root on USB

> Move your Jetson Nano’s root filesystem to a USB drive — boost performance, reduce SD card wear, and simplify development.

This project provides a safe, interactive script to install the root filesystem of a Jetson Nano (4GB or 2GB) onto a USB flash drive or SSD, and configure it to boot from that drive using `PARTUUID` for stability. Inspired by [JetsonHacksNano/rootOnUSB](https://github.com/JetsonHacksNano/rootOnUSB), this version modernizes and simplifies the process.

---

## 🚀 Features

- ✅ **Interactive device selection** (`lsblk` prompt)
- ✅ **Automated partitioning, formatting, and setup**
- ✅ **Root filesystem copy with `rsync`**
- ✅ **Robust PARTUUID-based boot config**
- ✅ **Automatically builds initramfs for USB support**
- ✅ **Safe — backs up boot config**

---

## 🧰 Requirements

- NVIDIA Jetson Nano (4GB or 2GB)
- JetPack 4.5+ freshly installed
- A USB 3.0 flash drive or SSD (≥16GB recommended)
- Internet connection (for initramfs and optional package installation)

---

## 📋 Initial Setup (JetPack Fresh Install)

Before running the script, ensure your Jetson Nano system is updated and key packages are installed:

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y rsync parted initramfs-tools
```

⚠️ If `initramfs-tools` is not available on your JetPack image (older versions), install `busybox` and `initramfs` alternatives or refer to the [JetsonHacks guide](https://jetsonhacks.com/2021/03/10/jetson-nano-boot-from-usb/).

---

## 📦 Installation

### 1. Clone the Repository

```bash
git clone https://github.com/<your-username>/jetson-root-on-usb.git
cd jetson-root-on-usb
```

### 2. Run the Script

```bash
chmod +x jetson-usb-boot-installer.sh
sudo ./jetson-usb-boot-installer.sh
```

The script will:

- Display available block devices (e.g., `sda`)
- Prompt you to confirm formatting the selected USB device
- Format the USB drive with GPT + EXT4
- Mount the USB and copy the entire root filesystem
- Update `/boot/extlinux/extlinux.conf` to point to the USB `PARTUUID`
- Generate and add an `initrd` entry (initramfs)

---

## 🔄 Reverting Back to SD Card Boot

To revert to booting from microSD card:

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
