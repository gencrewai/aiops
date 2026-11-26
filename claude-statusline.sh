#!/usr/bin/env bash
# Claude Code statusLine — 3/4-line or 1-line status bar
# The task-context line (🏷 peer name │ 📋 session title │ ▶ current work │
# ✎ edited repos) appears automatically when transcript/session data is available.
# Usage: bash statusline.sh               → 3-line, soft pastel (default)
#        bash statusline.sh lite           → 1-line
#        bash statusline.sh --left         → 3-line, remaining bars
#        bash statusline.sh --hard         → 3-line, classic ANSI colors
#        bash statusline.sh lite --left --hard → combine freely
# https://github.com/gencrewai/aiops
set -u

# --- parse arguments ---
MODE="full"
VIEW="used"
THEME="soft"
MASK_ACCOUNT=0

for arg in "$@"; do
  case "$arg" in
    lite)           MODE="lite" ;;
    --left)         VIEW="left" ;;
    --hard)         THEME="normal" ;;
    --mask-account) MASK_ACCOUNT=1 ;;
  esac
done

input=$(cat)

# --- color constants ---
RST=$'\033[0m'
DIM=$'\033[2m'
BOLD=$'\033[1m'

if [ "$THEME" = "soft" ]; then
  # ice-cream pastel palette (truecolor)
  CYAN=$'\033[38;2;137;207;240m'    # sky blue
  GREEN=$'\033[38;2;152;224;173m'   # mint
  YELLOW=$'\033[38;2;255;213;128m'  # butter
  RED=$'\033[38;2;255;154;139m'     # peach coral
  WHITE=$'\033[38;2;255;253;230m'   # cream
  MAGENTA=$'\033[38;2;200;162;200m' # lilac
  BLUE=$'\033[38;2;174;198;255m'    # periwinkle
  SEP=" ${DIM}│${RST} "
else
  CYAN=$'\033[36m'
  GREEN=$'\033[32m'
  YELLOW=$'\033[33m'
  RED=$'\033[31m'
  WHITE=$'\033[37m'
  MAGENTA=$'\033[35m'
  BLUE=$'\033[34m'
  SEP=" ${DIM}│${RST} "
fi

# --- extract helpers ---
str_field() {
  printf '%s' "$input" | grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -n1 | sed -E 's/.*"([^"]*)"\s*$/\1/'
}
num_field() {
  printf '%s' "$input" | grep -oE "\"$1\"[[:space:]]*:[[:space:]]*[0-9.]+" | head -n1 | grep -oE '[0-9.]+$'
}
int_part() {
  local n="${1:-0}"
  n="${n%%.*}"
  [ -z "$n" ] && n=0
  printf '%s' "$n"
}

# --- account helpers (logged-in Claude account; not present in stdin JSON) ---
account_config() {
  local cfg="${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json"
  [ -f "$cfg" ] && { printf '%s' "$cfg"; return; }
  [ -f "$HOME/.claude.json" ] && printf '%s' "$HOME/.claude.json"
}
get_account() {
  local cfg
  cfg=$(account_config)
  [ -n "$cfg" ] || return
  # strip control chars (incl. ESC) to prevent terminal injection from a crafted config
  grep -oE '"emailAddress"[[:space:]]*:[[:space:]]*"[^"]*"' "$cfg" 2>/dev/null \
    | head -n1 | sed -E 's/.*"([^"]*)"[[:space:]]*$/\1/' | tr -d '[:cntrl:]'
}
mask_email() {
  local e="$1" lp dom
  case "$e" in
    *@*) lp="${e%%@*}"; dom="${e#*@}"; printf '%s***@%s' "${lp:0:2}" "$dom" ;;
    *)   printf '%s' "$e" ;;
  esac
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

# --- TeamAI relay: last account used ---
# TeamAI rotates accounts per request across every session on this machine, so
# the closest live answer is the Claude account it used last. Read it from
# TeamAI's own state files; no TeamAI executable runs. Only when this session's
# base URL is one of TeamAI's loopback Claude ports and its server pid is alive.
teamai_home() { printf '%s' "${TEAMAI_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/teamai}"; }
# The interpreter comes only from fixed absolute locations, never $PATH (this
# runs on every render). macOS's /usr/bin stub offers an install dialog, so it is skipped there.
fixed_python() {
  local p
  for p in /opt/homebrew/bin/python3 /usr/local/bin/python3 \
           /Library/Developer/CommandLineTools/usr/bin/python3 /usr/bin/python3; do
    [ "$p" = /usr/bin/python3 ] && [ "$(uname -s)" = Darwin ] && continue
    [ -x "$p" ] && { printf '%s' "$p"; return 0; }
  done
  return 1
}
get_teamai_account() {
  local home py
  home=$(teamai_home)
  [ -f "$home/config.json" ] || return 1
  [ -n "${ANTHROPIC_BASE_URL:-}" ] || return 1
  py=$(fixed_python) || return 1
  "$py" -I -S -c '
import json, os, re, subprocess, sys, urllib.parse
home = sys.argv[1]
try:
    url = urllib.parse.urlsplit(sys.argv[2]); port = url.port
except ValueError:
    sys.exit(1)
# The parsed host, so "http://localhost:3456@elsewhere" is not taken for this machine.
if url.scheme not in ("http", "https") or url.hostname not in ("localhost", "127.0.0.1", "::1") or not port:
    sys.exit(1)
def load(name):
    with open(os.path.join(home, name), encoding="utf-8") as f:
        return json.load(f)
try:
    config = load("config.json"); proxy = config.get("proxy") or {}
    ports = {proxy.get("claudePort"), 3456, *((proxy.get("legacyPorts") or {}).get("claude") or [])}
    if port not in ports:
        sys.exit(1)
    # A live pid is not enough once TeamAI stopped: the pid may now belong to anything.
    pid = int(load("server.json")["pid"])
    command = subprocess.run(["/bin/ps", "-o", "command=", "-p", str(pid)],
                             capture_output=True, text=True, timeout=2).stdout
    if not re.search(r"\b(teamai|cli\.js) (server|supervise)\b", command):
        sys.exit(1)
    used = load("state.json").get("accounts") or {}
    last, label = max(((used.get(a.get("credentialId")) or {}).get("lastUsed") or 0, a.get("label") or "")
                      for a in config.get("accounts") or [] if a.get("provider") == "claude")
except Exception:
    sys.exit(1)
if not last:
    sys.exit(1)
print(label)
' "$home" "$ANTHROPIC_BASE_URL" 2>/dev/null | tr -d '[:cntrl:]'
}

