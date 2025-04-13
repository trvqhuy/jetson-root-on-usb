#!/bin/bash

backup_system() {
    local BACKUP_DIR="$1"

    log "Starting system backup..."

    # Validate input
    if [ -z "$BACKUP_DIR" ]; then
        log "No backup directory specified."
        return 1
    fi

    # Ensure destination exists
    sudo mkdir -p "$BACKUP_DIR" 2>&1 | tee -a "$LOGFILE" || {
        log "Failed to create backup directory $BACKUP_DIR."
        return 1
    }
    sudo mount | grep "$BACKUP_DIR" >/dev/null || warn "Backup directory $BACKUP_DIR is not mounted. Ensure it is accessible."

    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    DEST="$BACKUP_DIR/backup_$TIMESTAMP"

    log "Backing up system to $DEST..."
    sudo rsync -aAXH --info=progress2 \
        --exclude={"/proc","/sys","/dev","/run","/tmp","/mnt","/media","/lost+found"} \
        / "$DEST" 2>&1 | tee -a "$LOGFILE" || {
        log "Backup failed."
        return 1
    }

    log "System backup completed successfully: $DEST"
    return 0
}