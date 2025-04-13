#!/bin/bash

install_jupyter() {
    local JUPYTER_TYPE="$1"
    local JUPYTER_PORT="$2"
    local JUPYTER_BOOT="$3"
    local JUPYTER_SECURE="$4"
    local JUPYTER_PASSWORD="$5"

    log "Installing Jupyter ($JUPYTER_TYPE) on port $JUPYTER_PORT..."

    # Validate inputs
    if [ -z "$JUPYTER_TYPE" ] || [ -z "$JUPYTER_PORT" ] || [ -z "$JUPYTER_BOOT" ] || [ -z "$JUPYTER_SECURE" ]; then
        log "Invalid parameters for Jupyter installation."
        return 1
    fi
    if [ "$JUPYTER_SECURE" = "password" ] && [ -z "$JUPYTER_PASSWORD" ]; then
        log "Password required for secure mode but not provided."
        return 1
    fi

    # Repair dpkg if interrupted
    log "Verifying package manager status..."
    sudo dpkg --configure -a 2>&1 | tee -a "$LOGFILE" || {
        log "Failed to configure dpkg."
        return 1
    }
    sudo apt install -f -y 2>&1 | tee -a "$LOGFILE" || warn "Failed to fix broken packages, but continuing..."

    # Install dependencies
    log "Installing python3-pip and python3-venv..."
    sudo apt update 2>&1 | tee -a "$LOGFILE" || {
        log "Failed to update package lists."
        return 1
    }
    sudo apt install -y python3-pip python3-venv python3-dev 2>&1 | tee -a "$LOGFILE" || {
        log "Failed to install python3-pip, python3-venv, or python3-dev."
        return 1
    }
    python3 -m pip install --upgrade pip 2>&1 | tee -a "$LOGFILE" || {
        log "Failed to upgrade pip."
        return 1
    }

    # Create virtual environment
    log "Setting up virtual environment..."
    sudo rm -rf /opt/jupyter_env 2>/dev/null
    python3 -m venv /opt/jupyter_env 2>&1 | tee -a "$LOGFILE" || {
        log "Failed to create virtual environment."
        return 1
    }
    source /opt/jupyter_env/bin/activate

    # Install Jupyter
    if [ "$JUPYTER_TYPE" = "notebook" ]; then
        log "Installing Jupyter Notebook..."
        python3 -m pip install jupyter 2>&1 | tee -a "$LOGFILE" || {
            log "Failed to install Jupyter Notebook."
            return 1
        }
    elif [ "$JUPYTER_TYPE" = "lab" ]; then
        log "Installing JupyterLab..."
        python3 -m pip install jupyterlab 2>&1 | tee -a "$LOGFILE" || {
            log "Failed to install JupyterLab."
            return 1
        }
    else
        log "Invalid Jupyter type: $JUPYTER_TYPE."
        return 1
    }
    python3 -m pip install jupyter_server 2>&1 | tee -a "$LOGFILE" || warn "Failed to install jupyter_server."

    # Configure Jupyter
    USER_HOME=$(eval echo ~${SUDO_USER:-$USER})
    CONFIG_DIR="$USER_HOME/.jupyter"
    log "Configuring Jupyter settings..."
    sudo -u "$SUDO_USER" mkdir -p "$CONFIG_DIR" 2>&1 | tee -a "$LOGFILE" || {
        log "Failed to create Jupyter config directory."
        return 1
    }
    sudo -u "$SUDO_USER" jupyter notebook --generate-config --allow-root 2>&1 | tee -a "$LOGFILE" || {
        log "Failed to generate Jupyter config."
        return 1
    }

    # Set security mode
    case "$JUPYTER_SECURE" in
        password)
            log "Configuring password-protected access..."
            JUPYTER_HASH=$(sudo -u "$SUDO_USER" python3 -c "from notebook.auth import passwd; print(passwd('$JUPYTER_PASSWORD'))" 2>&1 | tee -a "$LOGFILE") || {
                log "Failed to hash password."
                return 1
            }
            sudo -u "$SUDO_USER" bash -c "echo \"c.NotebookApp.password = '$JUPYTER_HASH'\" >> $CONFIG_DIR/jupyter_notebook_config.py" 2>&1 | tee -a "$LOGFILE" || {
                log "Failed to configure password."
                return 1
            }
            ;;
        token)
            FIXED_TOKEN=$(openssl rand -hex 16)
            log "Configuring token-based access: $FIXED_TOKEN"
            sudo -u "$SUDO_USER" bash -c "echo \"c.NotebookApp.token = '$FIXED_TOKEN'\" >> $CONFIG_DIR/jupyter_notebook_config.py" 2>&1 | tee -a "$LOGFILE" || {
                log "Failed to configure token."
                return 1
            }
            ;;
        none)
            log "Configuring open access (insecure)..."
            sudo -u "$SUDO_USER" bash -c "echo \"c.NotebookApp.token = ''\" >> $CONFIG_DIR/jupyter_notebook_config.py" 2>&1 | tee -a "$LOGFILE" || {
                log "Failed to configure open access."
                return 1
            }
            sudo -u "$SUDO_USER" bash -c "echo \"c.NotebookApp.password = ''\" >> $CONFIG_DIR/jupyter_notebook_config.py" 2>&1 | tee -a "$LOGFILE" || {
                log "Failed to configure open access."
                return 1
            }
            ;;
        *)
            log "Unknown security mode: $JUPYTER_SECURE."
            return 1
            ;;
    esac

    # Create start script
    log "Creating Jupyter start script..."
    JUPYTER_CMD="/opt/jupyter_env/bin/jupyter $JUPYTER_TYPE --config=$CONFIG_DIR/jupyter_notebook_config.py --ip=0.0.0.0 --port=$JUPYTER_PORT"
    sudo bash -c "cat > /usr/local/bin/start-jupyter.sh" <<EOF
