#!/usr/bin/env bash
# claude-statusline installer
# Usage: curl -fsSL https://raw.githubusercontent.com/gencrewai/aiops/main/install.sh | bash
set -euo pipefail

REPO="gencrewai/aiops"
SCRIPT_NAME="statusline.sh"
INSTALL_DIR="$HOME/.claude"
INSTALL_PATH="$INSTALL_DIR/$SCRIPT_NAME"
SETTINGS_FILE="$INSTALL_DIR/settings.json"

echo "Installing claude-statusline..."

# create ~/.claude if needed
mkdir -p "$INSTALL_DIR"

# download script
curl -fsSL "https://raw.githubusercontent.com/$REPO/main/$SCRIPT_NAME" -o "$INSTALL_PATH"
chmod +x "$INSTALL_PATH"
echo "  Downloaded $INSTALL_PATH"

# configure settings.json
if [ -f "$SETTINGS_FILE" ]; then
  # check if statusLine already configured
  if grep -q '"statusLine"' "$SETTINGS_FILE" 2>/dev/null; then
    echo "  statusLine already configured in settings.json (skipped)"
    echo "  To update manually, set:"
    echo "    \"statusLine\": { \"type\": \"command\", \"command\": \"bash \\\"$INSTALL_PATH\\\"\" }"
  else
    # add statusLine before the last closing brace
    tmp=$(mktemp)
    sed '$ d' "$SETTINGS_FILE" > "$tmp"
    # add comma if needed
    if grep -q '[^[:space:]]' "$tmp"; then
      # check if last non-empty line ends with comma or brace
      last_char=$(grep '[^[:space:]]' "$tmp" | tail -1 | sed 's/.*\(.\)$/\1/')
      if [ "$last_char" != "," ] && [ "$last_char" != "{" ]; then
        sed -i '$ s/$/,/' "$tmp"
      fi
    fi
    printf '  "statusLine": { "type": "command", "command": "bash \\"%s\\\""}\n}\n' "$INSTALL_PATH" >> "$tmp"
    mv "$tmp" "$SETTINGS_FILE"
    echo "  Configured statusLine in settings.json"
  fi
else
  # create new settings.json
  printf '{\n  "statusLine": { "type": "command", "command": "bash \\"%s\\\""}\n}\n' "$INSTALL_PATH" > "$SETTINGS_FILE"
  echo "  Created settings.json with statusLine"
fi

echo ""
echo "Done! Restart Claude Code to see the status bar."
echo "To uninstall: curl -fsSL https://raw.githubusercontent.com/$REPO/main/uninstall.sh | bash"
