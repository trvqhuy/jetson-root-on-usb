#!/bin/bash

install_jupyter() {
    local JUPYTER_TYPE="$1"
    local JUPYTER_PORT="$2"

    log "Installing Jupyter..."

    # Validate inputs
    if [ -z "$JUPYTER_TYPE" ] || [ -z "$JUPYTER_PORT" ]; then
        error_exit "Jupyter type or port not provided."
    fi

    # Install pip and venv
    sudo apt install -y python3-pip python3-venv >> "$LOGFILE" 2>&1 || error_exit "Failed to install pip/venv."

    # Create virtual environment
    log "Setting up virtual environment..."
    python3 -m venv /opt/jupyter_env >> "$LOGFILE" 2>&1 || error_exit "Failed to create venv."
    source /opt/jupyter_env/bin/activate

    # Install Jupyter
    if [ "$JUPYTER_TYPE" = "notebook" ]; then
        log "Installing Jupyter Notebook..."
        python3 -m pip install jupyter >> "$LOGFILE" 2>&1 || error_exit "Failed to install Jupyter Notebook."
    elif [ "$JUPYTER_TYPE" = "lab" ]; then
        log "Installing JupyterLab..."
        python3 -m pip install jupyterlab >> "$LOGFILE" 2>&1 || error_exit "Failed to install JupyterLab."
    else
        error_exit "Invalid Jupyter type: $JUPYTER_TYPE"
    fi

    # Create start script
    sudo bash -c "cat > /usr/local/bin/start-jupyter.sh" << EOL
#!/bin/bash
source /opt/jupyter_env/bin/activate
jupyter $JUPYTER_TYPE --ip=0.0.0.0 --port=$JUPYTER_PORT
EOL
    sudo chmod +x /usr/local/bin/start-jupyter.sh

    log "Jupyter installed. Run 'start-jupyter.sh' to launch."
}