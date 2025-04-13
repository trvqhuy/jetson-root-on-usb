#!/bin/bash

install_jupyter() {
    log "Installing Jupyter..."

    # Install pip and venv
    sudo apt install -y python3-pip python3-venv >> "$LOGFILE" 2>&1 || error_exit "Failed to install pip/venv."

    # Prompt for Jupyter type
    JUPYTER_TYPE=$(dialog --menu "Select Jupyter type:" 10 40 2 \
        notebook "Jupyter Notebook" \
        lab "JupyterLab" \
        2>&1 >/dev/tty) || error_exit "Cancelled Jupyter type selection."

    # Create virtual environment
    log "Setting up virtual environment..."
    python3 -m venv /opt/jupyter_env >> "$LOGFILE" 2>&1 || error_exit "Failed to create venv."
    source /opt/jupyter_env/bin/activate

    # Install Jupyter
    if [ "$JUPYTER_TYPE" = "notebook" ]; then
        log "Installing Jupyter Notebook..."
        python3 -m pip install jupyter >> "$LOGFILE" 2>&1 || error_exit "Failed to install Jupyter Notebook."
    else
        log "Installing JupyterLab..."
        python3 -m pip install jupyterlab >> "$LOGFILE" 2>&1 || error_exit "Failed to install JupyterLab."
    fi

    # Prompt for port
    JUPYTER_PORT=$(dialog --inputbox "Enter Jupyter port:" 8 40 "$JUPYTER_PORT" 2>&1 >/dev/tty) || error_exit "Cancelled port input."

    # Create start script
    sudo bash -c "cat > /usr/local/bin/start-jupyter.sh" << EOL
#!/bin/bash
source /opt/jupyter_env/bin/activate
jupyter $JUPYTER_TYPE --ip=0.0.0.0 --port=$JUPYTER_PORT
EOL
    sudo chmod +x /usr/local/bin/start-jupyter.sh

    log "Jupyter installed. Run 'start-jupyter.sh' to launch."
}