#!/usr/bin/env bash
# aiops model/profile switcher installer
# Usage: curl -fsSL https://raw.githubusercontent.com/gencrewai/aiops/main/models-install.sh | bash
set -euo pipefail

REPO="gencrewai/aiops"
INSTALL_DIR="${AIOPS_HOME:-$HOME/.aiops}"
PROFILE_DIR="$INSTALL_DIR/profiles"
SCRIPT_NAME="aiops-models.mjs"
REGISTRY_NAME="ai-model-profiles.json"
INSTALL_PATH="$INSTALL_DIR/aiops-models"
REGISTRY_PATH="$PROFILE_DIR/$REGISTRY_NAME"

echo "Installing aiops model/profile switcher..."

mkdir -p "$PROFILE_DIR"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P || pwd)"

install_file() {
  local source_path="$1"
  local remote_path="$2"
  local target_path="$3"

  if [ -f "$source_path" ]; then
    cp "$source_path" "$target_path"
  else
    curl -fsSL "https://raw.githubusercontent.com/$REPO/main/$remote_path" -o "$target_path"
  fi
}

install_file "$SCRIPT_DIR/$SCRIPT_NAME" "$SCRIPT_NAME" "$INSTALL_PATH"
chmod +x "$INSTALL_PATH"
echo "  Installed $INSTALL_PATH"

install_file "$SCRIPT_DIR/profiles/$REGISTRY_NAME" "profiles/$REGISTRY_NAME" "$REGISTRY_PATH"
echo "  Installed $REGISTRY_PATH"

echo ""
echo "Done."
echo "Run:"
echo "  $INSTALL_PATH list"
echo "  $INSTALL_PATH use codex-standard --dry-run"
echo "  $INSTALL_PATH use codex-standard"
