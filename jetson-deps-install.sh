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
ERROR_DETECTED=0

# Cleanup function for cancellation or error
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
trap 'cleanup; echo "Installation cancelled by user via Ctrl+C."; whiptail --title "$TITLE" --msgbox "Installation cancelled by user via Ctrl+C." 8 50; exit 1' SIGINT

# Function to check logs for errors
check_log_for_errors() {
  local log_file=$1
  if [ -s "$log_file" ]; then
    # Look for common error patterns (case-insensitive)
    if grep -iE "error|failed|no such file|unable to|cannot" "$log_file" >/dev/null; then
      return 1 # Error found
    fi
  fi
  return 0 # No error
}

# Function to run commands with progress, live logs, and error detection
run_step() {
  local message=$1
  shift
  local commands=("$@") # Array of commands
  log_file="/tmp/install_log_$$.txt"
  debug_log="/tmp/install_debug_$$.log"
  CURRENT_PID=""
  ERROR_DETECTED=0

  # Initialize log file
  > "$log_file"
  echo "Starting step: $message" >> "$debug_log"

  # Calculate progress increment per command
  local num_commands=${#commands[@]}
  local progress_increment=$((100 / num_commands))
  local current_progress=0

  # Single gauge for all sub-commands
  (
    for cmd in "${commands[@]}"; do
      # Check for cancellation or prior error
      if [ $CANCELLED -eq 1 ] || [ $ERROR_DETECTED -eq 1 ]; then
        echo "XXX"
        echo "$current_progress"
        if [ $CANCELLED -eq 1 ]; then
          echo "$message - Cancelled!"
        else
          echo "$message - Error detected!"
        fi
        echo "XXX"
        exit 1
      fi

      # Initialize progress for this sub-task
      echo "XXX"
      echo "$current_progress"
      echo "$message"
      echo "XXX"
      echo "Progress update: $current_progress for '$cmd'" >> "$debug_log"

      # Execute sub-command with real-time logging
      echo "Running: $cmd" >> "$log_file"
      eval "$cmd" 2>&1 | tee -a "$log_file" &
      CURRENT_PID=$!
      local pid=$CURRENT_PID

      # Update logs and check for errors while command runs
      while kill -0 $pid 2>/dev/null && [ $CANCELLED -eq 0 ] && [ $ERROR_DETECTED -eq 0 ]; do
        if [ -s "$log_file" ]; then
          local log_snippet=$(tail -n 1 "$log_file")
          # Sanitize: remove non-printable, limit to 40 chars
          log_snippet=$(echo "$log_snippet" | sed 's/[^[:print:]]//g' | head -c 40)
          if [ -n "$log_snippet" ]; then
            echo "XXX"
            echo "$current_progress"
            echo "$message\nLog: $log_snippet"
            echo "XXX"
            echo "Log update: $log_snippet" >> "$debug_log"
          fi
          # Check logs for errors
          if ! check_log_for_errors "$log_file"; then
            ERROR_DETECTED=1
            echo "XXX"
            echo "$current_progress"
            echo "$message - Error detected in logs!"
            echo "XXX"
            kill -9 $pid 2>/dev/null
            exit 1
          fi
        fi
        sleep 1
      done

      # Wait for command to finish
      wait $pid
      local exit_status=$?

      echo "Command '$cmd' exited with status $exit_status, progress: $current_progress" >> "$debug_log"

      if [ $exit_status -ne 0 ] || [ $ERROR_DETECTED -eq 1 ]; then
        echo "XXX"
        echo "$current_progress"
        echo "$message - Failed: $cmd"
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
      echo "Progress incremented to: $current_progress" >> "$debug_log"
    done

    # Final progress
    echo "XXX"
    echo "100"
    echo "$message - Completed successfully!"
    echo "XXX"
  ) | whiptail --title "$TITLE" --gauge "$message" 8 60 0

  # Check exit statuses
  local gauge_exit=${PIPESTATUS[0]}
  local cmd_exit=${PIPESTATUS[1]}

  echo "Gauge exit: $gauge_exit, Command exit: $cmd_exit" >> "$debug_log"

  # Handle cancellation
  if [ $CANCELLED -eq 1 ]; then
    whiptail --title "$TITLE" --msgbox "Installation cancelled by user." 8 50
    exit 1
  fi

  # Handle command, gauge, or log error
  if [ $cmd_exit -ne 0 ] || [ $gauge_exit -ne 0 ] || [ $ERROR_DETECTED -eq 1 ]; then
    local error_msg="Error during: $message\nFailed command: ${cmd:-unknown}\nExit status: $cmd_exit"
    if [ $cmd_exit -ne 0 ] || [ $ERROR_DETECTED -eq 1 ]; then
      error_msg="$error_msg\nTry running 'apt-get update' or 'apt-get --fix-broken install' to resolve."
    fi
    if [ -s "$log_file" ]; then
      local log_tail=$(tail -n 5 "$log_file" | sed 's/[^a-zA-Z0-9.\/_-]/\\&/g')
      error_msg="$error_msg\nLog output (last 5 lines):\n\n$log_tail"
    else
      error_msg="$error_msg\nNo output captured in logs."
    fi
    whiptail --title "$TITLE" --msgbox "$error_msg" 18 70
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
}

# Show welcome message
whiptail --title "$TITLE" --msgbox "🚀 Welcome to the Jetson Nano AI/ML Installer!\n\nUse the arrow keys and spacebar to select what you want to install.\nThen press Enter to begin.\n\nPress Ctrl+C to cancel during installation." 15 60

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
        "apt-get install -y chromium-chromedriver" \
        "apt-get install -y firefox" \
        "apt-get install -y geckodriver" \
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
        "python3 -m pip install scikit-image==0.17.2" \
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