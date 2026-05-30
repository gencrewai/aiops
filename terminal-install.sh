#!/usr/bin/env bash
# aiops terminal/tmux installer
# Usage: curl -fsSL https://raw.githubusercontent.com/gencrewai/aiops/main/terminal-install.sh | bash
#        curl -fsSL https://raw.githubusercontent.com/gencrewai/aiops/main/terminal-install.sh | bash -s -- --auto-update
set -euo pipefail

REPO="gencrewai/aiops"
SCRIPT_NAME="terminal-statusline.sh"
UPDATE_SCRIPT_NAME="terminal-update.sh"
INSTALL_DIR="${AIOPS_HOME:-$HOME/.aiops}"
INSTALL_PATH="$INSTALL_DIR/$SCRIPT_NAME"
UPDATE_PATH="$INSTALL_DIR/$UPDATE_SCRIPT_NAME"
TMUX_SNIPPET="$INSTALL_DIR/tmux.conf"
AUTO_UPDATE_FILE="$INSTALL_DIR/auto-update.enabled"
LAST_CHECK_FILE="$INSTALL_DIR/terminal-update.last"

SHELL_BEGIN="# >>> aiops terminal status >>>"
SHELL_END="# <<< aiops terminal status <<<"
TMUX_BEGIN="# >>> aiops tmux status >>>"
TMUX_END="# <<< aiops tmux status <<<"

AUTO_UPDATE_REQUEST="preserve"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --auto-update)
      AUTO_UPDATE_REQUEST="enable"
      ;;
    --no-auto-update)
      AUTO_UPDATE_REQUEST="disable"
      ;;
    -h|--help)
      cat <<'EOF'
Usage: terminal-install.sh [--auto-update] [--no-auto-update]

Installs aiops status for zsh, bash, and tmux.

Options:
  --auto-update     Check for renderer updates in the background at most once per day.
  --no-auto-update  Disable background update checks.
EOF
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
  shift
done

echo "Installing aiops terminal status..."

mkdir -p "$INSTALL_DIR"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P || pwd)"
install_script_file() {
  local script_name="$1"
  local install_path="$2"

  if [ -f "$SCRIPT_DIR/$script_name" ]; then
    cp "$SCRIPT_DIR/$script_name" "$install_path"
  else
    curl -fsSL "https://raw.githubusercontent.com/$REPO/main/$script_name" -o "$install_path"
  fi

  chmod +x "$install_path"
}

install_script_file "$SCRIPT_NAME" "$INSTALL_PATH"
echo "  Installed $INSTALL_PATH"

install_script_file "$UPDATE_SCRIPT_NAME" "$UPDATE_PATH"
echo "  Installed $UPDATE_PATH"

case "$AUTO_UPDATE_REQUEST" in
  enable)
    : > "$AUTO_UPDATE_FILE"
    date +%s > "$LAST_CHECK_FILE"
    echo "  Auto update enabled (daily background check)"
    ;;
  disable)
    rm -f "$AUTO_UPDATE_FILE"
    echo "  Auto update disabled"
    ;;
  preserve)
    if [ -f "$AUTO_UPDATE_FILE" ]; then
      echo "  Auto update already enabled"
    else
      echo "  Auto update disabled (use --auto-update to enable)"
    fi
    ;;
esac

shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

remove_block() {
  local file="$1"
  local begin="$2"
  local end="$3"
  local tmp

  tmp="$(mktemp)"
  if [ -f "$file" ]; then
    awk -v begin="$begin" -v end="$end" '
      $0 == begin { skip = 1; next }
      $0 == end { skip = 0; next }
      !skip { print }
    ' "$file" > "$tmp"
  else
    : > "$tmp"
  fi

  mv "$tmp" "$file"
}

append_block() {
  local file="$1"
  local block="$2"
  local dir

  dir="$(dirname "$file")"
  mkdir -p "$dir"
  if [ -s "$file" ]; then
    printf '\n%s\n' "$block" >> "$file"
  else
    printf '%s\n' "$block" > "$file"
  fi
}

install_block() {
  local file="$1"
  local begin="$2"
  local end="$3"
  local body="$4"
  local block

  remove_block "$file" "$begin" "$end"
  block="${begin}"$'\n'"${body}"$'\n'"${end}"
  append_block "$file" "$block"
}

read -r -d '' SHELL_BODY <<'EOF' || true
export AIOPS_TERMINAL_STATUS="${AIOPS_TERMINAL_STATUS:-$HOME/.aiops/terminal-statusline.sh}"
export AIOPS_TERMINAL_UPDATE="${AIOPS_TERMINAL_UPDATE:-$HOME/.aiops/terminal-update.sh}"

__aiops_maybe_auto_update() {
  if [ -z "${__AIOPS_AUTO_UPDATE_STARTED:-}" ] && [ -x "$AIOPS_TERMINAL_UPDATE" ]; then
    __AIOPS_AUTO_UPDATE_STARTED=1
    "$AIOPS_TERMINAL_UPDATE" --background >/dev/null 2>&1 || true
  fi
}

