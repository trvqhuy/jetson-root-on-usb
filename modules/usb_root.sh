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
    if [ -z "$CONFIRM" ] || [ -z "$UPDATE_FSTAB" ]; then
        error_exit "Invalid parameters for USB root setup."
    fi

    if [ "$ARCH" != "aarch64" ]; then
        log "Simulating USB root migration on $ARCH (no changes made)."
        return
    fi

    # Fix TeamViewer GPG error
    if grep -q "teamviewer" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
        log "Fixing TeamViewer GPG key..."
        sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys EF9DBDC73B7D1A07 2>&1 | tee -a "$LOGFILE" || {
            warn "Failed to fetch TeamViewer GPG key. Continuing..."
            log "To remove TeamViewer repo, run: sudo rm /etc/apt/sources.list.d/teamviewer.list"
        }
    fi

    # Repair dpkg if interrupted
    log "Checking dpkg status..."
    if sudo dpkg --configure -a 2>&1 | tee -a "$LOGFILE" | grep -q "dpkg was interrupted"; then
        error_exit "dpkg is interrupted. Run 'sudo dpkg --configure -a' manually and retry."
    fi
    sudo apt install -f -y 2>&1 | tee -a "$LOGFILE" || warn "Failed to fix broken packages, but continuing..."

    # Install required packages
    log "Installing parted, rsync, pv..."
    sudo apt update 2>&1 | tee -a "$LOGFILE" || error_exit "Failed to update package lists."
    sudo apt-get install -y parted rsync pv 2>&1 | tee -a "$LOGFILE" || error_exit "Failed to install packages."

    # Select USB device in interactive mode
    if ! $HEADLESS; then
        # List USB block devices
        USB_DEVICES=$(lsblk -d -o NAME,SIZE,MODEL | grep -E '^sd[a-z]' | awk '{print $1 " " $2 " " $3}')
        if [ -z "$USB_DEVICES" ]; then
            error_exit "No USB devices detected. Please connect a USB drive."
        fi

        # Build dialog menu options
        DIALOG_OPTIONS=""
        while read -r name size model; do
            DIALOG_OPTIONS="$DIALOG_OPTIONS $name \"$name - $size - $model\" off "
        done <<< "$USB_DEVICES"

        # Show dialog menu
        USB_NAME=$(dialog --menu "Select USB device for root migration (ALL data will be erased):" 20 60 10 \
            $DIALOG_OPTIONS 2>&1 >/dev/tty) || error_exit "Cancelled USB device selection."
        clear
        log "Selected USB device: $USB_NAME"
    fi

    # Validate USB_NAME
    if [ -z "$USB_NAME" ]; then
        error_exit "No USB device specified."
    fi
    USB_DEV="/dev/$USB_NAME"
    USB_PART="${USB_DEV}1"
    if [ ! -b "$USB_DEV" ]; then
        error_exit "Device $USB_DEV does not exist or is not a block device."
    fi

    # Confirm erase in interactive mode
    if ! $HEADLESS; then
        dialog --yesno "Erase ALL data on $USB_DEV? (Jetson only)" 8 50 && CONFIRM="yes" || CONFIRM="no"
        clear
        if [ "$CONFIRM" != "yes" ]; then
            log "USB root migration cancelled by user."
            return
        fi
        dialog --yesno "Update /etc/fstab on USB?" 8 50 && UPDATE_FSTAB="yes" || UPDATE_FSTAB="no"
        clear
    fi

    if [ "$CONFIRM" != "yes" ]; then
        log "USB root migration skipped (confirmation not provided)."
        return
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
    sudo parted "$USB_DEV" --script mklabel gpt mkpart primary ext4 0% 100% 2>&1 | tee -a "$LOGFILE" || error_exit "Failed to partition $USB_DEV."
    sudo parted "$USB_DEV" --script name 1 APP 2>&1 | tee -a "$LOGFILE" || error_exit "Failed to name partition APP."

    log "Formatting $USB_PART as ext4 with label APP..."
    sudo mkfs.ext4 -F -L APP "$USB_PART" 2>&1 | tee -a "$LOGFILE" || error_exit "Failed to format $USB_PART."

    # Mount USB
    log "Mounting $USB_PART to $MOUNT_POINT..."
    sudo mkdir -p "$MOUNT_POINT"
    sudo mount "$USB_PART" "$MOUNT_POINT" 2>&1 | tee -a "$LOGFILE" || error_exit "Failed to mount $USB_PART."

    # Copy filesystem
    log "Copying root filesystem to USB..."
    sudo rsync -aAXh --info=progress2 \
        --exclude={"/mnt","/proc","/sys","/dev/pts","/tmp","/run","/media","/dev","/lost+found"} \
        / "$MOUNT_POINT" 2>&1 | tee -a "$LOGFILE" || error_exit "Failed to copy filesystem."

    # Explicitly copy /boot
    log "Copying /boot to USB..."
    sudo rsync -aAXh --info=progress2 /boot/ "$MOUNT_POINT/boot/" 2>&1 | tee -a "$LOGFILE" || error_exit "Failed to copy /boot."

    # Copy kernel modules
    log "Copying kernel modules..."
    if [ -d "/lib/modules/$KERNEL_VERSION" ]; then
        sudo rsync -a /lib/modules/ "$MOUNT_POINT/lib/modules/" 2>&1 | tee -a "$LOGFILE" || warn "Failed to copy kernel modules."
    else
        warn "Kernel modules not found for $KERNEL_VERSION."
    fi

    # Get PARTUUID
    log "Getting PARTUUID..."
    PARTUUID=$(sudo blkid -s PARTUUID -o value "$USB_PART") || error_exit "Failed to get PARTUUID."
    log "PARTUUID: $PARTUUID"

    # Backup extlinux.conf (SD card)
    if [ ! -f "${EXTLINUX_CONF}.backup" ]; then
        log "Backing up SD card extlinux.conf..."
        sudo cp "$EXTLINUX_CONF" "${EXTLINUX_CONF}.backup" 2>&1 | tee -a "$LOGFILE" || warn "Failed to backup extlinux.conf."
    fi

    # Create extlinux.conf on USB
    log "Creating extlinux.conf on USB..."
    sudo mkdir -p "$(dirname "$USB_EXTLINUX_CONF")"
    sudo cp "$EXTLINUX_CONF" "$USB_EXTLINUX_CONF" 2>&1 | tee -a "$LOGFILE" || error_exit "Failed to copy extlinux.conf to USB."
    
    # Update extlinux.conf on USB
    log "Updating USB extlinux.conf with PARTUUID..."
    sudo sed -i "s|root=[^ ]*|root=PARTUUID=${PARTUUID}|" "$USB_EXTLINUX_CONF" 2>&1 | tee -a "$LOGFILE" || error_exit "Failed to update USB extlinux.conf."

    # Update initramfs
    log "Rebuilding initramfs..."
    sudo update-initramfs -c -k "$KERNEL_VERSION" 2>&1 | tee -a "$LOGFILE" || error_exit "Failed to rebuild initramfs."
    
    INITRD_PATH="/boot/initrd-${KERNEL_VERSION}"
    if [ -f "/boot/initrd.img-${KERNEL_VERSION}" ]; then
        sudo cp "/boot/initrd.img-${KERNEL_VERSION}" "$MOUNT_POINT$INITRD_PATH" 2>&1 | tee -a "$LOGFILE" || warn "Failed to copy initrd to USB."
        sudo cp "/boot/initrd.img-${KERNEL_VERSION}" "/boot/initrd-${KERNEL_VERSION}" 2>&1 | tee -a "$LOGFILE" || warn "Failed to copy initrd to SD card."
    else
        warn "Initramfs not found at /boot/initrd.img-${KERNEL_VERSION}."
    fi

    # Add INITRD to USB extlinux.conf
    if ! grep -q "INITRD" "$USB_EXTLINUX_CONF"; then
        log "Adding INITRD to USB extlinux.conf..."
        sudo sed -i "/APPEND/ a INITRD ${INITRD_PATH}" "$USB_EXTLINUX_CONF" 2>&1 | tee -a "$LOGFILE" || warn "Failed to add INITRD."
    fi

    # Update extlinux.conf on SD card (for fallback)
    log "Updating SD card extlinux.conf..."
    sudo sed -i "s|root=[^ ]*|root=PARTUUID=${PARTUUID}|" "$EXTLINUX_CONF" 2>&1 | tee -a "$LOGFILE" || error_exit "Failed to update SD card extlinux.conf."
    if ! grep -q "INITRD" "$EXTLINUX_CONF"; then
        log "Adding INITRD to SD card extlinux.conf..."
        sudo sed -i "/APPEND/ a INITRD ${INITRD_PATH}" "$EXTLINUX_CONF" 2>&1 | tee -a "$LOGFILE" || warn "Failed to add INITRD."
    fi

    # Update fstab on USB
    if [ "$UPDATE_FSTAB" = "yes" ]; then
        log "Updating fstab on USB..."
        sudo sed -i "s|^UUID=.* / .*|PARTUUID=${PARTUUID} / ext4 defaults 0 1|" "$MOUNT_POINT/etc/fstab" 2>&1 | tee -a "$LOGFILE" || warn "Failed to update fstab."
        log "Updated fstab on USB."
    fi

    # Verify USB boot files
    log "Verifying USB boot files..."
    if [ ! -f "$USB_EXTLINUX_CONF" ]; then
        error_exit "USB extlinux.conf not found at $USB_EXTLINUX_CONF."
    fi
    if [ ! -f "$MOUNT_POINT$INITRD_PATH" ]; then
        warn "Initramfs not found at $MOUNT_POINT$INITRD_PATH on USB."
    fi
    if [ ! -f "$MOUNT_POINT/boot/Image" ]; then
        warn "Kernel image not found at $MOUNT_POINT/boot/Image on USB."
    fi

    log "USB root migration completed."
    log "To boot from USB without SD card, ensure USB is plugged in and remove SD card after reboot."
}