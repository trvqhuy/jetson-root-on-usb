#!/bin/bash

run_tasks() {
  # Fix apt sources before tasks
  fix_apt_sources

  # Flag to track cancellation
  CANCELLED=0
  ERROR_DETECTED=0

  # Cleanup function for cancellation or error
  cleanup_runner() {
    CANCELLED=1
    if [ -n "$CURRENT_PID" ]; then
      kill -9 "$CURRENT_PID" 2>/dev/null
    fi
    if [ -n "$log_file" ] && [ -f "$log_file" ]; then
      echo "Cleaning up log file: $log_file" >> "$debug_log"
      rm -f "$log_file"
    fi
  }

  # Trap Ctrl+C
  trap 'cleanup_runner; gum style --foreground 1 "Installation cancelled by user via Ctrl+C."; exit 1' SIGINT

  # Execute selected tasks
  IFS=$'\n' # Split choices on newlines
  for choice in $CHOICES; do
    [ $CANCELLED -eq 1 ] && break
    gum style --foreground 34 "Processing: $choice"
    if [[ -n "${TASKS[$choice]}" ]]; then
      IFS='|' read -r title cmd <<< "${TASKS[$choice]}"
      run_step "$title" "$cmd"
    else
      gum style --foreground 1 "❌ Unknown choice: $choice"
      continue
    fi
  done

  if [ $CANCELLED -eq 1 ]; then
    gum style --foreground 1 "❌ Installation cancelled."
    exit 1
  fi
}

run_step() {
  local title=$1
  local cmd=$2
  local log_file="/tmp/install_log_$$.txt"
  local pid_file="/tmp/install_pid_$$.txt"
  ERROR_DETECTED=0

  gum style --foreground 99 "🔧 $title"

  # Initialize log file
  > "$log_file"
  echo "Starting: $title" >> "$debug_log"

  # Run command with logging, suppressing terminal output
  eval "$cmd" >"$log_file" 2>&1 &
  CURRENT_PID=$!
  echo "$CURRENT_PID" > "$pid_file"

  # Update spinner title with last 5 log lines
  while kill -0 "$CURRENT_PID" 2>/dev/null && [ $CANCELLED -eq 0 ] && [ $ERROR_DETECTED -eq 0 ]; do
    if [ -s "$log_file" ]; then
      local log_snippet=$(tail -n 5 "$log_file" | sed 's/[^[:print:]]//g' | head -c 40 | tr '\n' ';')
      if [ -n "$log_snippet" ]; then
        # Replace semicolons with newlines for display
        log_snippet=$(echo "$log_snippet" | tr ';' '\n')
        gum spin --spinner dot --title "$title:\n$log_snippet" -- sleep 0.3
        echo "Log update: $log_snippet" >> "$debug_log"
      else
        gum spin --spinner dot --title "$title: Waiting for output..." -- sleep 0.3
        echo "Log update: empty snippet" >> "$debug_log"
      fi
    else
      gum spin --spinner dot --title "$title: Waiting for output..." -- sleep 0.3
      echo "Log update: log file empty" >> "$debug_log"
    fi
    # Check for errors
    if ! check_log_for_errors "$log_file"; then
      ERROR_DETECTED=1
      kill -9 "$CURRENT_PID" 2>/dev/null
      break
    fi
  done

  # Wait for command to finish
  wait "$CURRENT_PID" 2>/dev/null
  local exit_status=$?

  # Clean up pid file
  rm -f "$pid_file"

  echo "Command '$cmd' exited with status $exit_status" >> "$debug_log"

  if [ $exit_status -ne 0 ] || [ $ERROR_DETECTED -eq 1 ]; then
    error_msg=$(printf "❌ Error during: %s\nExit status: %d\nLog output (last 5 lines):\n" "$title" "$exit_status")
    if [ -s "$log_file" ]; then
      local log_tail=$(tail -n 5 "$log_file" | sed 's/[^[:print:]]//g')
      error_msg=$(printf "%s%s" "$error_msg" "$log_tail")
    else
      error_msg=$(printf "%sNo output captured in logs." "$error_msg")
    fi
    gum style --border normal --padding "1 2" --foreground 1 "$error_msg"
    exit 1
  fi

  gum style --foreground 10 "✅ $title completed."
}