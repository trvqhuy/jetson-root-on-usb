#!/bin/bash

install_gum() {
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

    # Function to install gum binary
    install_gum_binary() {
      local version=$1
      local binary_file="gum_${version#v}_Linux_arm64.tar.gz"
      local binary_url="https://github.com/charmbracelet/gum/releases/download/${version}/${binary_file}"
      echo "⬇️ Downloading $binary_file..." >&2
      wget -q --tries=3 --timeout=10 "$binary_url" -O "$binary_file"

      if [ -f "$binary_file" ]; then
        # Verify file integrity
        if file "$binary_file" | grep -q "gzip compressed data"; then
          echo "📦 Extracting gum binary..." >&2
          if tar -xzf "$binary_file" 2>>"$debug_log"; then
            if [ -f "gum" ]; then
              sudo mv gum /usr/local/bin/
              sudo chmod +x /usr/local/bin/gum
              echo "✅ gum binary installed successfully." >&2
              return 0
            else
              echo "❌ No gum binary found in archive. Contents:" >&2
              ls -l >&2
              return 1
            fi
          else
            echo "❌ Failed to extract $binary_file. Tar error logged in $debug_log." >&2
            return 1
          fi
        else
          echo "❌ $binary_file is not a valid gzip archive." >&2
          return 1
        fi
      else
        echo "❌ Failed to download $binary_file." >&2
        return 1
      fi
    }

    # Try latest version
    echo "🌐 Fetching latest gum version..." >&2
    LATEST_VERSION=$(curl -s --connect-timeout 10 https://api.github.com/repos/charmbracelet/gum/releases/latest | grep '"tag_name":' | sed -E 's/.*"tag_name":\s*"([^"]+)".*/\1/' || echo "v0.13.0")
    if [[ "$LATEST_VERSION" == "v"* ]]; then
      echo "📦 Found gum version: $LATEST_VERSION" >&2
    else
      echo "⚠️ Could not fetch latest version, falling back to v0.13.0" >&2
      LATEST_VERSION="v0.13.0"
    fi

    # Attempt to install latest version
    if install_gum_binary "$LATEST_VERSION"; then
      : # Success, continue
    else
      echo "⚠️ Failed to install $LATEST_VERSION, falling back to v0.13.0..." >&2
      if ! install_gum_binary "v0.13.0"; then
        echo "❌ Failed to install gum v0.13.0. Please install manually from https://github.com/charmbracelet/gum." >&2
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
}