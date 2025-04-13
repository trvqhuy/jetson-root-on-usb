#!/bin/bash

# --- Auto-install gum if not present ---
if ! command -v gum &> /dev/null; then
  echo "🔍 gum not found. Installing gum..."
  echo "deb [trusted=yes] https://apt.fury.io/charm/ /" | sudo tee /etc/apt/sources.list.d/charm.list > /dev/null
  sudo apt update -y
  sudo apt install -y gum
  if ! command -v gum &> /dev/null; then
    echo "❌ gum installation failed. Please install manually."
    exit 1
  fi
fi

clear
gum style --border double --margin "1 2" --padding "1 2" --foreground 212 --align center \
"🚀 Jetson Nano AI/ML Installer" \
"Use ↑ ↓ to navigate and Enter to select"

#!/bin/bash

clear
gum style --border double --margin "1 2" --padding "1 2" --foreground 212 --align center \
"🚀 Jetson Nano AI/ML Installer" \
"Use ↑ ↓ to navigate and Enter to select"

# Define choices
CHOICES=$(gum choose --no-limit \
  "Install system dependencies" \
  "Install Python build tools" \
  "Install scientific libraries" \
  "Install ML & CV libraries" \
  "Install EasyOCR" \
  "Install web stack" \
  "Check OpenCV CUDA support"
)

# Check if user cancelled
if [ -z "$CHOICES" ]; then
  gum style --foreground 1 "❌ No options selected. Exiting."
  exit 1
fi

# Function runner
run_step() {
  gum style --foreground 99 "🔧 $1"
  eval "$2" | gum spin --spinner dot --title "$1" --show-output
}

# Execute selected tasks
for item in $CHOICES; do
  case "$item" in
    "Install system dependencies")
      run_step "Installing apt packages" "
        sudo apt-get update && sudo apt-get install -y \
        python3-pip python3-virtualenv \
        libjpeg-dev libopenblas-base libopenmpi-dev libomp-dev \
        build-essential cmake gfortran libatlas-base-dev \
        chromium-chromedriver firefox geckodriver \
        libtiff5-dev libavcodec-dev libavformat-dev libswscale-dev \
        libgtk2.0-dev libcanberra-gtk* libxvidcore-dev libx264-dev \
        libgtk-3-dev libhdf5-serial-dev libqtgui4 libqtwebkit4 libqt4-test \
        libdc1394-22-dev libsm6 libxext6 libxrender-dev python3-matplotlib"
      ;;
    "Install Python build tools")
      run_step "Upgrading pip + tools" "
        python3 -m pip install --upgrade pip setuptools wheel Cython"
      ;;
    "Install scientific libraries")
      run_step "Installing NumPy, SciPy, PyBind11" "
        python3 -m pip install numpy==1.19.5 scipy==1.5.4 pybind11==2.6.2"
      ;;
    "Install ML & CV libraries")
      run_step "Installing sklearn, scikit-image, tqdm, pillow" "
        python3 -m pip install scikit-learn==0.24.2 scikit-image==0.17.2 tqdm==4.62.3 pillow==8.4.0"
      ;;
    "Install EasyOCR")
      run_step "Installing EasyOCR" "
        python3 -m pip install easyocr==1.4"
      ;;
    "Install web stack")
      run_step "Installing FastAPI, Uvicorn, etc." "
        python3 -m pip install fastapi==0.70.0 uvicorn[standard]==0.17.0 slowapi==0.1.5 \
        requests==2.27.1 python-dotenv==0.20.0 selenium==3.141.0"
      ;;
    "Check OpenCV CUDA support")
      run_step "Checking OpenCV CUDA" "
        python3 -c 'import cv2; print(\"🚀 CUDA available:\", cv2.cuda.getCudaEnabledDeviceCount() > 0)'"
      ;;
  esac
done

gum style --border normal --foreground 10 --align center --padding "1 2" \
"✅ All selected tasks completed!"
