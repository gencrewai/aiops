#!/usr/bin/env bash
# aiops model/profile switcher uninstaller
# Usage: curl -fsSL https://raw.githubusercontent.com/gencrewai/aiops/main/models-uninstall.sh | bash
set -euo pipefail

INSTALL_DIR="${AIOPS_HOME:-$HOME/.aiops}"
INSTALL_PATH="$INSTALL_DIR/aiops-models"
REGISTRY_PATH="$INSTALL_DIR/profiles/ai-model-profiles.json"

echo "Uninstalling aiops model/profile switcher..."

rm -f "$INSTALL_PATH"
rm -f "$REGISTRY_PATH"
rmdir "$INSTALL_DIR/profiles" 2>/dev/null || true

echo "Done."
