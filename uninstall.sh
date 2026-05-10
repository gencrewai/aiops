#!/usr/bin/env bash
# claude-statusline uninstaller
set -euo pipefail

INSTALL_DIR="${CLAUDE_HOME:-$HOME/.claude}"
INSTALL_PATH="$INSTALL_DIR/claude-statusline.sh"
SETTINGS_FILE="$INSTALL_DIR/settings.json"

echo "Uninstalling claude-statusline..."

# remove script
if [ -f "$INSTALL_PATH" ]; then
  rm "$INSTALL_PATH"
  echo "  Removed $INSTALL_PATH"
else
  echo "  Script not found (already removed?)"
fi

remove_statusline() {
  if command -v node >/dev/null 2>&1; then
    node - "$SETTINGS_FILE" <<'NODE'
const fs = require('fs');

const [settingsFile] = process.argv.slice(2);
if (!fs.existsSync(settingsFile)) {
  process.exit(0);
}

const raw = fs.readFileSync(settingsFile, 'utf8').trim();
if (!raw) {
  process.exit(0);
}

let settings;
try {
  settings = JSON.parse(raw);
} catch (error) {
  console.error(`  Failed to parse ${settingsFile}: ${error.message}`);
  process.exit(1);
}

if (!settings || Array.isArray(settings) || typeof settings !== 'object') {
  console.error(`  ${settingsFile} must contain a JSON object`);
  process.exit(1);
}

if (Object.prototype.hasOwnProperty.call(settings, 'statusLine')) {
  delete settings.statusLine;
  fs.writeFileSync(settingsFile, `${JSON.stringify(settings, null, 2)}\n`);
}
NODE
    return
  fi

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$SETTINGS_FILE" <<'PY'
import json
import os
import sys

settings_file = sys.argv[1]
if not os.path.exists(settings_file):
    sys.exit(0)

raw = open(settings_file, 'r', encoding='utf-8').read().strip()
if not raw:
    sys.exit(0)

try:
    settings = json.loads(raw)
except json.JSONDecodeError as error:
    print(f"  Failed to parse {settings_file}: {error}", file=sys.stderr)
    sys.exit(1)

if not isinstance(settings, dict):
    print(f"  {settings_file} must contain a JSON object", file=sys.stderr)
    sys.exit(1)

if 'statusLine' in settings:
    del settings['statusLine']
    with open(settings_file, 'w', encoding='utf-8') as handle:
        json.dump(settings, handle, indent=2)
        handle.write('\n')
PY
    return
  fi

  if command -v python >/dev/null 2>&1; then
    python - "$SETTINGS_FILE" <<'PY'
import json
import os
import sys

settings_file = sys.argv[1]
if not os.path.exists(settings_file):
    sys.exit(0)

raw = open(settings_file, 'r', encoding='utf-8').read().strip()
if not raw:
    sys.exit(0)

try:
    settings = json.loads(raw)
except ValueError as error:
    print("  Failed to parse %s: %s" % (settings_file, error), file=sys.stderr)
    sys.exit(1)

if not isinstance(settings, dict):
    print("  %s must contain a JSON object" % settings_file, file=sys.stderr)
    sys.exit(1)

if 'statusLine' in settings:
    del settings['statusLine']
    with open(settings_file, 'w', encoding='utf-8') as handle:
        json.dump(settings, handle, indent=2)
        handle.write('\n')
PY
    return
  fi

  echo "  Could not find node, python3, or python to update $SETTINGS_FILE"
  exit 1
}

if [ -f "$SETTINGS_FILE" ]; then
  remove_statusline
  echo "  Removed statusLine from settings.json"
fi

echo ""
echo "Done! Restart Claude Code to apply."
