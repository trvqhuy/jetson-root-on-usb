#!/bin/bash

setup_usb_root() {
    local USB_NAME="$1"
    local CONFIRM="$2"
    local UPDATE_FSTAB="$3"
    local ARCH="$4"
    local MOUNT_POINT="/mnt/usb"
    local EXT_CONF="/boot/extlinux/extlinux.conf"
    local KERNEL_VERSION="$(uname -r)"
    local USB_DEV="/dev/${USB_NAME}"
    local USB_PART="${USB_DEV}1"

    log "Starting USB root migration..."

    # Check
    if [ -z "$USB_NAME" ] || [ -z "$CONFIRM" ] || [ -z "$UPDATE_FSTAB" ]; then
        error_exit "Missing required input for USB setup."
    fi
    if [ "$ARCH" != "aarch64" ]; then
        log "Simulating USB migration (ARCH = $ARCH)"
        return
    fi

    # Install needed tools
    log "Installing tools..."
    sudo apt-get update -y
    sudo apt-get install -y parted rsync pv || error_exit "Required tools failed to install."

    # Confirm USB device exists
    [ -b "$USB_DEV" ] || error_exit "USB device $USB_DEV not found."

    # Unmount partitions
    log "Unmounting partitions..."
    lsblk -nr "$USB_DEV" | awk '{print $1}' | while read -r part; do
        mp=$(lsblk -nr "/dev/$part" -o MOUNTPOINT)
        [ -n "$mp" ] && sudo umount "/dev/$part" || true
    done

    # Partition and format
    log "Creating partition on $USB_DEV..."
    sudo parted "$USB_DEV" --script mklabel gpt mkpart primary ext4 0% 100%
    sudo mkfs.ext4 -F -L APP "$USB_PART" || error_exit "Failed to format $USB_PART"

    # Mount and copy system
    sudo mkdir -p "$MOUNT_POINT"
    sudo mount "$USB_PART" "$MOUNT_POINT" || error_exit "Mount failed"

    log "Copying root filesystem..."
    sudo rsync -aAXH --info=progress2 \
        --exclude={"/proc","/sys","/dev","/run","/tmp","/mnt","/media","/lost+found"} / "$MOUNT_POINT"

    log "Copying /boot and modules..."
    sudo rsync -aAX /boot/ "$MOUNT_POINT/boot/"
    [ -d "/lib/modules/$KERNEL_VERSION" ] && sudo rsync -a /lib/modules/ "$MOUNT_POINT/lib/modules/"

    PARTUUID=$(sudo blkid -s PARTUUID -o value "$USB_PART")
    log "PARTUUID: $PARTUUID"

    # extlinux.conf
    cp "$EXT_CONF" "${EXT_CONF}.backup"
    USB_EXT_CONF="$MOUNT_POINT/boot/extlinux/extlinux.conf"
    sudo mkdir -p "$(dirname "$USB_EXT_CONF")"
    sudo cp "$EXT_CONF" "$USB_EXT_CONF"
    sudo sed -i "s|root=[^ ]*|root=PARTUUID=$PARTUUID|" "$USB_EXT_CONF"
    sudo sed -i "s|root=[^ ]*|root=PARTUUID=$PARTUUID|" "$EXT_CONF"

    INITRD="/boot/initrd-${KERNEL_VERSION}"
    [ -f "/boot/initrd.img-${KERNEL_VERSION}" ] && {
        sudo cp "/boot/initrd.img-${KERNEL_VERSION}" "$MOUNT_POINT$INITRD"
        sudo cp "/boot/initrd.img-${KERNEL_VERSION}" "$INITRD"
    }

    grep -q "INITRD" "$USB_EXT_CONF" || sudo sed -i "/APPEND/ a INITRD ${INITRD}" "$USB_EXT_CONF"
    grep -q "INITRD" "$EXT_CONF"     || sudo sed -i "/APPEND/ a INITRD ${INITRD}" "$EXT_CONF"

    [ "$UPDATE_FSTAB" = "yes" ] && sudo sed -i "s|^UUID=.* / .*|PARTUUID=$PARTUUID / ext4 defaults 0 1|" "$MOUNT_POINT/etc/fstab"

    log "USB root migration complete. Remove SD card and reboot to boot from USB."
}
