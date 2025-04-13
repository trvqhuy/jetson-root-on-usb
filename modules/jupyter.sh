#!/bin/bash

install_jupyter() {
    local JUPYTER_TYPE="$1"
    local JUPYTER_PORT="$2"
    local ARCH="$3"
    local ENABLE_ON_BOOT="$4"
    local SECURITY_MODE="$5"  # none | password | token

    log "Installing Jupyter ($JUPYTER_TYPE) on port $JUPYTER_PORT..."

    sudo apt-get update
    sudo apt-get install -y python3-pip python3-dev || error_exit "Failed to install pip tools."
    python3 -m pip install --upgrade pip
    python3 -m pip install notebook jupyterlab jupyter_server

    USER_HOME=$(eval echo ~${SUDO_USER:-$USER})
    CONFIG_DIR="$USER_HOME/.jupyter"
    SERVICE_NAME="jupyter.service"

    sudo -u "$USER" bash -c "
        mkdir -p $CONFIG_DIR
        jupyter notebook --generate-config --allow-root
    "

    case "$SECURITY_MODE" in
        password)
            log "Setting password-based access..."
            JUPYTER_HASH=$(sudo -u "$USER" python3 -c "from notebook.auth import passwd; print(passwd())")
            sudo -u "$USER" bash -c "echo \"c.NotebookApp.password = '$JUPYTER_HASH'\" >> $CONFIG_DIR/jupyter_notebook_config.py"
            ;;
        token)
            FIXED_TOKEN=$(openssl rand -hex 16)
            log "Setting fixed token access: $FIXED_TOKEN"
            sudo -u "$USER" bash -c "
                echo \"c.NotebookApp.token = '$FIXED_TOKEN'\" >> $CONFIG_DIR/jupyter_notebook_config.py
            "
            ;;
        none)
            log "Disabling token and password — open access (dev only)..."
            sudo -u "$USER" bash -c "
                echo \"c.NotebookApp.token = ''\" >> $CONFIG_DIR/jupyter_notebook_config.py
                echo \"c.NotebookApp.password = ''\" >> $CONFIG_DIR/jupyter_notebook_config.py
            "
            ;;
        *)
            error_exit "Unknown SECURITY_MODE: $SECURITY_MODE"
            ;;
    esac

    JUPYTER_CMD="jupyter $JUPYTER_TYPE --config=$CONFIG_DIR/jupyter_notebook_config.py --ip=0.0.0.0 --port=$JUPYTER_PORT"

    sudo bash -c "cat > /etc/systemd/system/$SERVICE_NAME" <<EOF
[Unit]
Description=Jupyter Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/env bash -c 'cd $USER_HOME && $JUPYTER_CMD'
User=$USER
WorkingDirectory=$USER_HOME
Restart=always
Environment=PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reexec
    sudo systemctl daemon-reload
    sudo systemctl start $SERVICE_NAME

    if [ "$ENABLE_ON_BOOT" = "yes" ]; then
        sudo systemctl enable $SERVICE_NAME
        log "Enabled on boot."
    else
        sudo systemctl disable $SERVICE_NAME
        log "Not enabled on boot."
    fi

    IP_ADDRESS=$(ip route get 1 | awk '{print $7; exit}')
    log "✅ Jupyter $JUPYTER_TYPE is running."

    case "$SECURITY_MODE" in
        none)
            log "🌐 Access: http://$IP_ADDRESS:$JUPYTER_PORT"
            ;;
        password)
            log "🔐 Password required. Access via: http://$IP_ADDRESS:$JUPYTER_PORT"
            ;;
        token)
            log "🔑 Token-based access:"
            log "🌐 http://$IP_ADDRESS:$JUPYTER_PORT/?token=$FIXED_TOKEN"
            ;;
    esac
}
