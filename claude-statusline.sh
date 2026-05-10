#!/usr/bin/env bash
# Claude Code statusLine — 3-line or 1-line status bar
# Usage: bash statusline.sh          → 3-line (default)
#        bash statusline.sh lite     → 1-line
# https://github.com/gencrewai/aiops
set -u
MODE="${1:-full}"
input=$(cat)

# --- color constants (use $'...' for real ESC) ---
RST=$'\033[0m'
CYAN=$'\033[36m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
DIM=$'\033[2m'
BOLD=$'\033[1m'
WHITE=$'\033[37m'
MAGENTA=$'\033[35m'
BLUE=$'\033[34m'

SEP=" ${DIM}│${RST} "

# --- extract helpers ---
str_field() {
  printf '%s' "$input" | grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -n1 | sed -E 's/.*"([^"]*)"\s*$/\1/'
}
num_field() {
  printf '%s' "$input" | grep -oE "\"$1\"[[:space:]]*:[[:space:]]*[0-9.]+" | head -n1 | grep -oE '[0-9.]+$'
}

# --- data extraction ---
model_name=$(str_field "display_name")
[ -z "$model_name" ] && model_name="Claude"
model_short=$(printf '%s' "$model_name" | sed -E 's/^Claude //')

input_tokens=$(num_field "total_input_tokens");  [ -z "$input_tokens" ] && input_tokens=0
output_tokens=$(num_field "total_output_tokens"); [ -z "$output_tokens" ] && output_tokens=0
ctx_size=$(num_field "context_window_size");      [ -z "$ctx_size" ] && ctx_size=200000
ctx_pct=$(num_field "used_percentage");           [ -z "$ctx_pct" ] && ctx_pct=0
cost_usd=$(num_field "total_cost_usd");           [ -z "$cost_usd" ] && cost_usd="0"

duration_ms=$(num_field "total_duration_ms");     [ -z "$duration_ms" ] && duration_ms=0
lines_added=$(num_field "total_lines_added");     [ -z "$lines_added" ] && lines_added=0
lines_removed=$(num_field "total_lines_removed"); [ -z "$lines_removed" ] && lines_removed=0

cache_read=$(num_field "cache_read_input_tokens");     [ -z "$cache_read" ] && cache_read=0
cache_create=$(num_field "cache_creation_input_tokens"); [ -z "$cache_create" ] && cache_create=0

cwd=$(str_field "current_dir")
[ -z "$cwd" ] && cwd=$(str_field "cwd")
project_name=$(basename "$cwd" 2>/dev/null)
[ -z "$project_name" ] && project_name="?"

# rate_limits
five_pct=$(printf '%s' "$input" | grep -oE '"five_hour"[^}]*' | grep -oE '"used_percentage"[[:space:]]*:[[:space:]]*[0-9]+' | grep -oE '[0-9]+$')
five_reset=$(printf '%s' "$input" | grep -oE '"five_hour"[^}]*' | grep -oE '"resets_at"[[:space:]]*:[[:space:]]*[0-9]+' | grep -oE '[0-9]+$')
[ -z "$five_pct" ] && five_pct=0
[ -z "$five_reset" ] && five_reset=0

seven_pct=$(printf '%s' "$input" | grep -oE '"seven_day"[^}]*' | grep -oE '"used_percentage"[[:space:]]*:[[:space:]]*[0-9]+' | grep -oE '[0-9]+$')
[ -z "$seven_pct" ] && seven_pct=0

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

pct_color() {
  local pct=$1
  if [ "$pct" -ge 80 ]; then printf '%s' "$RED"
  elif [ "$pct" -ge 50 ]; then printf '%s' "$YELLOW"
  else printf '%s' "$GREEN"
  fi
}

health_color() {
  local h=$1
  if [ "$h" -le 30 ]; then printf '%s' "$RED"
  elif [ "$h" -le 60 ]; then printf '%s' "$YELLOW"
  else printf '%s' "$GREEN"
  fi
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

# --- compose LINE 1: model + context + cost ---
ctx_color=$(pct_color "$ctx_pct")
ctx_bar=$(make_bar "$ctx_pct" 10)
tk_display=$(format_tokens "$total_tokens")
ctx_display=$(format_ctx_size "$ctx_size")

L1=""
L1="${L1}${BOLD}${CYAN}${model_short}${RST}"
L1="${L1}${SEP}"
L1="${L1}${ctx_color}${ctx_bar}${RST} ${ctx_color}${ctx_pct}%${RST}"
L1="${L1}${SEP}"
L1="${L1}${WHITE}${tk_display}/${ctx_display}${RST}"
L1="${L1}${SEP}"
L1="${L1}💰 ${BOLD}${YELLOW}\$${cost_fmt}${RST}"

# --- compose LINE 2: project + git + session time + changes ---
L2=""
L2="${L2}📁 ${BLUE}${project_name}${RST}"
L2="${L2}${SEP}"
L2="${L2}${YELLOW}${git_branch}${RST} ${DIM}${git_hash}${RST}"
L2="${L2}${SEP}"
L2="${L2}${MAGENTA}${dur_display}${RST}"
if [ -n "$five_remain_display" ]; then
  L2="${L2}${SEP}"
  L2="${L2}⏳ ${DIM}~${five_remain_display}${RST}"
fi
L2="${L2}${SEP}"
L2="${L2}${GREEN}+${lines_added}${RST} ${RED}-${lines_removed}${RST}"

# --- compose LINE 3: context remain + rate limits + cache ---
ctx_remain_bar=$(make_bar "$ctx_remain" 8)
five_remain_bar=$(make_bar "$five_remain" 8)
seven_remain_bar=$(make_bar "$seven_remain" 8)
ctx_remain_color=$(health_color "$ctx_remain")
five_remain_color=$(health_color "$five_remain")
seven_remain_color=$(health_color "$seven_remain")

L3=""
L3="${L3}${DIM}ctx${RST} ${ctx_remain_color}${ctx_remain_bar} ${ctx_remain}%${RST}"
L3="${L3}${SEP}"
L3="${L3}${DIM}5h${RST} ${five_remain_color}${five_remain_bar} ${five_remain}%${RST}"
[ -n "$five_remain_display" ] && L3="${L3}${DIM}(${five_remain_display})${RST}"
L3="${L3}${SEP}"
L3="${L3}${DIM}7d${RST} ${seven_remain_color}${seven_remain_bar} ${seven_remain}%${RST}"
L3="${L3}${SEP}"
L3="${L3}📦 ${GREEN}${cache_pct}%${RST}"

# --- output ---
if [ "$MODE" = "lite" ]; then
  # 1-line: folder │ branch │ model │ 5h remain │ 7d remain
  LITE=""
  LITE="${LITE}📁 ${BLUE}${project_name}${RST}"
  LITE="${LITE}${SEP}"
  LITE="${LITE}${YELLOW}${git_branch}${RST}"
  LITE="${LITE}${SEP}"
  LITE="${LITE}${BOLD}${CYAN}${model_short}${RST}"
  LITE="${LITE}${SEP}"
  LITE="${LITE}${DIM}5h${RST} ${five_remain_color}${five_remain_bar} ${five_remain}%${RST}"
  LITE="${LITE}${SEP}"
  LITE="${LITE}${DIM}7d${RST} ${seven_remain_color}${seven_remain_bar} ${seven_remain}%${RST}"
  printf '%s' "$LITE"
else
  printf '%s\n%s\n%s' "$L1" "$L2" "$L3"
fi
