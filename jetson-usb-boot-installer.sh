#!/bin/bash

set -e

MOUNT_POINT="/mnt/usb"
EXTLINUX_CONF="/boot/extlinux/extlinux.conf"
EXCLUDE="--exclude=/mnt --exclude=/proc --exclude=/sys --exclude=/dev/pts --exclude=/tmp --exclude=/run --exclude=/media --exclude=/dev --exclude=/lost+found"

echo "🔍 Available block devices:"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E 'disk|part'
echo ""
read -rp "👉 Enter USB device name (e.g., sda): " USB_NAME
USB_DEV="/dev/$USB_NAME"
USB_PART="${USB_DEV}1"

echo "⚠️ This will wipe ALL data on $USB_DEV. Confirm? (yes/no): "
read CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    echo "❌ Aborted."
    exit 1
fi

echo "📦 Creating partition and formatting..."
sudo parted $USB_DEV --script mklabel gpt mkpart primary ext4 0% 100%
sudo mkfs.ext4 -F "$USB_PART"

echo "📂 Mounting $USB_PART..."
sudo mkdir -p "$MOUNT_POINT"
sudo mount "$USB_PART" "$MOUNT_POINT"

echo "🔄 Copying root filesystem to USB..."
sudo rsync -aAXv / "$MOUNT_POINT" $EXCLUDE

echo "🔧 Getting PARTUUID..."
PARTUUID=$(sudo blkid -s PARTUUID -o value "$USB_PART")

echo "📄 Backing up extlinux.conf..."
sudo cp "$EXTLINUX_CONF" "${EXTLINUX_CONF}.backup"

echo "📝 Updating extlinux.conf to boot from USB..."
sudo sed -i "s|root=[^ ]*|root=PARTUUID=${PARTUUID}|" "$EXTLINUX_CONF"

echo "📦 Rebuilding initramfs to ensure USB support..."
KERNEL_VERSION=$(uname -r)
INITRD_PATH="/boot/initrd-${KERNEL_VERSION}"
sudo update-initramfs -c -k "${KERNEL_VERSION}"
sudo cp "/boot/initrd.img-${KERNEL_VERSION}" "$INITRD_PATH"

if ! grep -q "INITRD" "$EXTLINUX_CONF"; then
  echo "📎 Adding INITRD to extlinux.conf..."
  sudo sed -i "/APPEND/ a INITRD ${INITRD_PATH}" "$EXTLINUX_CONF"
fi

echo ""
echo "✅ All done!"
echo "🔁 You can now reboot. The Jetson Nano will boot from USB."
echo "💡 If it doesn't, make sure USB boot is enabled and try with microSD present."