__aiops_maybe_auto_update

if [ -x "$AIOPS_TERMINAL_STATUS" ]; then
  if [ -n "${ZSH_VERSION:-}" ]; then
    autoload -Uz add-zsh-hook 2>/dev/null || true

    __aiops_zsh_precmd() {
      local aiops_status

      if [ -z "${__AIOPS_ORIGINAL_RPROMPT_CAPTURED:-}" ]; then
        __AIOPS_ORIGINAL_RPROMPT="${RPROMPT-}"
        __AIOPS_ORIGINAL_RPROMPT_CAPTURED=1
      fi

      aiops_status="$("$AIOPS_TERMINAL_STATUS" prompt 2>/dev/null)"
      aiops_status="${aiops_status//\%/%%}"

      if [ -n "$aiops_status" ]; then
        RPROMPT="$aiops_status${__AIOPS_ORIGINAL_RPROMPT:+ $__AIOPS_ORIGINAL_RPROMPT}"
      else
        RPROMPT="$__AIOPS_ORIGINAL_RPROMPT"
      fi
    }

    add-zsh-hook -d precmd __aiops_zsh_precmd 2>/dev/null || true
    add-zsh-hook precmd __aiops_zsh_precmd 2>/dev/null || true
  elif [ -n "${BASH_VERSION:-}" ] && [ -z "${__AIOPS_BASH_PROMPT_HOOKED:-}" ]; then
    __AIOPS_BASH_PROMPT_HOOKED=1
    __AIOPS_ORIGINAL_PROMPT_COMMAND="${PROMPT_COMMAND-}"

    __aiops_prompt_command() {
      local aiops_status

      if [ -z "${__AIOPS_ORIGINAL_PS1_CAPTURED:-}" ]; then
        __AIOPS_ORIGINAL_PS1="${PS1-}"
        __AIOPS_ORIGINAL_PS1_CAPTURED=1
      fi

      aiops_status="$("$AIOPS_TERMINAL_STATUS" prompt 2>/dev/null)"
      aiops_status="${aiops_status//\\/\\\\}"
      aiops_status="${aiops_status//\$/\\$}"
      aiops_status="${aiops_status//\`/\\\`}"

      if [ -n "$aiops_status" ]; then
        PS1="${aiops_status}"$'\n'"${__AIOPS_ORIGINAL_PS1}"
      else
        PS1="${__AIOPS_ORIGINAL_PS1}"
      fi

      if [ -n "${__AIOPS_ORIGINAL_PROMPT_COMMAND:-}" ] && [ "$__AIOPS_ORIGINAL_PROMPT_COMMAND" != "__aiops_prompt_command" ]; then
        eval "$__AIOPS_ORIGINAL_PROMPT_COMMAND"
      fi
    }

    PROMPT_COMMAND=__aiops_prompt_command
  fi
fi
EOF

write_shell_config() {
  local file="$1"
  install_block "$file" "$SHELL_BEGIN" "$SHELL_END" "$SHELL_BODY"
  echo "  Updated $file"
}

write_shell_config "$HOME/.zshrc"
write_shell_config "$HOME/.bashrc"

if [ -f "$HOME/.bash_profile" ] && ! grep -Eq '(^|[[:space:]])\.?[[:space:]]+["'\'']?\$HOME/\.bashrc|(^|[[:space:]])\.?[[:space:]]+["'\'']?~/\.bashrc|\. ~/.bashrc|source ~/.bashrc' "$HOME/.bash_profile"; then
  write_shell_config "$HOME/.bash_profile"
fi

QUOTED_INSTALL_PATH="$(shell_quote "$INSTALL_PATH")"
QUOTED_UPDATE_PATH="$(shell_quote "$UPDATE_PATH")"
cat > "$TMUX_SNIPPET" <<EOF
# Generated by aiops terminal-install.sh
set -g status on
set -g status-interval 5
set -g status-left-length 100
run-shell -b "$QUOTED_UPDATE_PATH --background >/dev/null 2>&1 || true"
set -g status-left "#[fg=colour111]#($QUOTED_INSTALL_PATH tmux \"#{pane_current_path}\")#[default] "
EOF
echo "  Wrote $TMUX_SNIPPET"

TMUX_BODY="source-file \"${TMUX_SNIPPET}\""
install_block "$HOME/.tmux.conf" "$TMUX_BEGIN" "$TMUX_END" "$TMUX_BODY"
echo "  Updated $HOME/.tmux.conf"

if command -v tmux >/dev/null 2>&1 && tmux ls >/dev/null 2>&1; then
  tmux source-file "$HOME/.tmux.conf"
  echo "  Reloaded running tmux server"
fi

echo ""
echo "Done! Open a new terminal, or run: source ~/.zshrc"
echo "For existing tmux sessions, press your tmux reload binding or run: tmux source-file ~/.tmux.conf"
echo "Manual update: $UPDATE_PATH --force"
