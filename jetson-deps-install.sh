#!/bin/bash

# Check if main.sh is executable
MAIN_SCRIPT="$(dirname "$0")/main.sh"
if [ ! -x "$MAIN_SCRIPT" ]; then
  echo "❌ Error: $MAIN_SCRIPT is not executable. Fixing permissions..." >&2
  chmod +x "$MAIN_SCRIPT" || { echo "❌ Failed to fix permissions for $MAIN_SCRIPT" >&2; exit 1; }
fi

# Execute main.sh
exec "$MAIN_SCRIPT" "$@"