# --- teamclaude proxy active account ---
# When this session routes through the teamclaude multi-account proxy
# (KarpelesLab/teamclaude), the effective account rotates per-request and is
# NOT reflected in .claude.json (which holds the static CLI /login account).
# Read the live account from `teamclaude status`, cached ~8s so the statusline
# stays fast. Returns non-zero when not on the proxy, so callers fall back.
get_teamclaude_account() {
  # only the local teamclaude proxy (loopback:3456); ignore remote hosts on that port
  case "${ANTHROPIC_BASE_URL:-}" in
    http://localhost:3456|http://localhost:3456/*|https://localhost:3456|https://localhost:3456/*) ;;
    http://127.0.0.1:3456|http://127.0.0.1:3456/*|https://127.0.0.1:3456|https://127.0.0.1:3456/*) ;;
    "http://[::1]:3456"|"http://[::1]:3456/"*|"https://[::1]:3456"|"https://[::1]:3456/"*) ;;
    *) return 1 ;;
  esac
  # resolve teamclaude only from fixed trusted install locations — this statusline
  # runs automatically on every render, so never execute a `teamclaude` from $PATH
  # or an env-provided path (both are attacker-influenceable).
  local tcbin="" p=""
  for p in /opt/homebrew/bin/teamclaude /usr/local/bin/teamclaude \
           "$HOME/.bun/bin/teamclaude" "$HOME/.local/bin/teamclaude" /usr/bin/teamclaude; do
    [ -x "$p" ] && { tcbin="$p"; break; }
  done
  [ -n "$tcbin" ] || return 1
  # canonicalize (resolve symlinks) and validate the REAL target: must be a
  # regular file we own and that is not group/other-writable
  local real
  real=$(readlink -f "$tcbin" 2>/dev/null || realpath "$tcbin" 2>/dev/null || printf '%s' "$tcbin")
  tcbin="$real"
  { [ -f "$tcbin" ] && [ ! -L "$tcbin" ] && [ -x "$tcbin" ] && [ -O "$tcbin" ]; } || return 1
  local _m
  _m=$(stat -f '%Lp' "$tcbin" 2>/dev/null || stat -c '%a' "$tcbin" 2>/dev/null || echo 777)
  { [ $(( ${_m: -2:1} & 2 )) -eq 0 ] && [ $(( ${_m: -1:1} & 2 )) -eq 0 ]; } || return 1
  # private per-user cache dir we own (avoid symlink attacks in a shared /tmp)
  local cdir="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/aiops.$(id -u 2>/dev/null || echo u)"
  [ -L "$cdir" ] && return 1
  mkdir -p "$cdir" 2>/dev/null || return 1
  chmod 700 "$cdir" 2>/dev/null
  { [ -d "$cdir" ] && [ ! -L "$cdir" ] && [ -O "$cdir" ]; } || return 1
  local cache="$cdir/tc-account" now mtime=0 acct="" tc="" tmpf=""
  now=$(date +%s)
  [ -f "$cache" ] && mtime=$(stat -f %m "$cache" 2>/dev/null || stat -c %Y "$cache" 2>/dev/null || echo 0)
  if [ $(( now - mtime )) -ge 8 ]; then
    # always run under a timeout so a hung teamclaude never stalls the statusline;
    # if no timeout tool exists, skip the live fetch and fall back to cache/.claude.json
    if command -v timeout >/dev/null 2>&1; then tc=$(timeout 2 "$tcbin" status 2>/dev/null)
    elif command -v gtimeout >/dev/null 2>&1; then tc=$(gtimeout 2 "$tcbin" status 2>/dev/null)
    else tc=""; fi
    # strip control chars (incl. ESC) to prevent terminal injection
    acct=$(printf '%s' "$tc" | grep -m1 -E '^Active account:' | sed -E 's/^Active account:[[:space:]]*//' | tr -d '[:cntrl:]')
    if [ -n "$acct" ] && tmpf=$(mktemp "$cdir/tc.XXXXXX" 2>/dev/null); then
      printf '%s' "$acct" > "$tmpf" && mv -f "$tmpf" "$cache" 2>/dev/null && mtime=$(date +%s)
      [ -e "$tmpf" ] && rm -f "$tmpf" 2>/dev/null
    fi
  fi
  # bounded staleness: discard a cache older than 60s so a persistently failing
  # refresh falls back to .claude.json instead of pinning a stale account
  [ $(( $(date +%s) - mtime )) -lt 60 ] || return 1
  acct=$(cat "$cache" 2>/dev/null | tr -d '[:cntrl:]')
  [ -n "$acct" ] || return 1
  printf '%s' "$acct"
}

