#!/bin/bash

# Function to clean up temporary directory
cleanup_tmp() {
  local tmp_dir=$1
  if [ -d "$tmp_dir" ]; then
    cd - >/dev/null 2>&1
    rm -rf "$tmp_dir"
    echo "🧹 Cleaned up temporary directory: $tmp_dir" >&2
  fi
}

# Auto-install gum if not present
if ! command -v gum &>/dev/null; then
  echo "🔍 gum not found. Attempting to install gum automatically..."

  # Detect architecture
  ARCH=$(uname -m)
  if [[ "$ARCH" != "aarch64" ]]; then
    echo "❌ Unsupported architecture: $ARCH. Expected aarch64 for Jetson Nano." >&2
    exit 1
  fi

  # Create temporary directory
  TMP_DIR=$(mktemp -d) || { echo "❌ Failed to create temporary directory" >&2; exit 1; }
  trap 'cleanup_tmp "$TMP_DIR"' EXIT

  cd "$TMP_DIR" || { echo "❌ Failed to change to temporary directory" >&2; exit 1; }

  # Get latest gum version from GitHub API
  echo "🌐 Fetching latest gum version..." >&2
  LATEST_VERSION=$(curl -s --connect-timeout 10 https://api.github.com/repos/charmbracelet/gum/releases/latest | grep '"tag_name":' | sed -E 's/.*"tag_name":\s*"([^"]+)".*/\1/' || echo "v0.13.0")
  if [[ "$LATEST_VERSION" == "v"* ]]; then
    echo "📦 Found gum version: $LATEST_VERSION" >&2
  else
    echo "⚠️ Could not fetch latest version, falling back to v0.13.0" >&2
    LATEST_VERSION="v0.13.0"
  fi

  # Try downloading .deb file first
  DEB_FILE="gum_${LATEST_VERSION#v}_linux_arm64.deb"
  DEB_URL="https://github.com/charmbracelet/gum/releases/download/${LATEST_VERSION}/${DEB_FILE}"
  echo "⬇️ Attempting to download $DEB_FILE..." >&2
  wget -q --tries=3 --timeout=10 "$DEB_URL" -O "$DEB_FILE"

  if [ -f "$DEB_FILE" ] && file "$DEB_FILE" | grep -q "Debian binary package"; then
    echo "🔧 Installing dependencies..." >&2
    sudo apt-get update || { echo "⚠️ apt-get update had issues, continuing..." >&2; }
    sudo apt-get install -y -f || { echo "⚠️ Failed to fix dependencies, attempting install anyway..." >&2; }

    echo "📦 Installing gum via .deb..." >&2
    if sudo dpkg -i "$DEB_FILE"; then
      echo "✅ gum installed successfully via .deb." >&2
    else
      echo "⚠️ dpkg failed, attempting to fix dependencies..." >&2
      sudo apt-get install -y -f
      if sudo dpkg -i "$DEB_FILE"; then
        echo "✅ gum installed after fixing dependencies." >&2
      else
        echo "❌ Failed to install gum .deb." >&2
        BINARY_INSTALL=1
      fi
    fi
  else
    echo "⚠️ .deb file not found or invalid, switching to binary installation..." >&2
    BINARY_INSTALL=1
  fi

  # Fallback to binary installation if .deb fails or is unavailable
  if [ "$BINARY_INSTALL" == "1" ]; then
    BINARY_FILE="gum_${LATEST_VERSION#v}_Linux_arm64.tar.gz"
    BINARY_URL="https://github.com/charmbracelet/gum/releases/download/${LATEST_VERSION}/${BINARY_FILE}"
    echo "⬇️ Downloading $BINARY_FILE..." >&2
    wget -q --tries=3 --timeout=10 "$BINARY_URL" -O "$BINARY_FILE"

    if [ -f "$BINARY_FILE" ] && file "$BINARY_FILE" | grep -q "gzip compressed data"; then
      echo "📦 Extracting gum binary..." >&2
      tar -xzf "$BINARY_FILE"
      if [ -f "gum" ]; then
        sudo mv gum /usr/local/bin/
        sudo chmod +x /usr/local/bin/gum
        echo "✅ gum binary installed successfully." >&2
      else
        echo "❌ Failed to extract gum binary." >&2
        cleanup_tmp "$TMP_DIR"
        exit 1
      fi
    else
      echo "❌ Failed to download or verify gum binary. Please install gum manually from https://github.com/charmbracelet/gum." >&2
      cleanup_tmp "$TMP_DIR"
      exit 1
    fi
  fi

  # Final check
  if ! command -v gum &>/dev/null; then
    echo "❌ gum installation failed. Please install manually from https://github.com/charmbracelet/gum." >&2
    cleanup_tmp "$TMP_DIR"
    exit 1
  fi

  echo "✅ gum is now installed and ready to use." >&2
else
  echo "✅ gum is already installed." >&2
fi

# Verify gum version
gum_version=$(gum --version 2>/dev/null || echo "unknown")
echo "ℹ️ gum version: $gum_version" >&2

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
