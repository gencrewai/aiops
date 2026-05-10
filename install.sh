#!/usr/bin/env bash
# claude-statusline installer
# Usage: curl -fsSL https://raw.githubusercontent.com/gencrewai/aiops/main/install.sh | bash
#        curl -fsSL ... | bash -s -- lite    → 1-line mode
set -euo pipefail

MODE="${1:-full}"
REPO="gencrewai/aiops"
SCRIPT_NAME="claude-statusline.sh"
INSTALL_DIR="${CLAUDE_HOME:-$HOME/.claude}"
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
  CMD_STR="\"${INSTALL_PATH}\" lite"
else
  CMD_STR="\"${INSTALL_PATH}\""
fi

write_settings_json() {
  if command -v node >/dev/null 2>&1; then
    node - "$SETTINGS_FILE" "$CMD_STR" <<'NODE'
const fs = require('fs');

const [settingsFile, command] = process.argv.slice(2);
let settings = {};

if (fs.existsSync(settingsFile)) {
  const raw = fs.readFileSync(settingsFile, 'utf8').trim();
  if (raw) {
    try {
      settings = JSON.parse(raw);
    } catch (error) {
      console.error(`  Failed to parse ${settingsFile}: ${error.message}`);
      process.exit(1);
    }
  }
}

if (!settings || Array.isArray(settings) || typeof settings !== 'object') {
  console.error(`  ${settingsFile} must contain a JSON object`);
  process.exit(1);
}

const existing = settings.statusLine && typeof settings.statusLine === 'object' && !Array.isArray(settings.statusLine)
  ? settings.statusLine
  : {};

settings.statusLine = {
  ...existing,
  type: 'command',
  command
};

fs.writeFileSync(settingsFile, `${JSON.stringify(settings, null, 2)}\n`);
NODE
    return
  fi

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$SETTINGS_FILE" "$CMD_STR" <<'PY'
import json
import os
import sys

settings_file, command = sys.argv[1], sys.argv[2]
settings = {}

if os.path.exists(settings_file):
    raw = open(settings_file, 'r', encoding='utf-8').read().strip()
    if raw:
        try:
            settings = json.loads(raw)
        except json.JSONDecodeError as error:
            print(f"  Failed to parse {settings_file}: {error}", file=sys.stderr)
            sys.exit(1)

if not isinstance(settings, dict):
    print(f"  {settings_file} must contain a JSON object", file=sys.stderr)
    sys.exit(1)

existing = settings.get('statusLine')
if not isinstance(existing, dict):
    existing = {}

settings['statusLine'] = {
    **existing,
    'type': 'command',
    'command': command,
}

with open(settings_file, 'w', encoding='utf-8') as handle:
    json.dump(settings, handle, indent=2)
    handle.write('\n')
PY
    return
  fi

  if command -v python >/dev/null 2>&1; then
    python - "$SETTINGS_FILE" "$CMD_STR" <<'PY'
import json
import os
import sys

settings_file, command = sys.argv[1], sys.argv[2]
settings = {}

if os.path.exists(settings_file):
    raw = open(settings_file, 'r', encoding='utf-8').read().strip()
    if raw:
        try:
            settings = json.loads(raw)
        except ValueError as error:
            print("  Failed to parse %s: %s" % (settings_file, error), file=sys.stderr)
            sys.exit(1)

if not isinstance(settings, dict):
    print("  %s must contain a JSON object" % settings_file, file=sys.stderr)
    sys.exit(1)

existing = settings.get('statusLine')
if not isinstance(existing, dict):
    existing = {}

existing.update({
    'type': 'command',
    'command': command,
})
settings['statusLine'] = existing

with open(settings_file, 'w', encoding='utf-8') as handle:
    json.dump(settings, handle, indent=2)
    handle.write('\n')
PY
    return
  fi

  echo "  Could not find node, python3, or python to update $SETTINGS_FILE"
  echo "  Update manually with:"
  echo "    \"statusLine\": { \"type\": \"command\", \"command\": \"$CMD_STR\" }"
  exit 1
}

write_settings_json
echo "  Configured statusLine in settings.json"

echo ""
echo "Done! Restart Claude Code to see the status bar."
echo ""
echo "Modes:"
echo "  full (default) — 3-line: model, context, cost, git, limits, cache"
echo "  lite           — 1-line: folder │ branch │ model │ 5h │ 7d"
echo ""
echo "Switch mode: re-run installer with 'lite' or 'full' argument"
echo "To uninstall: curl -fsSL https://raw.githubusercontent.com/$REPO/main/uninstall.sh | bash"
