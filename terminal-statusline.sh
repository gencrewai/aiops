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

# logged-in Claude account from ~/.claude.json (AIOPS_MASK_ACCOUNT=1 masks it)
account_email() {
  local cfg email lp
  cfg="${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json"
  [ -f "$cfg" ] || cfg="$HOME/.claude.json"
  [ -f "$cfg" ] || return
  # strip control chars (incl. ESC) to prevent terminal injection from a crafted config
  email="$(grep -oE '"emailAddress"[[:space:]]*:[[:space:]]*"[^"]*"' "$cfg" 2>/dev/null \
    | head -n1 | sed -E 's/.*"([^"]*)"[[:space:]]*$/\1/' | tr -d '[:cntrl:]')"
  [ -n "$email" ] || return
  if [ "${AIOPS_MASK_ACCOUNT:-0}" = "1" ]; then
    case "$email" in
      *@*) lp="${email%%@*}"; printf '%s***@%s' "${lp:0:2}" "${email#*@}" ;;
      *)   printf '%s' "$email" ;;
    esac
  else
    printf '%s' "$email"
  fi
}

# repo name from the main repo root (resolves worktrees/subdirs)
repo_name() {
  local common root
  common="$(git -C "$CWD" rev-parse --git-common-dir 2>/dev/null)"
  [ -n "$common" ] || return 0
  case "$common" in
    /*) ;;
    *) common="$CWD/$common" ;;
  esac
  # physical resolve so relative segments like ".." don't leak into the name
  root="$(cd "$(dirname "$common")" 2>/dev/null && pwd)"
  [ -n "$root" ] && [ "$root" != "/" ] || return 0
  basename "$root" 2>/dev/null
}

project="$(basename "$CWD" 2>/dev/null || printf '?')"
repo="$(repo_name)"
if [ -n "$repo" ] && [ "$repo" != "$project" ]; then
  project="${repo}/${project}"
fi
project="$(truncate_text "$project" 32)"

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

acct="$(account_email)"

case "$MODE" in
  tmux|prompt|shell|*)
    if [ -n "$acct" ]; then
      printf 'aiops %s | %s | %s' "$project" "$vcs" "$acct"
    else
      printf 'aiops %s | %s' "$project" "$vcs"
    fi
    ;;
esac
