#!/bin/bash

# install_jupyter.sh
# Installs Jupyter (Notebook or Lab) on NVIDIA Jetson devices with configurable options.

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

# Warning function for non-critical issues
warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" | tee -a "$LOGFILE"
}

install_jupyter() {
    local JUPYTER_TYPE="$1"        # notebook or lab
    local JUPYTER_PORT="$2"        # port number (e.g., 8888)
    local JUPYTER_BOOT="$3"        # yes or no (enable on boot)
    local JUPYTER_SECURE="$4"      # password, token, or none
    local JUPYTER_PASSWORD="$5"    # password for secure mode
    LOGFILE="/var/log/jupyter_install.log"

    log "Starting Jupyter ($JUPYTER_TYPE) installation on port $JUPYTER_PORT..."

    # Validate inputs
    if [ -z "$JUPYTER_TYPE" ] || [ -z "$JUPYTER_PORT" ] || [ -z "$JUPYTER_BOOT" ] || [ -z "$JUPYTER_SECURE" ]; then
        log "Error: Missing required parameters (type, port, boot, secure)."
        return 1
    fi
    if [ "$JUPYTER_SECURE" = "password" ] && [ -z "$JUPYTER_PASSWORD" ]; then
        log "Error: Password required for secure mode but not provided."
        return 1
    fi
    if [ "$JUPYTER_TYPE" != "notebook" ] && [ "$JUPYTER_TYPE" != "lab" ]; then
        log "Error: Invalid Jupyter type: $JUPYTER_TYPE. Use 'notebook' or 'lab'."
        return 1
    fi
    if ! [[ "$JUPYTER_PORT" =~ ^[0-9]+$ ]] || [ "$JUPYTER_PORT" -lt 1024 ] || [ "$JUPYTER_PORT" -gt 65535 ]; then
        log "Error: Invalid port: $JUPYTER_PORT. Must be between 1024 and 65535."
        return 1
    fi
    if [ "$JUPYTER_BOOT" != "yes" ] && [ "$JUPYTER_BOOT" != "no" ]; then
        log "Error: Invalid boot option: $JUPYTER_BOOT. Use 'yes' or 'no'."
        return 1
    fi
    if [ "$JUPYTER_SECURE" != "password" ] && [ "$JUPYTER_SECURE" != "token" ] && [ "$JUPYTER_SECURE" != "none" ]; then
        log "Error: Invalid security mode: $JUPYTER_SECURE. Use 'password', 'token', or 'none'."
        return 1
    fi

    # Ensure log file is writable
    sudo touch "$LOGFILE" && sudo chmod 666 "$LOGFILE" 2>/dev/null || {
        log "Error: Cannot create or modify log file at $LOGFILE."
        return 1
    }

    # Check available disk space (at least 1GB recommended)
    if [ "$(df -h / | tail -1 | awk '{print $4}' | grep -o '[0-9]\+')" -lt 1000 ]; then
        warn "Low disk space (<1GB). Installation may fail."
    fi

    # Repair package manager
    log "Verifying package manager..."
    sudo dpkg --configure -a 2>&1 | tee -a "$LOGFILE" || {
        log "Error: Failed to configure dpkg."
        return 1
    }
    sudo apt update 2>&1 | tee -a "$LOGFILE" || {
        log "Error: Failed to update package lists."
        return 1
    }
    sudo apt install -f -y 2>&1 | tee -a "$LOGFILE" || warn "Failed to fix broken packages, continuing..."

    # Install dependencies
    log "Installing Python dependencies..."
    sudo apt install -y python3-pip python3-dev python3-venv 2>&1 | tee -a "$LOGFILE" || {
        log "Error: Failed to install python3-pip, python3-dev, or python3-venv."
        return 1
    }
    python3 -m pip install --upgrade pip --no-cache-dir 2>&1 | tee -a "$LOGFILE" || {
        log "Error: Failed to upgrade pip."
        return 1
    }

    # Create and activate virtual environment
    log "Setting up virtual environment..."
    sudo rm -rf /opt/jupyter_env 2>/dev/null
    sudo mkdir -p /opt/jupyter_env && sudo chmod 755 /opt/jupyter_env
    python3 -m venv /opt/jupyter_env 2>&1 | tee -a "$LOGFILE" || {
        log "Error: Failed to create virtual environment."
        return 1
    }
    source /opt/jupyter_env/bin/activate || {
        log "Error: Failed to activate virtual environment."
        return 1
    }

    # Install Jupyter
    log "Installing Jupyter ($JUPYTER_TYPE)..."
    if [ "$JUPYTER_TYPE" = "notebook" ]; then
        python3 -m pip install jupyter notebook --no-cache-dir 2>&1 | tee -a "$LOGFILE" || {
            log "Error: Failed to install Jupyter Notebook."
            deactivate
            return 1
        }
    else
        python3 -m pip install jupyterlab --no-cache-dir 2>&1 | tee -a "$LOGFILE" || {
            log "Error: Failed to install JupyterLab."
            deactivate
            return 1
        }
    fi
    deactivate

    # Configure Jupyter
    USER_HOME=$(eval echo ~${SUDO_USER:-$USER})
    CONFIG_DIR="$USER_HOME/.jupyter"
    CONFIG_FILE="$CONFIG_DIR/jupyter_notebook_config.py"
    log "Configuring Jupyter..."
    sudo -u "${SUDO_USER:-$USER}" mkdir -p "$CONFIG_DIR" 2>&1 | tee -a "$LOGFILE" || {
        log "Error: Failed to create config directory ($CONFIG_DIR)."
        return 1
    }
    sudo -u "${SUDO_USER:-$USER}" /opt/jupyter_env/bin/jupyter notebook --generate-config --allow-root 2>&1 | tee -a "$LOGFILE" || {
        log "Error: Failed to generate Jupyter config."
        return 1
    }

    # Set security mode
    log "Configuring security mode ($JUPYTER_SECURE)..."
    case "$JUPYTER_SECURE" in
        password)
            JUPYTER_HASH=$(sudo -u "${SUDO_USER:-$USER}" /opt/jupyter_env/bin/python3 -c "from notebook.auth import passwd; print(passwd('$JUPYTER_PASSWORD'))" 2>&1 | tee -a "$LOGFILE") || {
                log "Error: Failed to hash password."
                return 1
            }
            echo "c.NotebookApp.password = '$JUPYTER_HASH'" | sudo -u "${SUDO_USER:-$USER}" tee -a "$CONFIG_FILE" >/dev/null || {
                log "Error: Failed to configure password."
                return 1
            }
            ;;
        token)
            FIXED_TOKEN=$(openssl rand -hex 16)
            log "Generated token: $FIXED_TOKEN"
            echo "c.NotebookApp.token = '$FIXED_TOKEN'" | sudo -u "${SUDO_USER:-$USER}" tee -a "$CONFIG_FILE" >/dev/null || {
                log "Error: Failed to configure token."
                return 1
            }
            ;;
        none)
            log "Configuring open access (insecure)..."
            echo "c.NotebookApp.token = ''" | sudo -u "${SUDO_USER:-$USER}" tee -a "$CONFIG_FILE" >/dev/null || {
                log "Error: Failed to configure open access (token)."
                return 1
            }
            echo "c.NotebookApp.password = ''" | sudo -u "${SUDO_USER:-$USER}" tee -a "$CONFIG_FILE" >/dev/null || {
                log "Error: Failed to configure open access (password)."
                return 1
            }
            ;;
    esac
    # Set IP and port
    echo "c.NotebookApp.ip = '0.0.0.0'" | sudo -u "${SUDO_USER:-$USER}" tee -a "$CONFIG_FILE" >/dev/null
    echo "c.NotebookApp.port = $JUPYTER_PORT" | sudo -u "${SUDO_USER:-$USER}" tee -a "$CONFIG_FILE" >/dev/null

    # Create start script
    log "Creating start script..."
    sudo bash -c "cat > /usr/local/bin/start-jupyter.sh" <<EOF
