#!/bin/bash

restore_system() {
    local RESTORE_SOURCE="$1"
    local RESTORE_TARGET="$2"

    log "Starting system restore..."

    # Validate inputs
    if [ -z "$RESTORE_SOURCE" ] || [ -z "$RESTORE_TARGET" ]; then
        log "Restore source or target not specified."
        return 1
    fi

    # Confirm source exists
    if [ ! -d "$RESTORE_SOURCE" ]; then
        log "Restore source directory $RESTORE_SOURCE does not exist."
        return 1
    fi
    sudo mount | grep "$RESTORE_SOURCE" >/dev/null || warn "Restore source $RESTORE_SOURCE is not mounted. Ensure it is accessible."

    # Ensure target exists
    sudo mkdir -p "$RESTORE_TARGET" 2>&1 | tee -a "$LOGFILE" || {
        log "Failed to create restore target directory $RESTORE_TARGET."
        return 1
    }
    sudo mount | grep "$RESTORE_TARGET" >/dev/null || warn "Restore target $RESTORE_TARGET is not mounted. Ensure it is accessible."

    log "Restoring system from $RESTORE_SOURCE to $RESTORE_TARGET..."
    sudo rsync -aAXH --info=progress2 \
        "$RESTORE_SOURCE/" "$RESTORE_TARGET" 2>&1 | tee -a "$LOGFILE" || {
        log "Restore failed."
        return 1
    }

    log "System restore completed successfully."
    return 0
}