# --- task-context helpers (session title / current work / edited repos) ---
# minimal JSON string unescape for display, then control-char sanitize
decode_json_str() {
  sed -E 's/\\[nrt]/ /g; s/\\"/"/g; s/\\\\/\\/g' | sanitize_name | redact_secretish
}
# value of the first/last JSON string field "$1" in the blob on stdin
json_field_first() {
  grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"([^\"\\\\]|\\\\.)*\"" | head -n1 \
    | sed -E 's/^"[^"]*"[[:space:]]*:[[:space:]]*"//; s/"$//' | decode_json_str
}
json_field_last() {
  grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"([^\"\\\\]|\\\\.)*\"" | tail -n1 \
    | sed -E 's/^"[^"]*"[[:space:]]*:[[:space:]]*"//; s/"$//' | decode_json_str
}
# mask secret-looking spans before display (statusline is screenshot/share surface):
# known token prefixes + key/token/secret/password-style assignments
redact_secretish() {
  sed -E \
    -e 's/sk-[A-Za-z0-9_-]{8,}/■■■/g' \
    -e 's/(ghp|gho|ghu|ghs)_[A-Za-z0-9]{16,}/■■■/g' \
    -e 's/github_pat_[A-Za-z0-9_]{20,}/■■■/g' \
    -e 's/glpat-[A-Za-z0-9_-]{10,}/■■■/g' \
    -e 's/(AKIA|ASIA)[0-9A-Z]{12,}/■■■/g' \
    -e 's/xox[a-z]-[A-Za-z0-9-]{10,}/■■■/g' \
    -e 's/xapp-[A-Za-z0-9-]{10,}/■■■/g' \
    -e 's/eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9._-]{10,}/■■■/g' \
    -e 's/([Bb][Ee][Aa][Rr][Ee][Rr][[:space:]]+)[^[:space:]]+/\1■■■/g' \
    -e "s/([A-Za-z0-9_-]*([Kk][Ee][Yy]|[Tt][Oo][Kk][Ee][Nn]|[Ss][Ee][Cc][Rr][Ee][Tt]|[Pp][Aa][Ss][Ss][Ww]?[Oo]?[Rr]?[Dd]?|[Pp][Ww][Dd]?|[Cc][Rr][Ee][Dd][A-Za-z]*)[A-Za-z0-9_-]*[\"']?[[:space:]]*[=:]).*/\1■■■/"
}
truncate_str() {
  local s="$1" n="${2:-40}"
  if [ "${#s}" -gt "$n" ]; then
    # re-sanitize after the cut in case a multibyte char was split
    printf '%s' "${s:0:$n}" | sanitize_name
    printf '…'
  else
    printf '%s' "$s"
  fi
}

# --- data extraction ---
model_name=$(str_field "display_name")
[ -z "$model_name" ] && model_name="Claude"
model_short=$(printf '%s' "$model_name" | sed -E 's/^Claude //')

# reasoning effort (Opus 4.5+): "effort":{"level":"high"} or "effort":"high"
effort_level=$(printf '%s' "$input" | grep -oE '"effort"[[:space:]]*:[[:space:]]*\{[^}]*\}' | grep -oE '"level"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 | sed -E 's/.*"([^"]*)"[[:space:]]*$/\1/')
[ -z "$effort_level" ] && effort_level=$(printf '%s' "$input" | grep -oE '"effort"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 | sed -E 's/.*"([^"]*)"[[:space:]]*$/\1/')

input_tokens=$(int_part "$(num_field "total_input_tokens")")
output_tokens=$(int_part "$(num_field "total_output_tokens")")
ctx_size=$(int_part "$(num_field "context_window_size")")
ctx_pct=$(int_part "$(num_field "used_percentage")")
cost_usd=$(num_field "total_cost_usd");           [ -z "$cost_usd" ] && cost_usd="0"

# Claude Code's payload may under-report context_window_size as 200K for
# 1M-context models (fable/mythos, and opus/sonnet "[1m]" variants) — the
# denominator then reads e.g. "551K/200K". Correct the window from the model id
# and recompute the pct against it so the ctx bar agrees with the denominator.
# No-op once the payload reports >= 1M (forward-compatible with a CC fix).
model_id=$(printf '%s' "$input" | grep -oE '"model"[[:space:]]*:[[:space:]]*\{[^}]*\}' | grep -oE '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 | sed -E 's/.*"([^"]*)"[[:space:]]*$/\1/')
case "$model_id" in
  *"[1m]"*|claude-fable-*|claude-mythos-*)
    if [ "$ctx_size" -lt 1000000 ]; then
      ctx_size=1000000
      ctx_pct=$(( (input_tokens + output_tokens) * 100 / ctx_size ))
      [ "$ctx_pct" -gt 100 ] && ctx_pct=100
    fi
    ;;
