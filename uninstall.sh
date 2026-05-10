#!/usr/bin/env bash
# claude-statusline uninstaller
set -euo pipefail

INSTALL_PATH="$HOME/.claude/statusline.sh"
SETTINGS_FILE="$HOME/.claude/settings.json"

echo "Uninstalling claude-statusline..."

# remove script
if [ -f "$INSTALL_PATH" ]; then
  rm "$INSTALL_PATH"
  echo "  Removed $INSTALL_PATH"
else
  echo "  Script not found (already removed?)"
fi

# remove statusLine from settings.json
if [ -f "$SETTINGS_FILE" ] && grep -q '"statusLine"' "$SETTINGS_FILE" 2>/dev/null; then
  tmp=$(mktemp)
  grep -v '"statusLine"' "$SETTINGS_FILE" | sed 's/,\([[:space:]]*}\)/\1/' > "$tmp"
  mv "$tmp" "$SETTINGS_FILE"
  echo "  Removed statusLine from settings.json"
fi

echo ""
echo "Done! Restart Claude Code to apply."