#!/bin/bash
source /opt/jupyter_env/bin/activate
$JUPYTER_CMD
EOF
    sudo chmod +x /usr/local/bin/start-jupyter.sh 2>&1 | tee -a "$LOGFILE" || {
        log "Failed to create Jupyter start script."
        return 1
    }

    # Configure systemd service
    SERVICE_NAME="jupyter.service"
    log "Configuring Jupyter systemd service..."
    sudo bash -c "cat > /etc/systemd/system/$SERVICE_NAME" <<EOF
[Unit]
Description=Jupyter Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/start-jupyter.sh
User=$SUDO_USER
WorkingDirectory=$USER_HOME
Restart=always
Environment=PATH=/opt/jupyter_env/bin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload 2>&1 | tee -a "$LOGFILE" || {
        log "Failed to reload systemd daemon."
        return 1
    }

    if [ "$JUPYTER_BOOT" = "yes" ]; then
        sudo systemctl enable $SERVICE_NAME 2>&1 | tee -a "$LOGFILE" || {
            log "Failed to enable Jupyter service on boot."
            return 1
        }
        log "Jupyter service enabled on boot."
    else
        sudo systemctl disable $SERVICE_NAME 2>&1 | tee -a "$LOGFILE" || warn "Failed to disable Jupyter service."
        log "Jupyter service not enabled on boot."
    fi

    # Start service
    sudo systemctl start $SERVICE_NAME 2>&1 | tee -a "$LOGFILE" || {
        log "Failed to start Jupyter service."
        return 1
    }

    # Log access instructions
    IP_ADDRESS=$(ip route get 1 | awk '{print $7; exit}')
    log "Jupyter $JUPYTER_TYPE installation completed."
    case "$JUPYTER_SECURE" in
        none)
            log "Access Jupyter at: http://$IP_ADDRESS:$JUPYTER_PORT"
            ;;
        password)
            log "Access Jupyter at: http://$IP_ADDRESS:$JUPYTER_PORT (password required)"
            ;;
        token)
            log "Access Jupyter at: http://$IP_ADDRESS:$JUPYTER_PORT/?token=$FIXED_TOKEN"
            ;;
    esac

    return 0
}