#!/bin/bash
source /opt/jupyter_env/bin/activate
exec /opt/jupyter_env/bin/jupyter $JUPYTER_TYPE --config="$CONFIG_FILE" --ip=0.0.0.0 --port=$JUPYTER_PORT
EOF
    sudo chmod +x /usr/local/bin/start-jupyter.sh 2>&1 | tee -a "$LOGFILE" || {
        log "Error: Failed to create or set permissions for start script."
        return 1
    }

    # Configure systemd service
    SERVICE_NAME="jupyter.service"
    log "Setting up systemd service..."
    sudo bash -c "cat > /etc/systemd/system/$SERVICE_NAME" <<EOF
[Unit]
Description=Jupyter $JUPYTER_TYPE Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/start-jupyter.sh
User=${SUDO_USER:-$USER}
WorkingDirectory=$USER_HOME
Restart=always
Environment=PATH=/opt/jupyter_env/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload 2>&1 | tee -a "$LOGFILE" || {
        log "Error: Failed to reload systemd daemon."
        return 1
    }

    if [ "$JUPYTER_BOOT" = "yes" ]; then
        sudo systemctl enable "$SERVICE_NAME" 2>&1 | tee -a "$LOGFILE" || {
            log "Error: Failed to enable Jupyter service."
            return 1
        }
        log "Jupyter service enabled on boot."
    else
        sudo systemctl disable "$SERVICE_NAME" 2>&1 | tee -a "$LOGFILE" || warn "Failed to disable Jupyter service."
        log "Jupyter service not enabled on boot."
    fi

    # Start service
    log "Starting Jupyter service..."
    sudo systemctl start "$SERVICE_NAME" 2>&1 | tee -a "$LOGFILE" || {
        log "Error: Failed to start Jupyter service."
        return 1
    }

    # Verify service is running
    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        log "Error: Jupyter service failed to start."
        journalctl -u "$SERVICE_NAME" -n 50 --no-pager | tee -a "$LOGFILE"
        return 1
    fi

    # Log access instructions
    IP_ADDRESS=$(ip route get 1 | awk '{print $7; exit}' || echo "localhost")
    log "Jupyter $JUPYTER_TYPE installation completed successfully."
    case "$JUPYTER_SECURE" in
        none)
            log "Access at: http://$IP_ADDRESS:$JUPYTER_PORT"
            ;;
        password)
            log "Access at: http://$IP_ADDRESS:$JUPYTER_PORT (use password: [hidden for security])"
            ;;
        token)
            log "Access at: http://$IP_ADDRESS:$JUPYTER_PORT/?token=$FIXED_TOKEN"
            ;;
    esac

    return 0
}

# Example usage (uncomment to run):
# install_jupyter "lab" "8888" "yes" "password" "mysecret"
# install_jupyter "notebook" "8888" "no" "token" ""
# install_jupyter "lab" "8888" "yes" "none" ""

# If called directly, print usage
# if [ "$#" -gt 0 ]; then
#     install_jupyter "$@"
# else
#     echo "Usage: $0 <type> <port> <boot> <secure> [password]"
#     echo "  type: notebook or lab"
#     echo "  port: e.g., 8888"
#     echo "  boot: yes or no"
#     echo "  secure: password, token, or none"
#     echo "  password: required if secure=password"
#     exit 1
# fi