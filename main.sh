#!/bin/bash

# Ensure script runs from its directory
cd "$(dirname "$0")" || exit 1

# Check and fix permissions for module files
for module in modules/*.sh; do
  if [ -f "$module" ] && [ ! -x "$module" ]; then
    echo "🛠️ Fixing permissions for $module..." >&2
    chmod +x "$module" || { echo "❌ Failed to fix permissions for $module" >&2; exit 1; }
  fi
done

# Source modules
source modules/utils.sh
source modules/install_gum.sh
source modules/ui.sh
source modules/tasks.sh
source modules/runner.sh

# Check if running as root
check_root

# Initialize debug log
setup_logging

# Install gum if not present
install_gum

# Show welcome message and get user choices
show_welcome
get_user_choices

# Run selected tasks
run_tasks

# Display completion message
gum style --border normal --foreground 10 --align center --padding "1 2" \
  "✅ All selected tasks completed!"