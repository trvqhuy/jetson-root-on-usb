#!/bin/bash

set -e

# -------------------- CONFIG --------------------
CONFIG_FILE="config/jetson-setup.conf"
LOG_DIR="logs/jetson-setup"
LOGFILE="$LOG_DIR/setup.log"
MODULE_DIR="$(dirname "$0")/modules"
TIMEOUT=30
HEADLESS=false

# Default values for headless mode
DEFAULT_USB_NAME="sda"
DEFAULT_CONFIRM="yes"
DEFAULT_UPDATE_FSTAB="yes"
DEFAULT_BACKUP_DIR="/mnt/usb/backup"
DEFAULT_RESTORE_DIR="/mnt/usb/backup"
DEFAULT_AI_ML_LIBS="numpy opencv"
DEFAULT_JUPYTER_PORT="8888"
DEFAULT_JUPYTER_TYPE="notebook"
DEFAULT_JUPYTER_BOOT="no"
DEFAULT_JUPYTER_SECURE="token"
DEFAULT_JUPYTER_PASSWORD=""
DEFAULT_SWAP_CONFIRM="yes"

# Dialog styling
DIALOG_BACKTITLE="Jetson Nano Setup - JetPack 4.6.x"
DIALOG_HEIGHT=20
DIALOG_WIDTH=60

# Parse arguments
if [ "$1" = "--headless" ]; then
    HEADLESS=true
fi

# Logging functions
log() {
    echo "[INFO] $1" | tee -a "$LOGFILE"
}

warn() {
    echo "[WARN] $1" | tee -a "$LOGFILE"
}

error_exit() {
    echo "[ERROR] $1" | tee -a "$LOGFILE"
    if ! $HEADLESS; then
        dialog --backtitle "$DIALOG_BACKTITLE" --title "Error" \
            --msgbox "Error: $1\nCheck $LOGFILE for details." 10 50 2>/dev/null || {
            echo "ERROR: Dialog failed to display: $1"
        }
        clear
    fi
    exit 1
}

# Create log and config directories
sudo mkdir -p "$LOG_DIR" "$(dirname "$CONFIG_FILE")"
sudo touch "$LOGFILE"
sudo chmod 644 "$LOGFILE"

# Ensure dialog is installed for interactive mode
if ! $HEADLESS; then
    if ! command -v dialog &> /dev/null; then
        log "Installing dialog..."
        sudo apt update 2>&1 | tee -a "$LOGFILE" || error_exit "Failed to update package lists."
        sudo apt install -y dialog 2>&1 | tee -a "$LOGFILE" || error_exit "Failed to install dialog."
    fi
    # Verify terminal environment
    if [ -z "$TERM" ] || [ "$TERM" = "dumb" ]; then
        export TERM=xterm
        log "Set TERM=xterm due to invalid or missing TERM."
    fi
    tty > /dev/null 2>&1 || {
        echo "ERROR: No interactive terminal (TTY) detected."
        echo "Run with 'ssh -t', a local terminal, or use --headless."
        exit 1
    }
    # Check terminal size
    read rows cols < <(stty size)
    if [ "$rows" -lt $DIALOG_HEIGHT ] || [ "$cols" -lt $DIALOG_WIDTH ]; then
        warn "Terminal size ($rows x $cols) too small for dialog. Resize recommended."
    fi
    # Test dialog
    dialog --backtitle "$DIALOG_BACKTITLE" --title "Initialization" \
        --msgbox "Welcome to Jetson Nano Setup.\nPress OK to proceed." 10 50 2>/dev/null || error_exit "Dialog test failed. Ensure interactive terminal."
    clear
fi

