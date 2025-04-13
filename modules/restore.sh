#!/bin/bash

restore_system() {
    log "Starting system restore..."

    # Prompt for backup file
    BACKUP_FILE=$(dialog --fselect "$BACKUP_DIR/jetson_backup_" 14 50 2>&1 >/dev/tty) || error_exit "Cancelled backup file selection."

    # Confirm restore
    dialog --yesno "This will overwrite the current system with $BACKUP_FILE. Continue?" 8 50 || error_exit "User cancelled restore."

    # Extract backup
    log "Restoring from $BACKUP_FILE..."
    sudo tar -xzf "$BACKUP_FILE" -C / >> "$LOGFILE" 2>&1 || error_exit "Failed to restore backup."

    # Rebuild initramfs
    log "Rebuilding initramfs..."
    sudo update-initramfs -u >> "$LOGFILE" 2>&1 || warn "Failed to rebuild initramfs."

    log "System restore completed."
}