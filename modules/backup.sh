#!/bin/bash

backup_system() {
    log "Starting system backup..."

    # Prompt for backup location
    BACKUP_DIR=$(dialog --inputbox "Enter backup directory:" 8 50 "$BACKUP_DIR" 2>&1 >/dev/tty) || error_exit "Cancelled backup directory input."
    BACKUP_FILE="$BACKUP_DIR/jetson_backup_$(date +%Y%m%d_%H%M%S).tar.gz"

    # Ensure directory exists
    sudo mkdir -p "$BACKUP_DIR" || error_exit "Failed to create backup directory."

    # Create backup
    log "Creating backup to $BACKUP_FILE..."
    sudo tar --exclude={"/mnt","/proc","/sys","/dev","/tmp","/run","/media","/lost+found"} \
        -czf "$BACKUP_FILE" / >> "$LOGFILE" 2>&1 || error_exit "Failed to create backup."

    log "System backup completed: $BACKUP_FILE"
}