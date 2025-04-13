#!/bin/bash

set -e

# -------------------- CONFIG --------------------
CONFIG_FILE="config/jetson-setup.conf"
LOG_DIR="logs/jetson-setup"
LOGFILE="$LOG_DIR/setup.log"
MODULE_DIR="$(dirname "$0")/modules"
TIMEOUT=30
HEADLESS=false

# Default values (used only for creating config file in headless mode)
DEFAULT_USB_NAME="sda"
DEFAULT_CONFIRM="yes"
DEFAULT_UPDATE_FSTAB="yes"
DEFAULT_BACKUP_DIR="/mnt/usb/backup"
DEFAULT_AI_ML_LIBS="numpy tensorflow pytorch opencv"
DEFAULT_JUPYTER_PORT="8888"
DEFAULT_JUPYTER_TYPE="notebook"

# Parse arguments
if [ "$1" = "--headless" ]; then
    HEADLESS=true
fi

# Logging functions
log() {
    echo -e "[INFO] $1" | tee -a "$LOGFILE"
}

warn() {
    echo -e "[WARN] $1" | tee -a "$LOGFILE"
}

error_exit() {
    echo -e "[ERROR] $1" | tee -a "$LOGFILE"
    if ! $HEADLESS; then
        dialog --msgbox "Error: $1\nCheck $LOGFILE for details." 10 50 || echo "Dialog failed to display error."
        clear
    fi
    exit 1
}

# Create log and config directories
sudo mkdir -p "$LOG_DIR" "$(dirname "$CONFIG_FILE")"
sudo touch "$LOGFILE"
sudo chmod 644 "$LOGFILE"

# Ensure dialog is installed (only needed for interactive mode)
if ! $HEADLESS; then
    if ! command -v dialog &> /dev/null; then
        log "Installing dialog..."
        sudo apt update >> "$LOGFILE" 2>&1 || error_exit "Failed to update package lists."
        sudo apt install -y dialog >> "$LOGFILE" 2>&1 || error_exit "Failed to install dialog."
    fi
    # Verify terminal environment
    if [ -z "$TERM" ] || [ "$TERM" = "dumb" ]; then
        export TERM=xterm
        log "Set TERM=xterm due to invalid or missing TERM."
    fi
    tty > /dev/null 2>&1 || error_exit "No TTY available. Run in an interactive terminal or use --headless."
    # Check terminal size
    read rows cols < <(stty size)
    if [ "$rows" -lt 20 ] || [ "$cols" -lt 60 ]; then
        warn "Terminal size ($rows x $cols) too small for dialog. Resizing recommended."
    fi
fi

