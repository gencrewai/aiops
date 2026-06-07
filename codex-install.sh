#!/usr/bin/env bash
# codex-statusline installer
# Usage: curl -fsSL https://raw.githubusercontent.com/gencrewai/aiops/main/codex-install.sh | bash
set -euo pipefail

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CONFIG_FILE="$CODEX_HOME/config.toml"

echo "Installing codex-statusline..."

# create ~/.codex if needed
mkdir -p "$CODEX_HOME"

# status line items to configure
STATUS_LINE='["current-dir", "git-branch", "model-with-reasoning", "context-used", "total-input-tokens", "total-output-tokens", "five-hour-limit", "weekly-limit"]'

if [ -f "$CONFIG_FILE" ]; then
  if grep -q 'status_line' "$CONFIG_FILE" 2>/dev/null; then
    # replace existing status_line
    if grep -q '^\[tui\]' "$CONFIG_FILE" 2>/dev/null; then
      # [tui] section exists — replace status_line value
      sed -i.bak -E "s|^status_line[[:space:]]*=.*|status_line = $STATUS_LINE|" "$CONFIG_FILE"
      # ensure colors enabled
      if ! grep -q 'status_line_use_colors' "$CONFIG_FILE"; then
        sed -i.bak "/^status_line[[:space:]]*=/a\\
status_line_use_colors = true" "$CONFIG_FILE"
      fi
      rm -f "${CONFIG_FILE}.bak"
      echo "  Updated status_line in config.toml"
    else
      echo "  status_line found but no [tui] section — skipped (update manually)"
      echo "  Add under [tui]: status_line = $STATUS_LINE"
    fi
  else
    # no status_line yet — add [tui] section if missing
    if grep -q '^\[tui\]' "$CONFIG_FILE" 2>/dev/null; then
      # append under existing [tui]
      sed -i.bak "/^\[tui\]/a\\
status_line = $STATUS_LINE\\
status_line_use_colors = true" "$CONFIG_FILE"
      rm -f "${CONFIG_FILE}.bak"
    else
      # add new [tui] section at end
      printf '\n[tui]\nstatus_line = %s\nstatus_line_use_colors = true\n' "$STATUS_LINE" >> "$CONFIG_FILE"
    fi
    echo "  Configured status_line in config.toml"
  fi
else
  # create new config.toml
  printf '[tui]\nstatus_line = %s\nstatus_line_use_colors = true\n' "$STATUS_LINE" > "$CONFIG_FILE"
  echo "  Created config.toml with status_line"
fi

echo ""
echo "Done! Restart Codex CLI to see the status bar."
echo ""
echo "Status line items:"
echo "  current-dir           — Working directory"
echo "  git-branch            — Current git branch"
echo "  model-with-reasoning  — Model name + reasoning effort (e.g. gpt-5.5 (xhigh))"
echo "  context-used          — Context window usage %"
echo "  total-input-tokens    — Input tokens"
echo "  total-output-tokens   — Output tokens"
echo "  five-hour-limit       — 5-hour rate limit"
echo "  weekly-limit          — Weekly rate limit"
echo ""
echo "Customize: codex /statusline (interactive) or edit ~/.codex/config.toml"
echo "To uninstall: curl -fsSL https://raw.githubusercontent.com/gencrewai/aiops/main/codex-uninstall.sh | bash"
