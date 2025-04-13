#!/bin/bash

install_ai_ml_libs() {
    local AI_ML_LIBS="$1"
    local ARCH="$2"

    log "Installing AI/ML libraries..."

    # Install pip
    log "Installing python3-pip..."
    sudo apt update 2>&1 | tee -a "$LOGFILE" || {
        log "Failed to update package lists."
        return 1
    }
    sudo apt install -y python3-pip 2>&1 | tee -a "$LOGFILE" || {
        log "Failed to install python3-pip."
        return 1
    }

    # Validate input
    if [ -z "$AI_ML_LIBS" ]; then
        log "No AI/ML libraries specified."
        return 1
    fi

    for lib in $AI_ML_LIBS; do
        case $lib in
            numpy)
                log "Installing NumPy..."
                python3 -m pip install numpy 2>&1 | tee -a "$LOGFILE" || {
                    log "Failed to install NumPy."
                    return 1
                }
                ;;
            tensorflow)
                if [ "$ARCH" = "aarch64" ]; then
                    log "Installing TensorFlow for Jetson..."
                    python3 -m pip install --extra-index-url https://developer.download.nvidia.com/compute/redist/jp/v46 tensorflow 2>&1 | tee -a "$LOGFILE" || {
                        log "Failed to install TensorFlow for Jetson."
                        return 1
                    }
                else
                    log "Installing generic TensorFlow..."
                    python3 -m pip install tensorflow 2>&1 | tee -a "$LOGFILE" || {
                        warn "Failed to install TensorFlow on $ARCH."
                    }
                fi
                ;;
            pytorch)
                if [ "$ARCH" = "aarch64" ]; then
                    log "Installing PyTorch for Jetson..."
                    wget -q https://nvidia.box.com/shared/static/1v2a6r9xnlc8f69aauv3ezzsgm0l0d3z.whl -O torch-1.8.0-cp36-cp36m-linux_aarch64.whl 2>&1 | tee -a "$LOGFILE" || {
                        log "Failed to download PyTorch wheel."
                        return 1
                    }
                    python3 -m pip install torch-1.8.0-cp36-cp36m-linux_aarch64.whl 2>&1 | tee -a "$LOGFILE" || {
                        log "Failed to install PyTorch."
                        return 1
                    }
                    python3 -m pip install torchvision 2>&1 | tee -a "$LOGFILE" || {
                        warn "Failed to install torchvision."
                    }
                    rm -f torch-1.8.0-cp36-cp36m-linux_aarch64.whl
                else
                    log "Installing generic PyTorch..."
                    python3 -m pip install torch 2>&1 | tee -a "$LOGFILE" || {
                        warn "Failed to install PyTorch on $ARCH."
                    }
                fi
                ;;
            opencv)
                log "Installing OpenCV..."
                sudo apt install -y python3-opencv 2>&1 | tee -a "$LOGFILE" || {
                    log "Failed to install OpenCV."
                    return 1
                }
                ;;
            *)
                warn "Unknown library: $lib"
                ;;
        esac
    done

    log "AI/ML libraries installation completed successfully."
    return 0
}