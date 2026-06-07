#!/usr/bin/env bash
# aiops terminal/tmux uninstaller
set -euo pipefail

INSTALL_DIR="${AIOPS_HOME:-$HOME/.aiops}"
INSTALL_PATH="$INSTALL_DIR/terminal-statusline.sh"
UPDATE_PATH="$INSTALL_DIR/terminal-update.sh"
TMUX_SNIPPET="$INSTALL_DIR/tmux.conf"
AUTO_UPDATE_FILE="$INSTALL_DIR/auto-update.enabled"
LAST_CHECK_FILE="$INSTALL_DIR/terminal-update.last"
LOCK_DIR="$INSTALL_DIR/terminal-update.lock"

SHELL_BEGIN="# >>> aiops terminal status >>>"
SHELL_END="# <<< aiops terminal status <<<"
TMUX_BEGIN="# >>> aiops tmux status >>>"
TMUX_END="# <<< aiops tmux status <<<"

echo "Uninstalling aiops terminal status..."

remove_block() {
  local file="$1"
  local begin="$2"
  local end="$3"
  local tmp

  [ -f "$file" ] || return 0

  tmp="$(mktemp)"
  awk -v begin="$begin" -v end="$end" '
    $0 == begin { skip = 1; next }
    $0 == end { skip = 0; next }
    !skip { print }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

remove_block "$HOME/.zshrc" "$SHELL_BEGIN" "$SHELL_END"
remove_block "$HOME/.bashrc" "$SHELL_BEGIN" "$SHELL_END"
remove_block "$HOME/.bash_profile" "$SHELL_BEGIN" "$SHELL_END"
remove_block "$HOME/.tmux.conf" "$TMUX_BEGIN" "$TMUX_END"
echo "  Removed shell/tmux config blocks"

rm -f "$TMUX_SNIPPET"
rm -f "$INSTALL_PATH"
rm -f "$UPDATE_PATH"
rm -f "$AUTO_UPDATE_FILE"
rm -f "$LAST_CHECK_FILE"
rmdir "$LOCK_DIR" 2>/dev/null || true
echo "  Removed installed aiops terminal files"

if command -v tmux >/dev/null 2>&1 && tmux ls >/dev/null 2>&1; then
  tmux source-file "$HOME/.tmux.conf"
  echo "  Reloaded running tmux server"
fi

echo ""
echo "Done! Open a new terminal to apply shell changes."
