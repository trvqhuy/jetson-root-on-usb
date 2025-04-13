#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  whiptail --title "Permission Error" --msgbox "This script must be run as root. Please rerun with 'sudo $0'." 8 60
  exit 1
fi

# Title and checklist menu config
TITLE="Jetson Nano AI/ML Installer"
HEIGHT=20
WIDTH=70
CHOICE_HEIGHT=10

# Define menu options
OPTIONS=(
  1 "Install system dependencies" off
  2 "Install Python build tools" off
  3 "Install scientific libraries (numpy, scipy, pybind11)" off
  4 "Install ML & CV libraries (scikit-learn, scikit-image, etc.)" off
  5 "Install EasyOCR" off
  6 "Install web stack (FastAPI, uvicorn, etc.)" off
  7 "Check OpenCV CUDA support" off
)

# Flag to track cancellation
CANCELLED=0

# Cleanup function for cancellation
cleanup() {
  CANCELLED=1
  if [ -n "$CURRENT_PID" ]; then
    kill -9 "$CURRENT_PID" 2>/dev/null
  fi
  if [ -n "$log_file" ] && [ -f "$log_file" ]; then
    echo "Cleaning up log file: $log_file" >> /tmp/install_debug_$$.log
    rm -f "$log_file"
  fi
}

# Trap Ctrl+C
trap 'cleanup; echo "Installation cancelled by user via Ctrl+C."; exit 1' SIGINT