# Source module scripts
log "Loading modules..."
for module in "$MODULE_DIR"/*.sh; do
    [ -f "$module" ] || error_exit "Module not found: $module"
    source "$module" || error_exit "Failed to load module: $module"
done

# Check architecture
ARCH=$(uname -m)
if [ "$ARCH" != "aarch64" ] && ! $HEADLESS; then
    dialog --backtitle "$DIALOG_BACKTITLE" --title "Architecture Warning" \
        --msgbox "This script is optimized for Jetson Nano (ARM64).\nRunning on $ARCH. Some features may be simulated." 10 50 2>/dev/null || log "Dialog warning failed to display."
    clear
fi

# Create default config for headless mode
if $HEADLESS; then
    if [ ! -f "$CONFIG_FILE" ]; then
        log "Creating default config file: $CONFIG_FILE"
        sudo bash -c "cat > $CONFIG_FILE" << 'EOL'
USB_NAME=sda
CONFIRM=yes
UPDATE_FSTAB=yes
BACKUP_DIR=/mnt/usb/backup
RESTORE_DIR=/mnt/usb/backup
AI_ML_LIBS="numpy opencv"
JUPYTER_PORT=8888
JUPYTER_TYPE=notebook
JUPYTER_BOOT=no
JUPYTER_SECURE=token
JUPYTER_PASSWORD=""
SWAP_CONFIRM=yes
EOL
        sudo chmod 644 "$CONFIG_FILE"
    fi
    # Source config
    if ! source "$CONFIG_FILE" 2>/dev/null; then
        error_exit "Failed to source $CONFIG_FILE. Please check its format."
    fi
fi

# -------------------- TUI / Headless Logic --------------------
main_menu() {
    if $HEADLESS; then
        FEATURES="1 2 3 4 5 6"
        log "Headless mode: Running all features with config defaults."
    else
        log "Interactive mode: Prompting for feature selection."
        FEATURES=$(dialog --backtitle "$DIALOG_BACKTITLE" --title "Feature Selection" \
            --checklist "Select features to configure your Jetson Nano:\nUse Space to toggle, Enter to confirm." $DIALOG_HEIGHT $DIALOG_WIDTH 10 \
            1 "Migrate Root Filesystem to USB" off \
            2 "Backup System" off \
            3 "Restore System" off \
            4 "Install AI/ML Libraries" off \
            5 "Install Jupyter Notebook" off \
            6 "Optimize System Performance" off \
            2>&1 >/dev/tty) || {
            log "Cancelled feature selection."
            clear
            exit 0
        }
        clear
        if [ -z "$FEATURES" ]; then
            log "No features selected. Exiting."
            dialog --backtitle "$DIALOG_BACKTITLE" --title "Setup Complete" \
                --msgbox "No features were selected. Setup terminated.\nThis message will close in 30 seconds." 10 50 --timeout 30 2>/dev/null || log "Dialog message failed to display."
            clear
            exit 0
        fi
    fi

    # Collect user inputs in interactive mode
    if ! $HEADLESS; then
        USB_NAME=""
        CONFIRM=""
        UPDATE_FSTAB=""
        BACKUP_DIR=""
        RESTORE_DIR=""
        AI_ML_LIBS=""
        JUPYTER_PORT=""
        JUPYTER_TYPE=""
        JUPYTER_BOOT=""
        JUPYTER_SECURE=""
        JUPYTER_PASSWORD=""
        SWAP_CONFIRM=""

        for feature in $FEATURES; do
            case $feature in
                1)
                    if [ "$ARCH" = "aarch64" ]; then
                        while true; do
                            USB_DEVICES=$(lsblk -d -o NAME,SIZE,MODEL | grep -E '^sd[a-z]' | awk '{print $1 " " $2 " " $3}')
                            if [ -z "$USB_DEVICES" ]; then
                                dialog --backtitle "$DIALOG_BACKTITLE" --title "USB Device Selection" \
                                    --msgbox "No USB devices detected. Please connect a USB drive and retry." 10 50 2>&1 >/dev/tty || true
                                clear
                                dialog --backtitle "$DIALOG_BACKTITLE" --title "Retry" \
                                    --yesno "Retry USB device detection?" 8 50 2>&1 >/dev/tty || error_exit "Cancelled USB device selection."
                                clear
                                continue
                            fi
                            DIALOG_OPTIONS=""
                            while read -r name size model; do
                                DIALOG_OPTIONS="$DIALOG_OPTIONS $name \"$name - $size - $model\" off "
                            done <<< "$USB_DEVICES"
                            USB_NAME=$(dialog --backtitle "$DIALOG_BACKTITLE" --title "USB Device Selection" \
                                --menu "Select a USB device for root migration.\nWARNING: All data on the device will be erased.\nUse arrow keys to select, Enter to confirm." $DIALOG_HEIGHT $DIALOG_WIDTH 10 \
                                $DIALOG_OPTIONS 2>&1 >/dev/tty) && break
                            clear
                            dialog --backtitle "$DIALOG_BACKTITLE" --title "Retry" \
                                --yesno "Retry USB device detection?" 8 50 2>&1 >/dev/tty || error_exit "Cancelled USB device selection."
                            clear
                        done
                        log "Selected USB device: $USB_NAME"
                        dialog --backtitle "$DIALOG_BACKTITLE" --title "Confirm USB Migration" \
                            --yesno "Erase all data on /dev/$USB_NAME for root migration?" 8 50 && CONFIRM="yes" || CONFIRM="no"
                        clear
                        dialog --backtitle "$DIALOG_BACKTITLE" --title "Fstab Configuration" \
                            --yesno "Update /etc/fstab on the USB to use PARTUUID?" 8 50 && UPDATE_FSTAB="yes" || UPDATE_FSTAB="no"
                        clear
                    else
                        CONFIRM="no"
                    fi
                    ;;
                2)
                    BACKUP_DIR=$(dialog --backtitle "$DIALOG_BACKTITLE" --title "Backup Directory" \
                        --inputbox "Enter the directory for system backup:" 10 50 "$DEFAULT_BACKUP_DIR" 2>&1 >/dev/tty) || error_exit "Cancelled backup directory input."
                    clear
                    ;;
                3)
                    RESTORE_DIR=$(dialog --backtitle "$DIALOG_BACKTITLE" --title "Restore Directory" \
                        --inputbox "Enter the directory containing backup files:" 10 50 "$DEFAULT_RESTORE_DIR" 2>&1 >/dev/tty) || error_exit "Cancelled restore directory input."
                    clear
                    ;;
                4)
                    AI_ML_LIBS=$(dialog --backtitle "$DIALOG_BACKTITLE" --title "AI/ML Library Selection" \
                        --checklist "Select AI/ML libraries to install:\nUse Space to toggle, Enter to confirm." 15 50 5 \
                        numpy "NumPy" on \
                        tensorflow "TensorFlow" $([ "$ARCH" = "aarch64" ] && echo "on" || echo "off") \
                        pytorch "PyTorch" $([ "$ARCH" = "aarch64" ] && echo "on" || echo "off") \
                        opencv "OpenCV" on \
                        2>&1 >/dev/tty) || error_exit "Cancelled library selection."
                    clear
                    ;;
                5)
                    JUPYTER_TYPE=$(dialog --backtitle "$DIALOG_BACKTITLE" --title "Jupyter Type Selection" \
                        --menu "Select Jupyter installation type:" 10 40 2 \
                        notebook "Jupyter Notebook" \
                        lab "JupyterLab" \
                        2>&1 >/dev/tty) || error_exit "Cancelled Jupyter type selection."
                    clear
                    JUPYTER_PORT=$(dialog --backtitle "$DIALOG_BACKTITLE" --title "Jupyter Port" \
                        --inputbox "Enter the port for Jupyter server:" 10 40 "$DEFAULT_JUPYTER_PORT" 2>&1 >/dev/tty) || error_exit "Cancelled port input."
                    clear
                    dialog --backtitle "$DIALOG_BACKTITLE" --title "Jupyter Boot Configuration" \
                        --yesno "Start Jupyter automatically on system boot?" 8 50 && JUPYTER_BOOT="yes" || JUPYTER_BOOT="no"
                    clear
                    JUPYTER_SECURE=$(dialog --backtitle "$DIALOG_BACKTITLE" --title "Jupyter Security Mode" \
                        --menu "Select Jupyter access security mode:" 12 60 3 \
                        none "No authentication (insecure, for development only)" \
                        password "Password-protected access" \
                        token "Token-based access (auto-generated)" \
                        2>&1 >/dev/tty) || error_exit "Cancelled security mode selection."
                    clear
                    if [ "$JUPYTER_SECURE" = "password" ]; then
                        while true; do
                            JUPYTER_PASSWORD=$(dialog --backtitle "$DIALOG_BACKTITLE" --title "Jupyter Password" \
                                --insecure --passwordbox "Enter Jupyter password:" 10 50 2>&1 >/dev/tty) || error_exit "Cancelled password input."
                            clear
                            JUPYTER_PASSWORD2=$(dialog --backtitle "$DIALOG_BACKTITLE" --title "Confirm Password" \
                                --insecure --passwordbox "Confirm Jupyter password:" 10 50 2>&1 >/dev/tty) || error_exit "Cancelled password confirmation."
                            clear
                            if [ "$JUPYTER_PASSWORD" = "$JUPYTER_PASSWORD2" ]; then
                                break
                            fi
                            dialog --backtitle "$DIALOG_BACKTITLE" --title "Password Mismatch" \
                                --msgbox "Passwords do not match. Please try again." 8 40 2>/dev/null || log "Dialog message failed to display."
                            clear
                        done
                    fi
                    ;;
                6)
                    dialog --backtitle "$DIALOG_BACKTITLE" --title "Swap Space Configuration" \
                        --yesno "Increase swap space to 4GB for improved performance?" 8 50 && SWAP_CONFIRM="yes" || SWAP_CONFIRM="no"
                    clear
                    ;;
            esac
        done
    fi

    # Execute selected features
    for feature in $FEATURES; do
        case $feature in
            1)
                log "Starting USB root migration..."
                status=$(setup_usb_root "$USB_NAME" "$CONFIRM" "$UPDATE_FSTAB" "$ARCH" 2>&1 | tee -a "$LOGFILE")
                if [ $? -eq 0 ]; then
                    dialog_status="Success: USB root migration completed."
                else
                    dialog_status="Failed: USB root migration encountered errors.\nCheck $LOGFILE for details."
                fi
                if ! $HEADLESS; then
                    dialog --backtitle "$DIALOG_BACKTITLE" --title "USB Root Migration Status" \
                        --msgbox "$dialog_status\nThis message will close in 30 seconds." 10 50 --timeout 30 2>/dev/null || log "Dialog status failed to display."
                    clear
                fi
                ;;
            2)
                log "Starting system backup..."
                status=$(backup_system "$BACKUP_DIR" 2>&1 | tee -a "$LOGFILE")
                if [ $? -eq 0 ]; then
                    dialog_status="Success: System backup completed."
                else
                    dialog_status="Failed: System backup encountered errors.\nCheck $LOGFILE for details."
                fi
                if ! $HEADLESS; then
                    dialog --backtitle "$DIALOG_BACKTITLE" --title "System Backup Status" \
                        --msgbox "$dialog_status\nThis message will close in 30 seconds." 10 50 --timeout 30 2>/dev/null || log "Dialog status failed to display."
                    clear
                fi
                ;;
            3)
                log "Starting system restore..."
                status=$(restore_system "$RESTORE_DIR" 2>&1 | tee -a "$LOGFILE")
                if [ $? -eq 0 ]; then
                    dialog_status="Success: System restore completed."
                else
                    dialog_status="Failed: System restore encountered errors.\nCheck $LOGFILE for details."
                fi
                if ! $HEADLESS; then
                    dialog --backtitle "$DIALOG_BACKTITLE" --title "System Restore Status" \
                        --msgbox "$dialog_status\nThis message will close in 30 seconds." 10 50 --timeout 30 2>/dev/null || log "Dialog status failed to display."
                    clear
                fi
                ;;
            4)
                log "Installing AI/ML libraries..."
                status=$(install_ai_ml_libs "$AI_ML_LIBS" "$ARCH" 2>&1 | tee -a "$LOGFILE")
                if [ $? -eq 0 ]; then
                    dialog_status="Success: AI/ML libraries installed."
                else
                    dialog_status="Failed: AI/ML library installation encountered errors.\nCheck $LOGFILE for details."
                fi
                if ! $HEADLESS; then
                    dialog --backtitle "$DIALOG_BACKTITLE" --title "AI/ML Libraries Status" \
                        --msgbox "$dialog_status\nThis message will close in 30 seconds." 10 50 --timeout 30 2>/dev/null || log "Dialog status failed to display."
                    clear
                fi
                ;;
            5)
                log "Installing Jupyter..."
                status=$(install_jupyter "$JUPYTER_TYPE" "$JUPYTER_PORT" "$JUPYTER_BOOT" "$JUPYTER_SECURE" "$JUPYTER_PASSWORD" 2>&1 | tee -a "$LOGFILE")
                if [ $? -eq 0 ]; then
                    dialog_status="Success: Jupyter installation completed."
                else
                    dialog_status="Failed: Jupyter installation encountered errors.\nCheck $LOGFILE for details."
                fi
                if ! $HEADLESS; then
                    dialog --backtitle "$DIALOG_BACKTITLE" --title "Jupyter Installation Status" \
                        --msgbox "$dialog_status\nThis message will close in 30 seconds." 10 50 --timeout 30 2>/dev/null || log "Dialog status failed to display."
                    clear
                fi
                ;;
            6)
                log "Optimizing system performance..."
                status=$(optimize_performance "$ARCH" "$SWAP_CONFIRM" 2>&1 | tee -a "$LOGFILE")
                if [ $? -eq 0 ]; then
                    dialog_status="Success: System performance optimization completed."
                else
                    dialog_status="Failed: Performance optimization encountered errors.\nCheck $LOGFILE for details."
                fi
                if ! $HEADLESS; then
                    dialog --backtitle "$DIALOG_BACKTITLE" --title "Performance Optimization Status" \
                        --msgbox "$dialog_status\nThis message will close in 30 seconds." 10 50 --timeout 30 2>/dev/null || log "Dialog status failed to display."
                    clear
                fi
                ;;
        esac
    done

    if $HEADLESS; then
        log "Headless setup completed."
    else
        dialog --backtitle "$DIALOG_BACKTITLE" --title "Setup Complete" \
            --msgbox "All selected features have been processed.\nCheck $LOGFILE for details.\nThis message will close in 30 seconds." 10 50 --timeout 30 2>/dev/null || log "Dialog completion message failed to display."
        clear
    fi
}

# -------------------- Main Execution --------------------
log "Starting setup for Jetson Nano (JetPack 4.6.x) or dev environment ($ARCH)..."

# Ensure root privileges
if [ "$EUID" -ne 0 ]; then
    error_exit "This script must be run as root. Use sudo."
fi

# Launch TUI or headless execution
main_menu

log "Setup finished."
clear
exit 0