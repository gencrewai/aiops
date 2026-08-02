#!/usr/bin/env bash
# Claude Code statusLine — 3/4-line or 1-line status bar
# The task-context line (📋 session title │ ▶ current work │ ✎ edited repos)
# appears automatically when transcript/session data is available.
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
mask_email() {
  local e="$1" lp dom
  case "$e" in
    *@*) lp="${e%%@*}"; dom="${e#*@}"; printf '%s***@%s' "${lp:0:2}" "$dom" ;;
    *)   printf '%s' "$e" ;;
  esac
}

# --- task-context helpers (session title / current work / edited repos) ---
# minimal JSON string unescape for display, then control-char sanitize
decode_json_str() {
  sed -E 's/\\[nrt]/ /g; s/\\"/"/g; s/\\\\/\\/g' | sanitize_name
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
# No-op once the payload reports >= 1M (forward-compatible with an upstream fix).
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
#   origin remote "owner/repo" shown in front of the folder name; the folder
#   part is omitted when it equals the repo name (avoids "repo/repo" at the
#   checkout root). Without a usable origin, fall back to the main-repo-root
#   basename prefix (worktree/subdir only, as before). Outside git the plain
#   folder name remains.
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

# --- task context: session title / current work / repos edited this session ---
transcript_path=$(str_field "transcript_path")
session_id=$(str_field "session_id")

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

task_title=$(str_field "session_name" | decode_json_str)
task_now=""
task_repos=""

if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
  t_tail=$(tail -c 65536 "$transcript_path" 2>/dev/null)

  # session title: explicit session_name → latest auto ai-title → first user prompt
  [ -z "$task_title" ] && task_title=$(printf '%s' "$t_tail" | json_field_last "aiTitle")
  if [ -z "$task_title" ]; then
    # -m1: stop at the first user entry — streaming, no byte-boundary cut on multibyte text
    first_user_line=$(grep -m1 '"type":"user"' "$transcript_path" 2>/dev/null)
    task_title=$(printf '%s' "$first_user_line" | json_field_first "content")
    # array-form message content: fall back to its first text block
    [ -z "$task_title" ] && task_title=$(printf '%s' "$first_user_line" | json_field_first "text")
  fi

  # current work: in-progress task (~/.claude/tasks) → todo (~/.claude/todos) → latest prompt
  if [ -n "$session_id" ]; then
    task_dir="$HOME/.claude/tasks/$session_id"
    if [ -d "$task_dir" ]; then
      while IFS= read -r tf; do
        [ -f "$tf" ] || continue
        flat=$(tr -d '\n' < "$tf" 2>/dev/null)
        printf '%s' "$flat" | grep -qE '"status"[[:space:]]*:[[:space:]]*"in_progress"' || continue
        task_now=$(printf '%s' "$flat" | json_field_first "activeForm")
        [ -z "$task_now" ] && task_now=$(printf '%s' "$flat" | json_field_first "subject")
        [ -n "$task_now" ] && break
      done <<EOF_TASKS
$(ls -t "$task_dir"/*.json 2>/dev/null)
EOF_TASKS
    fi
    if [ -z "$task_now" ]; then
      for tf in "$HOME/.claude/todos/$session_id"*.json; do
        [ -f "$tf" ] || continue
        todo_obj=$(tr -d '\n' < "$tf" 2>/dev/null | grep -oE '\{[^{}]*"in_progress"[^{}]*\}' | tail -n1)
        [ -n "$todo_obj" ] || continue
        task_now=$(printf '%s' "$todo_obj" | json_field_first "activeForm")
        [ -z "$task_now" ] && task_now=$(printf '%s' "$todo_obj" | json_field_first "content")
        [ -n "$task_now" ] && break
      done
    fi
  fi
  [ -z "$task_now" ] && task_now=$(printf '%s' "$t_tail" | json_field_last "lastPrompt")

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

account_email=$(get_account)

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
  account_seg="${SEP}👤 ${WHITE}${acct_disp}${RST}"
fi

# --- compose LINE 2: project + git + session time + changes + account ---
L2=""
L2="${L2}${BLUE}${project_name}${RST}"
L2="${L2}${SEP}"
L2="${L2}${YELLOW}${git_branch}${RST} ${DIM}${git_hash}${RST}"
L2="${L2}${SEP}"
L2="${L2}${MAGENTA}⏱ ${dur_display}${RST}"
L2="${L2}${SEP}"
L2="${L2}${GREEN}+${lines_added}${RST} ${RED}-${lines_removed}${RST}"
L2="${L2}${account_seg}"

# --- compose task line: 📋 session title │ ▶ current work │ ✎ edited repos ---
LT=""
if [ -n "$task_title" ] || [ -n "$task_now" ] || [ -n "$task_repos" ]; then
  [ -n "$task_title" ] && LT="📋 ${WHITE}$(truncate_str "$task_title" 40)${RST}"
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
