#!/bin/bash

restore_system() {
    local RESTORE_DIR="$1"

    log "Starting system restore..."

    # Validate input
    if [ -z "$RESTORE_DIR" ]; then
        log "No restore directory specified."
        return 1
    fi

    # Confirm source exists
    if [ ! -d "$RESTORE_DIR" ]; then
        log "Restore directory $RESTORE_DIR does not exist."
        return 1
    fi
    sudo mount | grep "$RESTORE_DIR" >/dev/null || warn "Restore directory $RESTORE_DIR is not mounted. Ensure it is accessible."

    log "Restoring system from $RESTORE_DIR to /..."
    sudo rsync -aAXH --info=progress2 \
        "$RESTORE_DIR"/ / 2>&1 | tee -a "$LOGFILE" || {
        log "Restore failed."
        return 1
    }

    log "System restore completed successfully."
    return 0
}