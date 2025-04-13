#!/bin/bash

backup_system() {
    local BACKUP_TARGET="$1"
    local ARCH="$2"

    log "Starting full system backup..."

    if [ -z "$BACKUP_TARGET" ]; then
        error_exit "No backup target directory specified."
    fi

    # Confirm destination exists
    sudo mkdir -p "$BACKUP_TARGET"
    sudo mount | grep "$BACKUP_TARGET" || warn "Ensure $BACKUP_TARGET is mounted."

    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    DEST="$BACKUP_TARGET/backup_$TIMESTAMP"

    log "Backing up / to $DEST ..."
    sudo rsync -aAXH --info=progress2 \
        --exclude={"/proc","/sys","/dev","/run","/tmp","/mnt","/media","/lost+found"} \
        / "$DEST" || error_exit "Backup failed."

    log "✅ Backup complete: $DEST"
}
