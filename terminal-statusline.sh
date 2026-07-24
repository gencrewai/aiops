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

# strip C0/C1 control chars (incl. ESC/CSI/OSC) from dir-derived names to
# prevent terminal injection, while keeping valid multibyte names intact:
# 1) drop invalid UTF-8 (lone C1 bytes)  2) drop UTF-8-encoded C1 (U+0080–U+009F)
# 3) drop C0 + DEL
sanitize_name() {
  if command -v iconv >/dev/null 2>&1; then
    # iconv -c drops invalid UTF-8 (lone C1 bytes) while keeping multibyte names
    iconv -f UTF-8 -t UTF-8 -c 2>/dev/null
  else
    # no iconv: drop raw C1 bytes outright (may mangle multibyte names; safe default)
    LC_ALL=C tr -d '\200-\237'
  fi | LC_ALL=C sed -E $'s/\xc2[\x80-\x9f]//g' | LC_ALL=C tr -d '[:cntrl:]'
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
  basename "$root" 2>/dev/null | sanitize_name
}

project="$(basename "$CWD" 2>/dev/null | sanitize_name)"
[ -n "$project" ] || project='?'
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
