#!/bin/bash

show_welcome() {
  clear
  gum style --border double --margin "1 2" --padding "1 2" --foreground 212 --align center \
    "🚀 Jetson Nano AI/ML Installer" \
    "Use ↑ ↓ to navigate, Space to select, Enter to confirm"
}

get_user_choices() {
  CHOICES=$(gum choose --no-limit \
    "Install system dependencies" \
    "Install Python build tools" \
    "Install scientific libraries" \
    "Install ML & CV libraries" \
    "Install EasyOCR" \
    "Install web stack" \
    "Check OpenCV CUDA support")

  if [ -z "$CHOICES" ]; then
    gum style --foreground 1 "❌ No options selected. Exiting."
    exit 1
  fi

  echo "Selected choices: $CHOICES" >> "$debug_log"
  export CHOICES
}