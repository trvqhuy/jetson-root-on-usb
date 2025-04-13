#!/bin/bash

backup_system() {
    local BACKUP_DIR="$1"

    log "Starting system backup..."

    # Validate input
    if [ -z "$BACKUP_DIR" ]; then
        error_exit "Backup directory not provided."
    fi

    # Create backup file
    BACKUP_FILE="$BACKUP_DIR/jetson_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    sudo mkdir -p "$BACKUP_DIR" || error_exit "Failed to create backup directory."

    # Create backup
    log "Creating backup to $BACKUP_FILE..."
    sudo tar --exclude={"/mnt","/proc","/sys","/dev","/tmp","/run","/media","/lost+found"} \
        -czf "$BACKUP_FILE" / >> "$LOGFILE" 2>&1 || error_exit "Failed to create backup."

    log "System backup completed: $BACKUP_FILE"
}