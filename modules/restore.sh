#!/bin/bash

restore_system() {
    local BACKUP_DIR="$1"

    log "Starting system restore..."

    # Validate input
    if [ -z "$BACKUP_DIR" ]; then
        error_exit "Backup directory not provided."
    fi

    # Select backup file
    if $HEADLESS; then
        # In headless mode, use latest backup file
        BACKUP_FILE=$(ls -t "$BACKUP_DIR"/jetson_backup_*.tar.gz 2>/dev/null | head -n 1)
        if [ -z "$BACKUP_FILE" ]; then
            error_exit "No backup files found in $BACKUP_DIR."
        fi
    else
        BACKUP_FILE=$(dialog --fselect "$BACKUP_DIR/jetson_backup_" 14 50 2>&1 >/dev/tty) || error_exit "Cancelled backup file selection."
        clear
    fi

    # Confirm restore
    if $HEADLESS || dialog --yesno "This will overwrite the current system with $BACKUP_FILE. Continue?" 8 50; then
        if ! $HEADLESS; then
            clear
        fi
        # Extract backup
        log "Restoring from $BACKUP_FILE..."
        sudo tar -xzf "$BACKUP_FILE" -C / >> "$LOGFILE" 2>&1 || error_exit "Failed to restore backup."

        # Rebuild initramfs
        log "Rebuilding initramfs..."
        sudo update-initramfs -u >> "$LOGFILE" 2>&1 || warn "Failed to rebuild initramfs."

        log "System restore completed."
    else
        error_exit "Restore cancelled."
    fi
}