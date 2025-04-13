#!/bin/bash

restore_system() {
    local BACKUP_SOURCE="$1"
    local RESTORE_TARGET="$2"

    log "Starting system restore..."

    if [ -z "$BACKUP_SOURCE" ] || [ -z "$RESTORE_TARGET" ]; then
        error_exit "Backup source or restore target not provided"
    fi

    # Confirm target is mounted
    sudo mkdir -p "$RESTORE_TARGET"
    sudo mount | grep "$RESTORE_TARGET" || warn "Ensure $RESTORE_TARGET is mounted"

    log "Restoring from $BACKUP_SOURCE to $RESTORE_TARGET..."
    sudo rsync -aAXH --info=progress2 \
        "$BACKUP_SOURCE"/ "$RESTORE_TARGET" || error_exit "Restore failed."

    log "✅ Restore complete to $RESTORE_TARGET"
}
