#!/bin/bash

optimize_performance() {
    local ARCH="$1"

    log "Optimizing performance..."

    if [ "$ARCH" = "aarch64" ]; then
        # Set max power mode
        log "Setting max power mode (Jetson)..."
        sudo nvpmodel -m 0 >> "$LOGFILE" 2>&1 || warn "Failed to set power mode."
        sudo jetson_clocks >> "$LOGFILE" 2>&1 || warn "Failed to run jetson_clocks."
    else
        log "Skipping Jetson-specific optimizations on $ARCH."
    fi

    # Increase swap space (platform-agnostic)
    if $HEADLESS || dialog --yesno "Increase swap space to 4GB?" 8 50; then
        if ! $HEADLESS; then
            clear
        fi
        log "Creating 4GB swapfile..."
        sudo fallocate -l 4G /swapfile >> "$LOGFILE" 2>&1 || error_exit "Failed to create swapfile."
        sudo chmod 600 /swapfile
        sudo mkswap /swapfile >> "$LOGFILE" 2>&1 || error_exit "Failed to format swapfile."
        sudo swapon /swapfile >> "$LOGFILE" 2>&1 || error_exit "Failed to enable swap."
        echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >> "$LOGFILE" 2>&1
    fi

    log "Performance optimization completed."
}