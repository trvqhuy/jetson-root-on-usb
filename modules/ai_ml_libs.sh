#!/bin/bash

install_ai_ml_libs() {
    log "Installing AI/ML libraries..."

    # Install pip
    log "Installing python3-pip..."
    sudo apt install -y python3-pip >> "$LOGFILE" 2>&1 || error_exit "Failed to install pip."

    # Prompt for libraries
    LIBS=$(dialog --checklist "Select AI/ML libraries to install:" 15 50 5 \
        numpy "NumPy" on \
        tensorflow "TensorFlow" on \
        pytorch "PyTorch" on \
        opencv "OpenCV" on \
        2>&1 >/dev/tty) || error_exit "Cancelled library selection."

    for lib in $LIBS; do
        case $lib in
            numpy)
                log "Installing NumPy..."
                python3 -m pip install numpy >> "$LOGFILE" 2>&1 || error_exit "Failed to install NumPy."
                ;;
            tensorflow)
                log "Installing TensorFlow..."
                python3 -m pip install --extra-index-url https://developer.download.nvidia.com/compute/redist/jp/v46 tensorflow >> "$LOGFILE" 2>&1 || error_exit "Failed to install TensorFlow."
                ;;
            pytorch)
                log "Installing PyTorch..."
                # Example for JetPack 4.6 (update URL as needed)
                wget -q https://nvidia.box.com/shared/static/1v2a6r9xnlc8f69aauv3ezzsgm0l0d3z.whl -O torch-1.8.0-cp36-cp36m-linux_aarch64.whl
                python3 -m pip install torch-1.8.0-cp36-cp36m-linux_aarch64.whl >> "$LOGFILE" 2>&1 || error_exit "Failed to install PyTorch."
                python3 -m pip install torchvision >> "$LOGFILE" 2>&1 || warn "Failed to install torchvision."
                ;;
            opencv)
                log "Installing OpenCV..."
                sudo apt install -y python3-opencv >> "$LOGFILE" 2>&1 || error_exit "Failed to install OpenCV."
                ;;
        esac
    done

    log "AI/ML libraries installed."
}