esac

duration_ms=$(int_part "$(num_field "total_duration_ms")")
lines_added=$(int_part "$(num_field "total_lines_added")")
lines_removed=$(int_part "$(num_field "total_lines_removed")")

cache_read=$(int_part "$(num_field "cache_read_input_tokens")")
cache_create=$(int_part "$(num_field "cache_creation_input_tokens")")

cwd=$(str_field "current_dir")
[ -z "$cwd" ] && cwd=$(str_field "cwd")
project_name=$(basename "$cwd" 2>/dev/null | sanitize_name)
[ -z "$project_name" ] && project_name="?"

# repository identity for the project segment — always visible:
#   origin remote "owner/repo" (e.g. acme/web-app) shown
#   in front of the folder name; the folder part is omitted when it equals the
#   repo name (avoids "repo/repo" at the checkout root). Without a usable
#   origin, fall back to the main-repo-root basename prefix (worktree/subdir
#   only, as before). Outside git the plain folder name remains.
repo_common=""
[ -n "$cwd" ] && repo_common=$(git -C "$cwd" rev-parse --git-common-dir 2>/dev/null)
if [ -n "$repo_common" ]; then
  case "$repo_common" in
    /*) ;;
    *) repo_common="$cwd/$repo_common" ;;
  esac
  # physical resolve so relative segments like ".." don't leak into the name
  repo_root=$(cd "$(dirname "$repo_common")" 2>/dev/null && pwd)
  repo_name=$(basename "$repo_root" 2>/dev/null | sanitize_name)
  # origin "owner/repo" from https or scp-style URLs; empty when absent/unparsable
  remote_id=$(git -C "$cwd" remote get-url origin 2>/dev/null \
    | sed -E 's#\.git/*$##; s#/+$##' \
    | grep -oE '[^/:]+/[^/:]+$' | sanitize_name)
  case "$remote_id" in
    ?*/?*) ;;
    *) remote_id="" ;;
  esac
  if [ -n "$remote_id" ]; then
    if [ "$project_name" = "${remote_id##*/}" ]; then
      project_name="$remote_id"
    else
      project_name="${remote_id}/${project_name}"
    fi
  elif [ -n "$repo_name" ] && [ "$repo_name" != "/" ] && [ "$repo_name" != "$project_name" ]; then
    project_name="${repo_name}/${project_name}"
  fi
fi

# session id — locates this session's task/todo stores; fall back to transcript filename
session_id=$(str_field "session_id")
transcript_path=$(str_field "transcript_path")
if [ -z "$session_id" ] && [ -n "$transcript_path" ]; then
  session_id=$(basename "$transcript_path" .jsonl 2>/dev/null)
fi

# trust boundary: stdin is harness-produced, but never trust paths from it.
# session_id must be a full UUID (it feeds glob paths — a short prefix would
# match other sessions' files); transcript_path must be that session's own
# <session_id>.jsonl: a regular non-symlink file whose canonicalized (pwd -P)
# directory sits under the Claude projects dir.
printf '%s' "$session_id" \
  | grep -qE '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$' || session_id=""
