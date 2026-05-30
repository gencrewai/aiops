#!/usr/bin/env bash
# aiops terminal/tmux updater
set -euo pipefail

REPO="${AIOPS_REPO:-gencrewai/aiops}"
BRANCH="${AIOPS_BRANCH:-main}"
RAW_BASE_URL="${AIOPS_RAW_BASE_URL:-https://raw.githubusercontent.com/$REPO/$BRANCH}"
INSTALL_DIR="${AIOPS_HOME:-$HOME/.aiops}"
AUTO_UPDATE_FILE="$INSTALL_DIR/auto-update.enabled"
LAST_CHECK_FILE="$INSTALL_DIR/terminal-update.last"
LOCK_DIR="$INSTALL_DIR/terminal-update.lock"
INTERVAL_SECONDS="${AIOPS_AUTO_UPDATE_INTERVAL_SECONDS:-86400}"

MODE="force"
QUIET=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --auto)
      MODE="auto"
      QUIET=1
      ;;
    --background)
      if [ -f "$AUTO_UPDATE_FILE" ]; then
        ("$0" --auto >/dev/null 2>&1 &)
      fi
      exit 0
      ;;
    --force)
      MODE="force"
      ;;
    --quiet)
      QUIET=1
      ;;
    -h|--help)
      cat <<'EOF'
Usage: terminal-update.sh [--force] [--auto] [--background]

Options:
  --force       Update now, regardless of auto-update settings.
  --auto        Update only when auto-update is enabled and the interval elapsed.
  --background  Start an auto update check in the background and return immediately.
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

log() {
  if [ "$QUIET" -eq 0 ]; then
    printf '%s\n' "$*"
  fi
}

now_epoch() {
  date +%s
}

should_auto_update() {
  [ -f "$AUTO_UPDATE_FILE" ] || return 1

  local now last elapsed
  now="$(now_epoch)"
  last=0
  if [ -f "$LAST_CHECK_FILE" ]; then
    last="$(cat "$LAST_CHECK_FILE" 2>/dev/null || printf '0')"
    case "$last" in
      ''|*[!0-9]*) last=0 ;;
    esac
  fi

  elapsed=$((now - last))
  [ "$elapsed" -ge "$INTERVAL_SECONDS" ]
}

download_script() {
  local script_name="$1"
  local install_path="$2"
  local tmp

  tmp="$(mktemp)"
  if ! curl -fsSL "$RAW_BASE_URL/$script_name" -o "$tmp"; then
    rm -f "$tmp"
    return 1
  fi

  if ! bash -n "$tmp"; then
    rm -f "$tmp"
    return 1
  fi

  chmod +x "$tmp"
  mv "$tmp" "$install_path"
}

mkdir -p "$INSTALL_DIR"

if [ "$MODE" = "auto" ] && ! should_auto_update; then
  exit 0
fi

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  exit 0
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

if ! command -v curl >/dev/null 2>&1; then
  log "curl is required for aiops update"
  exit 1
fi

log "Updating aiops terminal status..."
download_script "terminal-statusline.sh" "$INSTALL_DIR/terminal-statusline.sh"
download_script "terminal-update.sh" "$INSTALL_DIR/terminal-update.sh"
now_epoch > "$LAST_CHECK_FILE"
log "Updated aiops terminal status."