# Function to run commands with progress and live log updates
run_step() {
  local message=$1
  shift
  local commands=("$@") # Array of commands
  log_file="/tmp/install_log_$$.txt"
  debug_log="/tmp/install_debug_$$.log"
  CURRENT_PID=""

  # Initialize log file
  > "$log_file"
  echo "Starting step: $message" >> "$debug_log"

  # Calculate progress increment per command
  local num_commands=${#commands[@]}
  local progress_increment=$((100 / num_commands))
  local current_progress=0

  # Run commands with progress updates
  (
    echo "XXX"
    echo "0"
    echo "$message"
    echo "XXX"

    for cmd in "${commands[@]}"; do
      # Check for cancellation
      if [ $CANCELLED -eq 1 ]; then
        echo "XXX"
        echo "$current_progress"
        echo "$message - Cancelled!"
        echo "XXX"
        exit 1
      fi

      # Execute sub-command with unbuffered output
      echo "Running: $cmd" >> "$log_file"
      stdbuf -oL -eL eval "$cmd" >> "$log_file" 2>&1 &
      CURRENT_PID=$!
      local pid=$CURRENT_PID

      # Update progress and logs while command runs
      while kill -0 $pid 2>/dev/null && [ $CANCELLED -eq 0 ]; do
        if [ -s "$log_file" ]; then
          local log_snippet=$(tail -n 1 "$log_file")
          # Limit snippet length to avoid gauge overflow
          log_snippet=${log_snippet:0:50}
          echo "XXX"
          echo "$current_progress"
          echo "$message\n$log_snippet"
          echo "XXX"
        fi
        sleep 1 # Slower update to reduce whiptail issues
      done

      # Wait for command to finish
      wait $pid
      local exit_status=$?

      echo "Command '$cmd' exited with status $exit_status" >> "$debug_log"

      if [ $exit_status -ne 0 ]; then
        echo "XXX"
        echo "$current_progress"
        echo "$message - Failed!"
        echo "XXX"
        exit $exit_status
      fi

      # Update progress
      current_progress=$((current_progress + progress_increment))
      if [ $current_progress -gt 100 ]; then
        current_progress=100
      fi
      echo "XXX"
      echo "$current_progress"
      echo "$message"
      echo "XXX"
    done

    # Final progress
    echo "XXX"
    echo "100"
    echo "$message - Completed successfully!"
    echo "XXX"
  ) | whiptail --title "$TITLE" --gauge "$message" 8 60 0

  # Check dialog and command exit status
  local gauge_exit=${PIPESTATUS[0]}
  local cmd_exit=${PIPESTATUS[1]}

  echo "Gauge exit: $gauge_exit, Command exit: $cmd_exit" >> "$debug_log"

  # Check if user cancelled the dialog
  if [ $gauge_exit -ne 0 ]; then
    cleanup
    whiptail --title "$TITLE" --msgbox "Installation cancelled by user via dialog close." 8 50
    exit 1
  fi

  # Display last 5 lines of log
  if [ -s "$log_file" ]; then
    local log_tail=$(tail -n 5 "$log_file" | sed 's/[^a-zA-Z0-9.\/_-]/\\&/g')
    whiptail --title "$TITLE" --msgbox "Log output (last 5 lines):\n\n$log_tail" 15 70
  else
    whiptail --title "$TITLE" --msgbox "Log output (last 5 lines):\n\nNo output captured in logs." 15 70
  fi

  # Clean up log file
  echo "Removing log file: $log_file" >> "$debug_log"
  rm -f "$log_file"

  # Exit if command failed or cancelled
  if [ $cmd_exit -ne 0 ]; then
    whiptail --title "$TITLE" --msgbox "Error during: $message\nInstallation aborted." 8 50
    exit $cmd_exit
  fi
  if [ $CANCELLED -eq 1 ]; then
    whiptail --title "$TITLE" --msgbox "Installation cancelled by user." 8 50
    exit 1
  fi
}

# Show welcome message
whiptail --title "$TITLE" --msgbox "🚀 Welcome to the Jetson Nano AI/ML Installer!\n\nUse the arrow keys and spacebar to select what you want to install.\nThen press Enter to begin.\n\nPress Ctrl+C or close the progress dialog to cancel during installation." 15 60

# Show checklist menu and capture selections
CHOICES=$(whiptail --title "$TITLE" --checklist \
  "Select components to install:" $HEIGHT $WIDTH $CHOICE_HEIGHT \
  "${OPTIONS[@]}" 3>&1 1>&2 2>&3)

# Check if user cancelled
if [ $? -ne 0 ]; then
  whiptail --title "$TITLE" --msgbox "Installation cancelled." 8 50
  exit 0
fi

# Remove quotes from selections
CHOICES=$(echo "$CHOICES" | tr -d '"')

# Check if any options were selected
if [ -z "$CHOICES" ]; then
  whiptail --title "$TITLE" --msgbox "No options selected. Exiting." 8 50
  exit 0
fi

# Run selected options
for choice in $CHOICES; do
  [ $CANCELLED -eq 1 ] && break
  case $choice in
    1)
      run_step "Installing system dependencies" \
        "apt-get update" \
        "apt-get install -y python3-pip python3-virtualenv" \
        "apt-get install -y libjpeg-dev libopenblas-base libopenmpi-dev libomp-dev" \
        "apt-get install -y build-essential cmake gfortran libatlas-base-dev" \
        "apt-get install -y chromium-chromedriver firefox geckodriver" \
        "apt-get install -y libtiff5-dev libavcodec-dev libavformat-dev libswscale-dev" \
        "apt-get install -y libgtk2.0-dev libcanberra-gtk* libxvidcore-dev libx264-dev" \
        "apt-get install -y libgtk-3-dev libhdf5-serial-dev libqtgui4 libqtwebkit4 libqt4-test" \
        "apt-get install -y libdc1394-22-dev libsm6 libxext6 libxrender-dev python3-matplotlib"
      ;;
    2)
      run_step "Upgrading pip and installing build tools" \
        "python3 -m pip install --upgrade pip" \
        "python3 -m pip install setuptools wheel Cython"
      ;;
    3)
      run_step "Installing scientific libraries" \
        "python3 -m pip install numpy==1.19.5" \
        "python3 -m pip install scipy==1.5.4" \
        "python3 -m pip install pybind11==2.6.2"
      ;;
    4)
      run_step "Installing ML & CV libraries" \
        "python3 -m pip install scikit-learn==0.24.2" \
        "python3 -m pip install scikit-image==0.16.2" \
        "python3 -m pip install pillow==8.4.0" \
        "python3 -m pip install tqdm==4.62.3"
      ;;
    5)
      run_step "Installing EasyOCR" \
        "python3 -m pip install easyocr==1.4"
      ;;
    6)
      run_step "Installing web stack" \
        "python3 -m pip install fastapi==0.70.0" \
        "python3 -m pip install uvicorn[standard]==0.17.0" \
        "python3 -m pip install slowapi==0.1.5" \
        "python3 -m pip install requests==2.27.1" \
        "python3 -m pip install python-dotenv==0.20.0" \
        "python3 -m pip install selenium==3.141.0"
      ;;
    7)
      run_step "Verifying OpenCV CUDA support" \
        "python3 -c 'import cv2; print(\"CUDA available:\", cv2.cuda.getCudaEnabledDeviceCount() > 0)'"
      ;;
  esac
done

# Check if cancelled before showing completion
if [ $CANCELLED -eq 1 ]; then
  whiptail --title "$TITLE" --msgbox "Installation cancelled by user." 8 50
  exit 1
fi

# Completion message
whiptail --title "$TITLE" --msgbox "✅ Installation completed successfully!" 8 50