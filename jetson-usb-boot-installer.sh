#!/bin/bash

set -e

# -------------------- CONFIG --------------------
MOUNT_POINT="/mnt/usb"
EXTLINUX_CONF="/boot/extlinux/extlinux.conf"
KERNEL_VERSION="$(uname -r)"
LOGFILE="/var/log/usb-root-setup.log"
EXCLUDE="--exclude=/mnt --exclude=/proc --exclude=/sys --exclude=/dev/pts --exclude=/tmp --exclude=/run --exclude=/media --exclude=/dev --exclude=/lost+found"
DEFAULT_USB_NAME="sda"
DEFAULT_CONFIRM="yes"
DEFAULT_UPDATE_FSTAB="yes"
TIMEOUT=10
AUTO_MODE=false
# ------------------------------------------------

if [[ "$1" == "--auto" ]]; then
    AUTO_MODE=true
    echo -e "\033[1;36m[AUTO MODE ENABLED]\033[0m"
fi

log() {
  echo -e "\033[1;32m[INFO]\033[0m $1" | tee -a "$LOGFILE"
}

warn() {
  echo -e "\033[1;33m[WARN]\033[0m $1" | tee -a "$LOGFILE"
}

error_exit() {
  echo -e "\033[1;31m[ERROR]\033[0m $1" | tee -a "$LOGFILE"
  exit 1
}

log "📦 Ensuring required packages are installed (non-interactive)..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  parted rsync initramfs-tools pv \
  -o Dpkg::Options::="--force-confdef" \
  -o Dpkg::Options::="--force-confold" | tee -a "$LOGFILE"

echo
log "🔍 Listing available block devices:"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E 'disk|part' | tee -a "$LOGFILE"

if $AUTO_MODE; then
  USB_NAME="$DEFAULT_USB_NAME"
  CONFIRM="$DEFAULT_CONFIRM"
  UPDATE_FSTAB="$DEFAULT_UPDATE_FSTAB"
  log "🛠️  Auto mode: using default USB device "/dev/$USB_NAME""
else
  echo ""
  read -t $TIMEOUT -rp "👉 Enter USB device name (e.g. sda) [default: ${DEFAULT_USB_NAME}]: " USB_NAME_INPUT || true
  USB_NAME="${USB_NAME_INPUT:-$DEFAULT_USB_NAME}"
  log "📌 Selected device: /dev/$USB_NAME"

  read -t $TIMEOUT -rp "⚠️  This will erase ALL data on /dev/$USB_NAME. Type 'yes' to continue [default: ${DEFAULT_CONFIRM}]: " CONFIRM_INPUT || true
  CONFIRM="${CONFIRM_INPUT:-$DEFAULT_CONFIRM}"
fi

USB_DEV="/dev/$USB_NAME"
USB_PART="${USB_DEV}1"

if [[ "$CONFIRM" != "yes" ]]; then
  error_exit "User did not confirm disk wipe. Aborting."
fi

log "📦 Creating partition on $USB_DEV..."
sudo parted "$USB_DEV" --script mklabel gpt mkpart primary ext4 0% 100% > /dev/null

log "💥 Formatting $USB_PART as ext4..."
sudo mkfs.ext4 -F "$USB_PART"

# FS_TYPE=$(sudo blkid -o value -s TYPE "$USB_PART" || echo "")
# if [[ "$FS_TYPE" != "ext4" ]]; then
#   log "💥 Formatting $USB_PART as ext4..."
#   sudo mkfs.ext4 -F "$USB_PART"
# else
#   log "ℹ️  $USB_PART is already ext4. Skipping format."
# fi

log "📂 Mounting $USB_PART to $MOUNT_POINT..."
sudo mkdir -p "$MOUNT_POINT"
sudo mount "$USB_PART" "$MOUNT_POINT"

log "🔄 Copying root filesystem to USB with progress bar..."
TOTAL_FILES=$(sudo find / -xdev \\( -path /mnt -o -path /proc -o -path /sys -o -path /dev/pts -o -path /tmp -o -path /run -o -path /media -o -path /dev -o -path /lost+found \\) -prune -o -print | wc -l)
log "📊 Estimated total files: $TOTAL_FILES"

sudo find / -xdev \\( -path /mnt -o -path /proc -o -path /sys -o -path /dev/pts -o -path /tmp -o -path /run -o -path /media -o -path /dev -o -path /lost+found \\) -prune -o -print0 \\
  | pv -0 -l -s "$TOTAL_FILES" \\
  | sudo cpio -0 -pdm "$MOUNT_POINT" 2>&1 | tee -a "$LOGFILE"

log "📄 Copying kernel modules to USB..."
if [ -d "/lib/modules/$KERNEL_VERSION" ]; then
  sudo rsync -a /lib/modules/ "$MOUNT_POINT/lib/modules/" > /dev/null
else
  warn "/lib/modules/$KERNEL_VERSION not found on host!"
fi

log "🔧 Getting PARTUUID for $USB_PART..."
PARTUUID=$(sudo blkid -s PARTUUID -o value "$USB_PART")
if [[ -z "$PARTUUID" ]]; then
  error_exit "Failed to get PARTUUID."
fi
log "📌 PARTUUID: $PARTUUID"

if [ ! -f "${EXTLINUX_CONF}.backup" ]; then
  log "📄 Backing up extlinux.conf..."
  sudo cp "$EXTLINUX_CONF" "${EXTLINUX_CONF}.backup"
else
  log "ℹ️  extlinux.conf backup already exists. Skipping backup."
fi

log "📝 Updating extlinux.conf to boot from USB..."
sudo sed -i "s|root=[^ ]*|root=PARTUUID=${PARTUUID}|" "$EXTLINUX_CONF"

log "📦 Rebuilding initramfs for kernel $KERNEL_VERSION..."
sudo update-initramfs -c -k "$KERNEL_VERSION"

INITRD_PATH="/boot/initrd-${KERNEL_VERSION}"
if [ -f "/boot/initrd.img-${KERNEL_VERSION}" ]; then
  sudo cp "/boot/initrd.img-${KERNEL_VERSION}" "$INITRD_PATH"
else
  warn "Initramfs not found at /boot/initrd.img-${KERNEL_VERSION}"
fi

if ! grep -q "INITRD" "$EXTLINUX_CONF"; then
  log "📎 Adding INITRD path to extlinux.conf..."
  sudo sed -i "/APPEND/ a INITRD ${INITRD_PATH}" "$EXTLINUX_CONF"
fi

if ! $AUTO_MODE; then
  read -t $TIMEOUT -rp "📝 Update /etc/fstab in USB to use PARTUUID? (yes/no, default: ${DEFAULT_UPDATE_FSTAB}): " UPDATE_FSTAB || true
  UPDATE_FSTAB="${UPDATE_FSTAB:-$DEFAULT_UPDATE_FSTAB}"
fi

if [[ "$UPDATE_FSTAB" == "yes" ]]; then
  sudo sed -i "s|^UUID=.* / .*|PARTUUID=${PARTUUID} / ext4 defaults 0 1|" "$MOUNT_POINT/etc/fstab"
  log "/etc/fstab updated on USB root."
fi

log "✅ USB root setup completed successfully!"
log "🔁 You can now reboot. The Jetson Nano will attempt to boot from USB."

echo ""
echo -e "\033[1;34mLog file:\033[0m $LOGFILE"
echo -e "\033[1;36mUse 'mount | grep \" / \"' after reboot to verify it's running from USB.\033[0m"