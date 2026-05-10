#!/usr/bin/env bash
# claude-statusline installer
# Usage: curl -fsSL https://raw.githubusercontent.com/gencrewai/aiops/main/install.sh | bash
#        curl -fsSL ... | bash -s -- lite    → 1-line mode
set -euo pipefail

MODE="${1:-full}"
REPO="gencrewai/aiops"
SCRIPT_NAME="claude-statusline.sh"
INSTALL_DIR="$HOME/.claude"
INSTALL_PATH="$INSTALL_DIR/$SCRIPT_NAME"
SETTINGS_FILE="$INSTALL_DIR/settings.json"

echo "Installing claude-statusline (${MODE} mode)..."

# create ~/.claude if needed
mkdir -p "$INSTALL_DIR"

# download script
curl -fsSL "https://raw.githubusercontent.com/$REPO/main/$SCRIPT_NAME" -o "$INSTALL_PATH"
chmod +x "$INSTALL_PATH"
echo "  Downloaded $INSTALL_PATH"

# build command string based on mode
if [ "$MODE" = "lite" ]; then
  CMD_STR="bash \\\"${INSTALL_PATH}\\\" lite"
else
  CMD_STR="bash \\\"${INSTALL_PATH}\\\""
fi

# configure settings.json
if [ -f "$SETTINGS_FILE" ]; then
  if grep -q '"statusLine"' "$SETTINGS_FILE" 2>/dev/null; then
    echo "  statusLine already configured in settings.json (skipped)"
    echo "  To update manually, set:"
    echo "    \"statusLine\": { \"type\": \"command\", \"command\": \"$CMD_STR\" }"
  else
    tmp=$(mktemp)
    sed '$ d' "$SETTINGS_FILE" > "$tmp"
    if grep -q '[^[:space:]]' "$tmp"; then
      last_char=$(grep '[^[:space:]]' "$tmp" | tail -1 | sed 's/.*\(.\)$/\1/')
      if [ "$last_char" != "," ] && [ "$last_char" != "{" ]; then
        sed -i '$ s/$/,/' "$tmp"
      fi
    fi
    printf '  "statusLine": { "type": "command", "command": "%s"}\n}\n' "$CMD_STR" >> "$tmp"
    mv "$tmp" "$SETTINGS_FILE"
    echo "  Configured statusLine in settings.json"
  fi
else
  printf '{\n  "statusLine": { "type": "command", "command": "%s"}\n}\n' "$CMD_STR" > "$SETTINGS_FILE"
  echo "  Created settings.json with statusLine"
fi

echo ""
echo "Done! Restart Claude Code to see the status bar."
echo ""
echo "Modes:"
echo "  full (default) — 3-line: model, context, cost, git, limits, cache"
echo "  lite           — 1-line: folder │ branch │ model │ 5h │ 7d"
echo ""
echo "Switch mode: re-run installer with 'lite' or 'full' argument"
echo "To uninstall: curl -fsSL https://raw.githubusercontent.com/$REPO/main/uninstall.sh | bash"
