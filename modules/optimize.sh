#!/bin/bash

optimize_performance() {
    log "Optimizing performance..."

    # Set max power mode
    log "Setting max power mode..."
    sudo nvpmodel -m 0 >> "$LOGFILE" 2>&1 || warn "Failed to set power mode."
    sudo jetson_clocks >> "$LOGFILE" 2>&1 || warn "Failed to run jetson_clocks."

    # Increase swap space
    if dialog --yesno "Increase swap space to 4GB?" 8 50; then
        log "Creating 4GB swapfile..."
        sudo fallocate -l 4G /swapfile >> "$LOGFILE" 2>&1 || error_exit "Failed to create swapfile."
        sudo chmod 600 /swapfile
        sudo mkswap /swapfile >> "$LOGFILE" 2>&1 || error_exit "Failed to format swapfile."
        sudo swapon /swapfile >> "$LOGFILE" 2>&1 || error_exit "Failed to enable swap."
        echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >> "$LOGFILE" 2>&1
    fi

    log "Performance optimization completed."
}