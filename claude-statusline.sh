#!/usr/bin/env bash
# Claude Code statusLine — 3-line or 1-line status bar
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

duration_ms=$(int_part "$(num_field "total_duration_ms")")
lines_added=$(int_part "$(num_field "total_lines_added")")
lines_removed=$(int_part "$(num_field "total_lines_removed")")

cache_read=$(int_part "$(num_field "cache_read_input_tokens")")
cache_create=$(int_part "$(num_field "cache_creation_input_tokens")")

cwd=$(str_field "current_dir")
[ -z "$cwd" ] && cwd=$(str_field "cwd")
project_name=$(basename "$cwd" 2>/dev/null)
[ -z "$project_name" ] && project_name="?"

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
  printf '%s\n%s\n%s' "$L1" "$L2" "$L3"
fi
