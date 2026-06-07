#!/usr/bin/env bash
# aiops terminal/tmux statusline renderer
set -u

MODE="${1:-prompt}"
CWD_ARG="${2:-${AIOPS_CWD:-${PWD:-$HOME}}}"

if [ -d "$CWD_ARG" ]; then
  CWD="$CWD_ARG"
else
  CWD="${PWD:-$HOME}"
fi

clean_text() {
  local value="${1:-}"
  value="${value//$'\n'/ }"
  value="${value//$'\r'/ }"
  value="${value//$'\t'/ }"
  printf '%s' "$value"
}

truncate_text() {
  local value max
  value="$(clean_text "${1:-}")"
  max="${2:-32}"

  if [ "${#value}" -gt "$max" ] && [ "$max" -gt 3 ]; then
    printf '%s...' "${value:0:max-3}"
  else
    printf '%s' "$value"
  fi
}

git_branch() {
  git -C "$CWD" symbolic-ref --quiet --short HEAD 2>/dev/null \
    || git -C "$CWD" rev-parse --short HEAD 2>/dev/null \
    || true
}

git_dirty_count() {
  local status
  status="$(git -C "$CWD" status --porcelain 2>/dev/null || true)"
  if [ -z "$status" ]; then
    printf '0'
  else
    printf '%s\n' "$status" | sed '/^$/d' | wc -l | tr -d ' '
  fi
}

project="$(basename "$CWD" 2>/dev/null || printf '?')"
project="$(truncate_text "$project" 24)"

branch="$(git_branch)"
if [ -n "$branch" ]; then
  branch="$(truncate_text "$branch" 24)"
  dirty="$(git_dirty_count)"
  if [ "$dirty" -gt 0 ] 2>/dev/null; then
    vcs="${branch} *${dirty}"
  else
    vcs="$branch"
  fi
else
  vcs="no-git"
fi

case "$MODE" in
  tmux)
    printf 'aiops %s | %s' "$project" "$vcs"
    ;;
  prompt|shell|*)
    printf 'aiops %s | %s' "$project" "$vcs"
    ;;
esac
