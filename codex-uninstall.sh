#!/usr/bin/env bash
# codex-statusline uninstaller
# Usage: curl -fsSL https://raw.githubusercontent.com/gencrewai/aiops/main/codex-uninstall.sh | bash
set -euo pipefail

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CONFIG_FILE="$CODEX_HOME/config.toml"

echo "Uninstalling codex-statusline..."

if [ -f "$CONFIG_FILE" ]; then
  if grep -q 'status_line' "$CONFIG_FILE" 2>/dev/null; then
    sed -i.bak '/^status_line\s*=/d' "$CONFIG_FILE"
    sed -i.bak '/^status_line_use_colors\s*=/d' "$CONFIG_FILE"
    rm -f "${CONFIG_FILE}.bak"
    echo "  Removed status_line from config.toml"
    echo "  Note: [tui] section header left intact (safe to remove manually if empty)"
  else
    echo "  No status_line config found (nothing to remove)"
  fi
else
  echo "  No config.toml found at $CONFIG_FILE"
fi

echo ""
echo "Done! Restart Codex CLI to apply changes."