# Source module scripts
for module in "$MODULE_DIR"/*.sh; do
    [ -f "$module" ] || error_exit "Module not found: $module"
    source "$module"
done

# Check architecture
ARCH=$(uname -m)
if [ "$ARCH" != "aarch64" ] && ! $HEADLESS; then
    dialog --msgbox "Warning: This script is optimized for Jetson Nano (ARM64). Running on $ARCH. Some features (e.g., USB root migration, Jetson-specific libraries) may be skipped or simulated." 10 60 || log "Dialog warning failed to display."
    clear
fi

# Create default config if headless and not exists
if $HEADLESS; then
    if [ ! -f "$CONFIG_FILE" ]; then
        log "Creating default config file: $CONFIG_FILE"
        sudo bash -c "cat > $CONFIG_FILE" << 'EOL'
USB_NAME=sda
CONFIRM=yes
UPDATE_FSTAB=yes
BACKUP_DIR=/mnt/usb/backup
AI_ML_LIBS="numpy tensorflow pytorch opencv"
JUPYTER_PORT=8888
JUPYTER_TYPE=notebook
EOL
        sudo chmod 644 "$CONFIG_FILE"
    fi

    # Source config in headless mode
    if ! source "$CONFIG_FILE" 2>/dev/null; then
        error_exit "Failed to source $CONFIG_FILE. Please check its format."
    fi
fi

# -------------------- TUI / Headless Logic --------------------
main_menu() {
    if $HEADLESS; then
        # In headless mode, select all features
        FEATURES="1 2 3 4 5 6"
        log "Headless mode: Running all features with config defaults."
    else
        log "Interactive mode: Prompt for feature selections."
        # Interactive mode: Prompt for feature selection
        FEATURES=$(dialog --checklist "Select features to set up:" 20 60 10 \
            1 "Migrate root to USB" off \
            2 "Backup system" on \
            3 "Restore system" off \
            4 "Install AI/ML libraries" on \
            5 "Install Jupyter" on \
            6 "Optimize performance" on \
            2>&1 >/dev/tty) || {
            log "Cancelled feature selection."
            clear
            exit 0
        }
        clear
        if [ -z "$FEATURES" ]; then
            log "No features selected. Exiting."
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
        AI_ML_LIBS=""
        JUPYTER_PORT=""
        JUPYTER_TYPE=""

        for feature in $FEATURES; do
            case $feature in
                1)
                    # USB selection handled here ONLY
                    DEVICE_LIST=$(lsblk -dpno NAME,MODEL,SIZE,TYPE | grep -E 'disk' | grep -v 'mmcblk\|loop')
                    CHOICES=()
                    while IFS= read -r line; do
                        DEV=$(echo "$line" | awk '{print $1}')
                        DESC=$(echo "$line" | sed "s|$DEV||")
                        CHOICES+=("$DEV" "$DESC")
                    done <<< "$DEVICE_LIST"

                    USB_PATH=$(dialog --title "Select USB device" --menu "Choose USB for root migration:" 15 60 6 "${CHOICES[@]}" 2>&1 >/dev/tty) || error_exit "USB selection cancelled."
                    USB_NAME=$(basename "$USB_PATH")
                    clear

                    if [ "$ARCH" != "aarch64" ]; then
                        dialog --msgbox "Non-Jetson detected. Simulating only." 8 50
                        clear
                        CONFIRM="no"
                    else
                        dialog --yesno "Erase ALL data on /dev/$USB_NAME?" 8 50 && CONFIRM="yes" || CONFIRM="no"
                        clear
                        dialog --yesno "Update /etc/fstab on USB?" 8 50 && UPDATE_FSTAB="yes" || UPDATE_FSTAB="no"
                        clear
                    fi
                    ;;

                2)
                    # List mounted drives under /mnt or /media
                    MOUNTED_DEVICES=$(lsblk -o NAME,MOUNTPOINT | grep -E '/mnt|/media' | awk '$2!=""')
                    CHOICES=()

                    while read -r name mountpoint; do
                        device="/dev/$name"
                        CHOICES+=("$mountpoint" "$device")
                    done <<< "$MOUNTED_DEVICES"

                    if [ ${#CHOICES[@]} -eq 0 ]; then
                        dialog --msgbox "No mounted USB/SD devices found under /mnt or /media.\nPlease mount a backup destination and try again." 10 60
                        clear
                        exit 1
                    fi

                    BACKUP_TARGET=$(dialog --menu "Select where to save the system backup:" 15 60 6 "${CHOICES[@]}" 2>&1 >/dev/tty) || error_exit "Cancelled."
                    clear
                    ;;


                3)
                    # Step 1: Select backup device
                    BACKUP_DEV_LIST=$(lsblk -o NAME,MOUNTPOINT | grep -E '/mnt|/media' | awk '$2!=""')
                    CHOICES=()
                    while read -r name mountpoint; do
                        CHOICES+=("$mountpoint" "/dev/$name")
                    done <<< "$BACKUP_DEV_LIST"

                    if [ ${#CHOICES[@]} -eq 0 ]; then
                        dialog --msgbox "No mounted devices with backups found." 8 50
                        clear
                        exit 1
                    fi

                    BACKUP_PARENT=$(dialog --menu "Select drive where backup is stored:" 15 60 6 "${CHOICES[@]}" 2>&1 >/dev/tty) || error_exit "Cancelled backup device selection."
                    clear

                    # Step 2: Select folder inside that path
                    BACKUP_SOURCE=$(dialog --dselect "$BACKUP_PARENT/" 15 60 2>&1 >/dev/tty) || error_exit "Cancelled folder selection."
                    clear

                    # Step 3: Select restore target
                    RESTORE_TARGET=$(dialog --inputbox "Enter path to restore to (must be mounted, e.g. /mnt/usb):" 8 60 "/mnt/usb" 2>&1 >/dev/tty) || error_exit "Cancelled restore target."
                    clear
                    ;;

                4)
                    AI_ML_LIBS=$(dialog --checklist "Select AI/ML libraries:" 15 50 5 \
                        numpy "NumPy" on \
                        tensorflow "TensorFlow" $([ "$ARCH" = "aarch64" ] && echo "on" || echo "off") \
                        pytorch "PyTorch" $([ "$ARCH" = "aarch64" ] && echo "on" || echo "off") \
                        opencv "OpenCV" on \
                        2>&1 >/dev/tty) || error_exit "Cancelled library selection."
                    clear
                    ;;

                5)
                    JUPYTER_TYPE=$(dialog --menu "Select Jupyter type:" 10 40 2 \
                        notebook "Jupyter Notebook" \
                        lab "JupyterLab" \
                        2>&1 >/dev/tty) || error_exit "Cancelled."
                    clear

                    JUPYTER_PORT=$(dialog --inputbox "Enter Jupyter port:" 8 40 "8888" 2>&1 >/dev/tty) || error_exit "Cancelled."
                    clear

                    dialog --yesno "Start Jupyter on boot?" 8 50 && JUPYTER_BOOT="yes" || JUPYTER_BOOT="no"
                    clear

                    JUPYTER_SECURE=$(dialog --menu "Select Jupyter access mode:" 12 60 3 \
                        none "No password, no token (insecure)" \
                        password "Password protected" \
                        token "Fixed token (auto generated)" \
                        2>&1 >/dev/tty) || error_exit "Cancelled Jupyter access mode."
                    clear
                    if [ "$JUPYTER_SECURE" = "password" ]; then
                        JUPYTER_PASSWORD=$(dialog --insecure --passwordbox "Enter Jupyter password:" 10 50 2>&1 >/dev/tty) || error_exit "Password input cancelled."
                        clear
                        JUPYTER_PASSWORD2=$(dialog --insecure --passwordbox "Confirm password:" 10 50 2>&1 >/dev/tty) || error_exit "Password confirmation cancelled."
                        clear

                        if [ "$JUPYTER_PASSWORD" != "$JUPYTER_PASSWORD2" ]; then
                            dialog --msgbox "Passwords do not match. Exiting." 8 40
                            clear
                            exit 1
                        fi
                    fi
                    ;;


            esac
        done
    fi

    # Execute selected features
    for feature in $FEATURES; do
        case $feature in
            1) setup_usb_root "$USB_NAME" "$CONFIRM" "$UPDATE_FSTAB" "$ARCH" ;;
            2) backup_system "$BACKUP_DIR" ;;
            3) restore_system "$BACKUP_DIR" ;;
            4) install_ai_ml_libs "$AI_ML_LIBS" "$ARCH" ;;
            5) install_jupyter "$JUPYTER_TYPE" "$JUPYTER_PORT" "$ARCH" "$JUPYTER_BOOT" "$JUPYTER_SECURE" "$JUPYTER_PASSWORD" ;;
            6) optimize_performance "$ARCH" ;;
        esac
    done

    if $HEADLESS; then
        log "Headless setup completed."
    else
        dialog --msgbox "Setup completed successfully!\nLog: $LOGFILE" 10 50 || log "Dialog completion message failed to display."
        clear
    fi
}

# -------------------- Main Execution --------------------
log "Starting setup for Jetson Nano (JetPack 4.6.x) or dev environment ($ARCH)..."

# Ensure root privileges
if [ "$EUID" -ne 0 ]; then
    error_exit "Please run as root (sudo)."
fi

# Update system
log "Updating system packages..."
sudo apt update >> "$LOGFILE" 2>&1 || error_exit "Failed to update system."

# Launch TUI or headless execution
main_menu

log "Setup finished."
clear
exit 0