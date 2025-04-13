#!/bin/bash

install_ai_ml_libs() {
    local AI_ML_LIBS="$1"
    local ARCH="$2"

    log "Installing AI/ML libraries..."

    # Install pip
    log "Installing python3-pip..."
    sudo apt install -y python3-pip >> "$LOGFILE" 2>&1 || error_exit "Failed to install pip."

    # Validate input
    if [ -z "$AI_ML_LIBS" ]; then
        error_exit "No AI/ML libraries specified."
    fi

    for lib in $AI_ML_LIBS; do
        case $lib in
            numpy)
                log "Installing NumPy..."
                python3 -m pip install numpy >> "$LOGFILE" 2>&1 || error_exit "Failed to install NumPy."
                ;;
            tensorflow)
                if [ "$ARCH" = "aarch64" ]; then
                    log "Installing TensorFlow (Jetson)..."
                    python3 -m pip install --extra-index-url https://developer.download.nvidia.com/compute/redist/jp/v46 tensorflow >> "$LOGFILE" 2>&1 || error_exit "Failed to install TensorFlow."
                else
                    log "Installing TensorFlow (generic)..."
                    python3 -m pip install tensorflow >> "$LOGFILE" 2>&1 || warn "Failed to install TensorFlow on $ARCH."
                fi
                ;;
            pytorch)
                if [ "$ARCH" = "aarch64" ]; then
                    log "Installing PyTorch (Jetson)..."
                    wget -q https://nvidia.box.com/shared/static/1v2a6r9xnlc8f69aauv3ezzsgm0l0d3z.whl -O torch-1.8.0-cp36-cp36m-linux_aarch64.whl
                    python3 -m pip install torch-1.8.0-cp36-cp36m-linux_aarch64.whl >> "$LOGFILE" 2>&1 || error_exit "Failed to install PyTorch."
                    python3 -m pip install torchvision >> "$LOGFILE" 2>&1 || warn "Failed to install torchvision."
                else
                    log "Installing PyTorch (generic)..."
                    python3 -m pip install torch >> "$LOGFILE" 2>&1 || warn "Failed to install PyTorch on $ARCH."
                fi
                ;;
            opencv)
                log "Installing OpenCV..."
                sudo apt install -y python3-opencv >> "$LOGFILE" 2>&1 || error_exit "Failed to install OpenCV."
                ;;
            *)
                warn "Unknown library: $lib"
                ;;
        esac
    done

    log "AI/ML libraries installed."
}