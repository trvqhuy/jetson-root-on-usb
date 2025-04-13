#!/bin/bash

setup_usb_root() {
    local USB_NAME="$1"
    local CONFIRM="$2"
    local UPDATE_FSTAB="$3"
    local ARCH="$4"
    local MOUNT_POINT="/mnt/usb"
    local EXTLINUX_CONF="/boot/extlinux/extlinux.conf"
    local USB_EXTLINUX_CONF="$MOUNT_POINT/boot/extlinux/extlinux.conf"
    local KERNEL_VERSION="$(uname -r)"

    log "Starting USB root migration..."

    # Validate inputs
    if [ -z "$USB_NAME" ] || [ -z "$CONFIRM" ] || [ -z "$UPDATE_FSTAB" ]; then
        log "Invalid parameters for USB root setup."
        return 1
    fi

    if [ "$CONFIRM" != "yes" ]; then
        log "USB root migration skipped: Confirmation not provided."
        return 0
    fi

    if [ "$ARCH" != "aarch64" ]; then
        log "Simulated USB root migration on $ARCH (no changes made)."
        return 0
    fi

    # Fix TeamViewer GPG error
    if grep -q "teamviewer" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
        log "Configuring TeamViewer repository key..."
        wget -q -O /tmp/teamviewer.gpg https://download.teamviewer.com/download/linux/signature/TeamViewer2017.asc 2>&1 | tee -a "$LOGFILE" || {
            warn "Failed to download TeamViewer GPG key. Continuing..."
        }
        if [ -f /tmp/teamviewer.gpg ]; then
            sudo apt-key add /tmp/teamviewer.gpg 2>&1 | tee -a "$LOGFILE" || warn "Failed to add TeamViewer GPG key."
            rm -f /tmp/teamviewer.gpg
        fi
    fi

    # Repair dpkg if interrupted
    log "Verifying package manager status..."
    sudo dpkg --configure -a 2>&1 | tee -a "$LOGFILE" || {
        log "Failed to configure dpkg."
        return 1
    }
    sudo apt install -f -y 2>&1 | tee -a "$LOGFILE" || warn "Failed to fix broken packages, but continuing..."

    # Install required packages
    log "Installing required packages (parted, rsync, pv, initramfs-tools)..."
    sudo apt update 2>&1 | tee -a "$LOGFILE" || {
        log "Failed to update package lists."
        return 1
    }
    sudo apt-get install -y parted rsync pv initramfs-tools 2>&1 | tee -a "$LOGFILE" || {
        log "Failed to install packages."
        return 1
    }

    USB_DEV="/dev/$USB_NAME"
    USB_PART="${USB_DEV}1"
    if [ ! -b "$USB_DEV" ]; then
        log "Device $USB_DEV does not exist or is not a block device."
        return 1
    fi

    # Unmount partitions
    log "Unmounting partitions on $USB_DEV..."
    MOUNTED_PARTS=$(lsblk -nr "$USB_DEV" | awk '{print $1}' | grep -E '^.+[0-9]+$')
    for part in $MOUNTED_PARTS; do
        MOUNTPOINT=$(lsblk -nr "/dev/$part" -o MOUNTPOINT)
        if [ -n "$MOUNTPOINT" ]; then
            sudo umount "/dev/$part" 2>&1 | tee -a "$LOGFILE" || warn "Failed to unmount /dev/$part."
        fi
    done

    # Partition and format
    log "Creating GPT partition on $USB_DEV..."
    sudo parted "$USB_DEV" --script mklabel gpt mkpart primary ext4 0% 100% 2>&1 | tee -a "$LOGFILE" || {
        log "Failed to partition $USB_DEV."
        return 1
    }
    sudo parted "$USB_DEV" --script name 1 APP 2>&1 | tee -a "$LOGFILE" || {
        log "Failed to name partition APP."
        return 1
    }

    log "Formatting $USB_PART as ext4 with label APP..."
    sudo mkfs.ext4 -F -L APP "$USB_PART" 2>&1 | tee -a "$LOGFILE" || {
        log "Failed to format $USB_PART."
        return 1
    }

    # Mount USB
    log "Mounting $USB_PART to $MOUNT_POINT..."
    sudo mkdir -p "$MOUNT_POINT"
    sudo mount "$USB_PART" "$MOUNT_POINT" 2>&1 | tee -a "$LOGFILE" || {
        log "Failed to mount $USB_PART."
        return 1
    }

    # Copy filesystem
    log "Copying root filesystem to USB..."
    sudo rsync -aAXh --info=progress2 \
        --exclude={"/mnt","/proc","/sys","/dev/pts","/tmp","/run","/media","/dev","/lost+found"} \
        / "$MOUNT_POINT" 2>&1 | tee -a "$LOGFILE" || {
        log "Failed to copy filesystem."
        return 1
    }

    # Explicitly copy /boot
    log "Copying /boot to USB..."
    sudo rsync -aAXh --info=progress2 /boot/ "$MOUNT_POINT/boot/" 2>&1 | tee -a "$LOGFILE" || {
        log "Failed to copy /boot."
        return 1
    }

    # Copy kernel modules
    log "Copying kernel modules to USB..."
    if [ -d "/lib/modules/$KERNEL_VERSION" ]; then
        sudo rsync -a /lib/modules/ "$MOUNT_POINT/lib/modules/" 2>&1 | tee -a "$LOGFILE" || warn "Failed to copy kernel modules."
    else
        warn "Kernel modules not found for $KERNEL_VERSION."
    fi

    # Get PARTUUID
    log "Retrieving PARTUUID for $USB_PART..."
    PARTUUID=$(sudo blkid -s PARTUUID -o value "$USB_PART") || {
        log "Failed to get PARTUUID."
        return 1
    }
    log "PARTUUID: $PARTUUID"

    # Backup extlinux.conf (SD card)
    if [ ! -f "${EXTLINUX_CONF}.backup" ]; then
        log "Backing up SD card extlinux.conf..."
        sudo cp "$EXTLINUX_CONF" "${EXTLINUX_CONF}.backup" 2>&1 | tee -a "$LOGFILE" || warn "Failed to backup extlinux.conf."
    fi

    # Update extlinux.conf on SD card (for fallback)
    log "Configuring SD card extlinux.conf..."
    sudo sed -i "s|root=[^ ]*|root=PARTUUID=${PARTUUID}|" "$EXTLINUX_CONF" 2>&1 | tee -a "$LOGFILE" || {
        log "Failed to update SD card extlinux.conf."
        return 1
    }

    # Create extlinux.conf on USB
    log "Creating extlinux.conf on USB..."
    sudo mkdir -p "$(dirname "$USB_EXTLINUX_CONF")"
    sudo cp "$EXTLINUX_CONF" "$USB_EXTLINUX_CONF" 2>&1 | tee -a "$LOGFILE" || {
        log "Failed to copy extlinux.conf to USB."
        return 1
    }
    
    # Update extlinux.conf on USB
    log "Configuring USB extlinux.conf with PARTUUID..."
    sudo sed -i "s|root=[^ ]*|root=PARTUUID=${PARTUUID}|" "$USB_EXTLINUX_CONF" 2>&1 | tee -a "$LOGFILE" || {
        log "Failed to update USB extlinux.conf."
        return 1
    }

    # Update initramfs
    log "Rebuilding initramfs for kernel $KERNEL_VERSION..."
    sudo update-initramfs -c -k "$KERNEL_VERSION" 2>&1 | tee -a "$LOGFILE" || {
        log "Failed to rebuild initramfs."
        return 1
    }
    
    INITRD_PATH="/boot/initrd-${KERNEL_VERSION}"
    if [ -f "/boot/initrd.img-${KERNEL_VERSION}" ]; then
        sudo cp "/boot/initrd.img-${KERNEL_VERSION}" "$MOUNT_POINT$INITRD_PATH" 2>&1 | tee -a "$LOGFILE" || warn "Failed to copy initrd to USB."
        sudo cp "/boot/initrd.img-${KERNEL_VERSION}" "$INITRD_PATH" 2>&1 | tee -a "$LOGFILE" || warn "Failed to copy initrd to SD card."
    else
        warn "Initramfs not found at /boot/initrd.img-${KERNEL_VERSION}."
    fi

    # Add INITRD to extlinux.conf
    if ! grep -q "INITRD" "$EXTLINUX_CONF"; then
        log "Adding INITRD path to SD card extlinux.conf..."
        sudo sed -i "/APPEND/ a INITRD ${INITRD_PATH}" "$EXTLINUX_CONF" 2>&1 | tee -a "$LOGFILE" || warn "Failed to add INITRD to SD card."
    fi
    if ! grep -q "INITRD" "$USB_EXTLINUX_CONF"; then
        log "Adding INITRD path to USB extlinux.conf..."
        sudo sed -i "/APPEND/ a INITRD ${INITRD_PATH}" "$USB_EXTLINUX_CONF" 2>&1 | tee -a "$LOGFILE" || warn "Failed to add INITRD to USB."
    fi

    # Update fstab on USB
    if [ "$UPDATE_FSTAB" = "yes" ]; then
        log "Configuring fstab on USB..."
        sudo sed -i "s|^UUID=.* / .*|PARTUUID=${PARTUUID} / ext4 defaults 0 1|" "$MOUNT_POINT/etc/fstab" 2>&1 | tee -a "$LOGFILE" || warn "Failed to update fstab."
    fi

    # Verify USB boot files
    log "Verifying USB boot configuration..."
    if [ ! -f "$USB_EXTLINUX_CONF" ]; then
        log "USB extlinux.conf not found at $USB_EXTLINUX_CONF."
        return 1
    fi
    if [ ! -f "$MOUNT_POINT$INITRD_PATH" ]; then
        warn "Initramfs not found at $MOUNT_POINT$INITRD_PATH on USB."
    fi
    if [ ! -f "$MOUNT_POINT/boot/Image" ]; then
        warn "Kernel image not found at $MOUNT_POINT/boot/Image on USB."
    fi

    log "USB root migration completed successfully."
    return 0
}