claude_projects_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
tp_ok=""
if [ -n "$session_id" ] && [ -n "$transcript_path" ] \
  && [ -f "$transcript_path" ] && [ ! -L "$transcript_path" ] \
  && [ "$(basename "$transcript_path")" = "${session_id}.jsonl" ]; then
  proj_real=$(cd "$claude_projects_dir" 2>/dev/null && pwd -P)
  tp_dir=$(cd "$(dirname "$transcript_path")" 2>/dev/null && pwd -P)
  if [ -n "$proj_real" ] && [ -n "$tp_dir" ]; then
    case "$tp_dir" in
      "$proj_real"|"$proj_real"/*) tp_ok=1 ;;
    esac
  fi
fi
[ -n "$tp_ok" ] || transcript_path=""

# peer name: what SendMessage/ListAgents call this session (e.g. "my-laptop-ea").
# Claude Code keeps one registry file per live process at <config>/sessions/<pid>.json
# with the current sessionId (it follows /clear) and that name, and runs this
# script as its direct child: read $PPID.json, walking up at most 4 ancestors,
# and accept it only when its sessionId is this session's. One file, no scan.
# The file is opened once (no symlink follow, non-blocking) and judged by fstat
# on that descriptor, then read up to 64K: a FIFO, device or link is skipped.
peer_name=""
peer_source=""
if [ -n "$session_id" ] && reg_py=$(fixed_python); then
  reg_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/sessions"
  [ -d "$reg_dir" ] || reg_dir="$HOME/.claude/sessions"
  peer_line=$("$reg_py" -I -S -c '
import json, os, stat, subprocess, sys
reg_dir, sid, pid, cap = sys.argv[1], sys.argv[2], sys.argv[3], 65536
flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0)
def entry(pid):
    try:
        fd = os.open(os.path.join(reg_dir, pid + ".json"), flags)
    except OSError:
        return None
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_size > cap:
            return None
        data = os.read(fd, cap + 1)
    except OSError:
        return None
    finally:
        os.close(fd)
    try:
        reg = json.loads(data[:cap].decode("utf-8"))
    except (ValueError, RecursionError):
        return None
    return reg if isinstance(reg, dict) and reg.get("sessionId") == sid else None
reg = None
for _ in range(4):
    if not pid.isdigit() or int(pid) <= 1:
        break
    reg = entry(pid)
    if reg is not None:
        break
    try:
        pid = subprocess.run(["/bin/ps", "-o", "ppid=", "-p", pid],
                             capture_output=True, text=True, timeout=2).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        break
if reg is None:
    sys.exit(1)
name, source = reg.get("name"), reg.get("nameSource")
if not isinstance(name, str) or not name:
    sys.exit(1)
source = source if isinstance(source, str) and source.isalpha() else ""
# whitespace becomes a space (not dropped) so redact_secretish still sees "Bearer x"
name = "".join(c if c.isprintable() else " " if c.isspace() else "" for c in name)
print(source + "\t" + name)
' "$reg_dir" "$session_id" "$PPID" 2>/dev/null)
  if [ -n "$peer_line" ]; then
    tab=$'\t'
    peer_source="${peer_line%%"$tab"*}"
    peer_name=$(printf '%s' "${peer_line#*"$tab"}" | sanitize_name | redact_secretish)
  fi
fi

# --- task context: session title / current work / repos edited this session ---
task_title=$(printf '%s' "$input" | json_field_first "session_name")
task_now=""
task_repos=""

if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
  t_tail=$(tail -c 65536 "$transcript_path" 2>/dev/null)

  # session title: explicit session_name → latest auto ai-title.
  # no raw-prompt fallback: a first prompt may carry secrets and can be an
  # unbounded line (CPU per refresh) — the title slot shows curated summaries only
  [ -z "$task_title" ] && task_title=$(printf '%s' "$t_tail" | json_field_last "aiTitle")

  # current work: in-progress task (tasks store) → todo store — curated metadata only
  # (same cfg_base convention as the subagent/task-count section below)
  if [ -n "$session_id" ]; then
    tc_base="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
    [ -d "$tc_base/todos" ] || [ -d "$tc_base/tasks" ] || tc_base="$HOME/.claude"
    tc_task_dir="$tc_base/tasks/$session_id"
    if [ -d "$tc_task_dir" ]; then
      while IFS= read -r tf; do
        [ -f "$tf" ] || continue
        # byte-bound the read (runaway file guard); split multibyte at the
        # boundary is dropped downstream by decode_json_str → sanitize_name
        flat=$(tail -c 16384 "$tf" 2>/dev/null | tr -d '\n')
        printf '%s' "$flat" | grep -qE '"status"[[:space:]]*:[[:space:]]*"in_progress"' || continue
        task_now=$(printf '%s' "$flat" | json_field_first "activeForm")
        [ -z "$task_now" ] && task_now=$(printf '%s' "$flat" | json_field_first "subject")
        [ -n "$task_now" ] && break
      done <<EOF_TASKS
$(ls -t "$tc_task_dir"/*.json 2>/dev/null)
EOF_TASKS
    fi
    if [ -z "$task_now" ]; then
      for tf in "$tc_base/todos/$session_id"*.json; do
        [ -f "$tf" ] || continue
        # byte-bound as above — the newest todos sit at the array tail anyway
        todo_obj=$(tail -c 16384 "$tf" 2>/dev/null | tr -d '\n' | grep -oE '\{[^{}]*"in_progress"[^{}]*\}' | tail -n1)
        [ -n "$todo_obj" ] || continue
        task_now=$(printf '%s' "$todo_obj" | json_field_first "activeForm")
        [ -z "$task_now" ] && task_now=$(printf '%s' "$todo_obj" | json_field_first "content")
        [ -n "$task_now" ] && break
      done
    fi
  fi
  # no lastPrompt fallback: raw prompts are uncurated text on a share surface —
  # the current-work slot renders task/todo metadata only

  # repos edited this session: Edit/Write file paths → repo names, recent first, max 3
  edit_paths=$(printf '%s' "$t_tail" \
    | grep -E '"name"[[:space:]]*:[[:space:]]*"(Edit|Write|MultiEdit|NotebookEdit)"' \
    | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | sed -E 's/.*:[[:space:]]*"//; s/"$//' | tail -n 20)
  if [ -n "$edit_paths" ]; then
    edit_dirs=$(printf '%s\n' "$edit_paths" \
      | awk '{a[NR]=$0} END{for(i=NR;i>=1;i--)print a[i]}' \
      | while IFS= read -r p; do dirname "$p" 2>/dev/null; done \
      | awk '!seen[$0]++' | head -n 8)
    seen_repos="|"
    rcount=0
    while IFS= read -r d; do
      [ -n "$d" ] && [ -d "$d" ] || continue
      repo_gc=$(git -C "$d" rev-parse --git-common-dir 2>/dev/null) || continue
      [ -n "$repo_gc" ] || continue
      case "$repo_gc" in
        /*) ;;
        *) repo_gc="$d/$repo_gc" ;;
      esac
      rr=$(cd "$(dirname "$repo_gc")" 2>/dev/null && pwd) || continue
      rn=$(basename "$rr" 2>/dev/null | sanitize_name)
      [ -n "$rn" ] && [ "$rn" != "/" ] || continue
      case "$seen_repos" in *"|$rn|"*) continue ;; esac
      seen_repos="${seen_repos}${rn}|"
      if [ -z "$task_repos" ]; then task_repos="$rn"; else task_repos="${task_repos}·${rn}"; fi
      rcount=$((rcount+1))
      if [ "$rcount" -ge 3 ]; then break; fi
    done <<EOF_DIRS
$edit_dirs
EOF_DIRS
  fi
fi

# effective account: a rotating relay (TeamAI, else legacy teamclaude) wins over
# the static CLI login in .claude.json when this session routes through it.
# Where TeamAI is set up, teamclaude is retired: its leftover CLI is never run.
# Deciding by endpoint instead would not work: both relays use port 3456, so every
# moment TeamAI is down would run that CLI again on each render.
ACCOUNT_VIA_PROXY=""
if account_email=$(get_teamai_account) && [ -n "$account_email" ]; then
  ACCOUNT_VIA_PROXY="tai"
elif [ ! -f "$(teamai_home)/config.json" ] && account_email=$(get_teamclaude_account); then
  ACCOUNT_VIA_PROXY="tc"
else
  account_email=$(get_account)
fi

# rate_limits
five_pct=$(printf '%s' "$input" | grep -oE '"five_hour"[^}]*' | grep -oE '"used_percentage"[[:space:]]*:[[:space:]]*[0-9.]+' | grep -oE '[0-9.]+$')
five_reset=$(printf '%s' "$input" | grep -oE '"five_hour"[^}]*' | grep -oE '"resets_at"[[:space:]]*:[[:space:]]*[0-9.]+' | grep -oE '[0-9.]+$')
five_pct=$(int_part "$five_pct")
five_reset=$(int_part "$five_reset")

seven_pct=$(printf '%s' "$input" | grep -oE '"seven_day"[^}]*' | grep -oE '"used_percentage"[[:space:]]*:[[:space:]]*[0-9.]+' | grep -oE '[0-9.]+$')
seven_pct=$(int_part "$seven_pct")

total_tokens=$((input_tokens + output_tokens))

# --- formatting helpers ---
format_tokens() {
  local t=$1
  if [ "$t" -ge 1000000 ]; then
    printf '%s.%sM' "$((t / 1000000))" "$(( (t % 1000000) / 100000 ))"
  elif [ "$t" -ge 1000 ]; then
    printf '%sK' "$((t / 1000))"
  else
    printf '%s' "$t"
  fi
}

format_ctx_size() {
  local t=$1
  if [ "$t" -ge 1000000 ]; then
    printf '%sM' "$((t / 1000000))"
  elif [ "$t" -ge 1000 ]; then
    printf '%sK' "$((t / 1000))"
  else
    printf '%s' "$t"
  fi
}

make_bar() {
  local pct=$1 width=${2:-10}
  local filled=$(( pct * width / 100 ))
  [ "$filled" -gt "$width" ] && filled=$width
  local empty=$(( width - filled ))
  local bar="" i=0
  while [ "$i" -lt "$filled" ]; do bar="${bar}█"; i=$((i+1)); done
  i=0
  while [ "$i" -lt "$empty" ]; do bar="${bar}░"; i=$((i+1)); done
  printf '%s' "$bar"
}

# used color: high = red (bad)
pct_color() {
  local pct=$1
  if [ "$pct" -ge 80 ]; then printf '%s' "$RED"
  elif [ "$pct" -ge 50 ]; then printf '%s' "$YELLOW"
  else printf '%s' "$GREEN"
  fi
}

# remaining color: low = red (bad)
health_color() {
  local h=$1
  if [ "$h" -le 30 ]; then printf '%s' "$RED"
  elif [ "$h" -le 60 ]; then printf '%s' "$YELLOW"
  else printf '%s' "$GREEN"
  fi
}

# reasoning effort color: informational (high = deeper thinking, not a warning)
effort_color() {
  case "$1" in
    high)        printf '%s' "$MAGENTA" ;;
    medium|med)  printf '%s' "$BLUE" ;;
    low)         printf '%s' "$GREEN" ;;
    *)           printf '%s' "$DIM" ;;
  esac
}

# --- computed metrics ---

# session elapsed time
duration_sec=$(( ${duration_ms%.*} / 1000 ))
dur_min=$((duration_sec / 60))
dur_sec=$((duration_sec % 60))
if [ "$dur_min" -ge 60 ]; then
  dur_h=$((dur_min / 60))
  dur_m=$((dur_min % 60))
  dur_display="${dur_h}h${dur_m}m"
else
  dur_display="${dur_min}m${dur_sec}s"
fi

# 5h reset remaining
five_remain_display=""
if [ "$five_reset" -gt 0 ]; then
  now=$(date +%s)
  diff=$((five_reset - now))
  if [ "$diff" -gt 0 ]; then
    rh=$((diff / 3600))
    rm=$(( (diff % 3600) / 60 ))
    five_remain_display="${rh}h${rm}m"
  fi
fi

# git branch + commit hash
git_branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
[ -z "$git_branch" ] && git_branch="-"
git_hash=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
[ -z "$git_hash" ] && git_hash="-"

# cache hit rate
cache_total=$((cache_read + cache_create))
if [ "$cache_total" -gt 0 ]; then
  cache_pct=$((cache_read * 100 / cache_total))
else
  cache_pct=0
fi

# remaining percentages
ctx_remain=$((100 - ctx_pct))
five_remain=$((100 - five_pct))
seven_remain=$((100 - seven_pct))

# cost formatting
cost_fmt=$(printf '%.2f' "$cost_usd")

# --- subagent + task counts (session-scoped, from filesystem stores) ---
task_done=0
task_total=0
sub_count=0
if [ -n "$session_id" ]; then
  # base dir holding todos/ and tasks/ (default ~/.claude)
  cfg_base="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  [ -d "$cfg_base/todos" ] || [ -d "$cfg_base/tasks" ] || cfg_base="$HOME/.claude"

  # tasks: prefer the Task system (one json file per task), else main-agent TodoWrite
  task_dir="$cfg_base/tasks/$session_id"
  if [ -d "$task_dir" ]; then
    for tf in "$task_dir"/*.json; do
      [ -f "$tf" ] || continue
      task_total=$((task_total + 1))
      grep -q '"status"[[:space:]]*:[[:space:]]*"completed"' "$tf" 2>/dev/null && task_done=$((task_done + 1))
    done
  fi
  if [ "$task_total" -eq 0 ]; then
    todo_main="$cfg_base/todos/${session_id}-agent-${session_id}.json"
    if [ -f "$todo_main" ]; then
      task_total=$(grep -oE '"status"[[:space:]]*:[[:space:]]*"[a-z_]+"' "$todo_main" 2>/dev/null | wc -l | tr -d ' ')
      task_done=$(grep -oE '"status"[[:space:]]*:[[:space:]]*"completed"' "$todo_main" 2>/dev/null | wc -l | tr -d ' ')
    fi
  fi

  # subagents: this session's subagent TodoWrite files (agent id != session id)
  for af in "$cfg_base"/todos/"${session_id}"-agent-*.json; do
    [ -f "$af" ] || continue
    ab=$(basename "$af" .json)
    ag=${ab##*-agent-}
    [ "$ag" != "$session_id" ] && sub_count=$((sub_count + 1))
  done
fi

# --- compose LINE 1: model + in/out tokens + total/ctx + cost ---
in_display=$(format_tokens "$input_tokens")
out_display=$(format_tokens "$output_tokens")
tk_display=$(format_tokens "$total_tokens")
ctx_display=$(format_ctx_size "$ctx_size")

# reasoning effort segment (shown right after model, only if present)
effort_seg=""
if [ -n "$effort_level" ]; then
  effort_seg=" ${DIM}🧠${RST}$(effort_color "$effort_level")${effort_level}${RST}"
fi

L1=""
L1="${L1}${BOLD}${CYAN}${model_short}${RST}${effort_seg}"
L1="${L1}${SEP}"
L1="${L1}${DIM}In:${RST}${WHITE}${in_display}${RST} ${DIM}Out:${RST}${WHITE}${out_display}${RST}"
L1="${L1}${SEP}"
L1="${L1}${WHITE}${tk_display}/${ctx_display}${RST}"
L1="${L1}${SEP}"
L1="${L1}💰 ${BOLD}${YELLOW}\$${cost_fmt}${RST}"

# account segment (appended to line 2; only if an account was found)
account_seg=""
if [ -n "$account_email" ]; then
  acct_disp="$account_email"
  [ "$MASK_ACCOUNT" = "1" ] && acct_disp=$(mask_email "$account_email")
  tc_marker=""
  [ -n "$ACCOUNT_VIA_PROXY" ] && tc_marker=" ${DIM}⇄${ACCOUNT_VIA_PROXY}${RST}"
  account_seg="${SEP}👤 ${WHITE}${acct_disp}${RST}${tc_marker}"
fi

# task progress segment (only if this session has any task/todo)
task_seg=""
if [ "$task_total" -gt 0 ]; then
  if [ "$task_done" -ge "$task_total" ]; then task_col="$GREEN"; else task_col="$YELLOW"; fi
  task_seg="${SEP}${task_col}✓${task_done}/${task_total}${RST}"
fi

# subagent count segment (only if any subagent ran this session)
sub_seg=""
[ "$sub_count" -gt 0 ] && sub_seg="${SEP}${CYAN}🤖${sub_count}${RST}"

# --- compose LINE 2: project + git + session time + changes + tasks + subagents + account ---
L2=""
L2="${L2}${BLUE}${project_name}${RST}"
L2="${L2}${SEP}"
L2="${L2}${YELLOW}${git_branch}${RST} ${DIM}${git_hash}${RST}"
L2="${L2}${SEP}"
L2="${L2}${MAGENTA}⏱ ${dur_display}${RST}"
L2="${L2}${SEP}"
L2="${L2}${GREEN}+${lines_added}${RST} ${RED}-${lines_removed}${RST}"
L2="${L2}${task_seg}${sub_seg}"
L2="${L2}${account_seg}"

# peer-name segment; for a derived name the tail that tells sibling sessions
# apart ("ea" in "my-laptop-ea") is bold
peer_seg=""
if [ -n "$peer_name" ]; then
  # split before truncating so a long folder prefix never cuts the tail off
  if [ "$peer_source" = "derived" ] && [ "${peer_name%-*}" != "$peer_name" ]; then
    peer_seg="🏷 ${DIM}$(truncate_str "${peer_name%-*}" 28)-${RST}${BOLD}${YELLOW}$(truncate_str "${peer_name##*-}" 8)${RST}"
  else
    peer_seg="🏷 ${BOLD}${YELLOW}$(truncate_str "$peer_name" 32)${RST}"
  fi
fi
# a /rename'd session carries the same text as name and title: show it once
[ -n "$peer_name" ] && [ "$task_title" = "$peer_name" ] && task_title=""

# --- compose task line: 🏷 peer name │ 📋 session title │ ▶ current work │ ✎ edited repos ---
LT=""
if [ -n "$peer_seg" ] || [ -n "$task_title" ] || [ -n "$task_now" ] || [ -n "$task_repos" ]; then
  LT="$peer_seg"
  if [ -n "$task_title" ]; then
    [ -n "$LT" ] && LT="${LT}${SEP}"
    LT="${LT}📋 ${WHITE}$(truncate_str "$task_title" 40)${RST}"
  fi
  if [ -n "$task_now" ]; then
    [ -n "$LT" ] && LT="${LT}${SEP}"
    LT="${LT}${GREEN}▶${RST} ${WHITE}$(truncate_str "$task_now" 40)${RST}"
  fi
  if [ -n "$task_repos" ]; then
    [ -n "$LT" ] && LT="${LT}${SEP}"
    LT="${LT}${MAGENTA}✎ ${task_repos}${RST}"
  fi
fi

# --- compose LINE 3: metrics bars (used or left) ---
L3=""
if [ "$VIEW" = "left" ]; then
  # remaining capacity view
  ctx_v=$ctx_remain; five_v=$five_remain; seven_v=$seven_remain
  ctx_vc=$(health_color "$ctx_v")
  five_vc=$(health_color "$five_v")
  seven_vc=$(health_color "$seven_v")
  ctx_label="ctx left"; five_label="5h left"; seven_label="7d left"
else
  # used view (default)
  ctx_v=$ctx_pct; five_v=$five_pct; seven_v=$seven_pct
  ctx_vc=$(pct_color "$ctx_v")
  five_vc=$(pct_color "$five_v")
  seven_vc=$(pct_color "$seven_v")
  ctx_label="ctx"; five_label="5h"; seven_label="7d"
fi

ctx_v_bar=$(make_bar "$ctx_v" 8)
five_v_bar=$(make_bar "$five_v" 8)
seven_v_bar=$(make_bar "$seven_v" 8)

L3="${L3}${DIM}${ctx_label}${RST} ${ctx_vc}${ctx_v_bar} ${ctx_v}%${RST}"
L3="${L3}${SEP}"
L3="${L3}${DIM}${five_label}${RST} ${five_vc}${five_v_bar} ${five_v}%${RST}"
[ -n "$five_remain_display" ] && L3="${L3}${DIM}(${five_remain_display})${RST}"
L3="${L3}${SEP}"
L3="${L3}${DIM}${seven_label}${RST} ${seven_vc}${seven_v_bar} ${seven_v}%${RST}"
L3="${L3}${SEP}"
L3="${L3}📦 ${GREEN}${cache_pct}%${RST}"

# --- output ---
if [ "$MODE" = "lite" ]; then
  LITE=""
  [ -n "$peer_seg" ] && LITE="${peer_seg}${SEP}"
  LITE="${LITE}${BLUE}${project_name}${RST}"
  LITE="${LITE}${SEP}"
  LITE="${LITE}${YELLOW}${git_branch}${RST}"
  LITE="${LITE}${SEP}"
  LITE="${LITE}${BOLD}${CYAN}${model_short}${RST}${effort_seg}"
  LITE="${LITE}${SEP}"
  if [ "$VIEW" = "left" ]; then
    LITE="${LITE}${DIM}5h left${RST} ${five_vc}${five_v_bar} ${five_v}%${RST}"
    LITE="${LITE}${SEP}"
    LITE="${LITE}${DIM}7d left${RST} ${seven_vc}${seven_v_bar} ${seven_v}%${RST}"
  else
    LITE="${LITE}${DIM}5h${RST} ${five_vc}${five_v_bar} ${five_v}%${RST}"
    LITE="${LITE}${SEP}"
    LITE="${LITE}${DIM}7d${RST} ${seven_vc}${seven_v_bar} ${seven_v}%${RST}"
  fi
  printf '%s' "$LITE"
else
  if [ -n "$LT" ]; then
    printf '%s\n%s\n%s\n%s' "$L1" "$L2" "$LT" "$L3"
  else
    printf '%s\n%s\n%s' "$L1" "$L2" "$L3"
  fi
fi
