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

# Setup debug logging
setup_logging() {
  debug_log="/tmp/install_debug_$$.log"
  echo "Debug log: $debug_log" >> "$debug_log"
  export debug_log
}

# Check if running as root
check_root() {
  if [ "$EUID" -ne 0 ]; then
    gum style --foreground 1 "❌ This script must be run as root. Please use sudo."
    exit 1
  fi
}

# Function to check logs for errors
check_log_for_errors() {
  local log_file=$1
  if [ -s "$log_file" ]; then
    if grep -iE "E: Unable to locate package|failed|error:|no such file|cannot" "$log_file" >/dev/null; then
      return 1 # Error found
    fi
  fi
  return 0 # No error
}

# Function to fix apt sources
fix_apt_sources() {
  if grep -q "apt.fury.io/charm" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
    echo "🛠️ Removing invalid apt.fury.io/charm source..." >&2
    sudo find /etc/apt/sources.list.d/ -type f -name "*.list" -exec grep -l "apt.fury.io/charm" {} \; -delete 2>/dev/null
    sudo sed -i '/apt.fury.io\/charm/d' /etc/apt/sources.list 2>/dev/null
  fi
}