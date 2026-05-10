# claude-statusline

A 3-line status bar for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI.

```
Opus 4.6 │ ██████░░░░ 58% │ 234K/200K │ 💰 $1.23
📁 my-project │ main a1b2c3d │ 12m30s │ ⏳ ~3h42m │ +45 -12
ctx ████████ 42% │ 5h ██████░░ 72% │ 7d █████░░░ 65% │ 📦 89%
```

## What it shows / 표시 항목

**Line 1** — Model, context usage bar, token count, session cost
- 모델명, 컨텍스트 사용량 바, 토큰 수, 세션 비용

**Line 2** — Project folder, git branch + hash, session duration, 5h reset timer, lines changed
- 프로젝트 폴더, git 브랜치 + 커밋 해시, 세션 경과 시간, 5시간 리셋 타이머, 변경 줄 수

**Line 3** — Remaining capacity bars (context window, 5-hour rate limit, 7-day rate limit), prompt cache hit rate
- 남은 용량 바 (컨텍스트 윈도우, 5시간 제한, 7일 제한), 프롬프트 캐시 적중률

### Color coding / 색상 의미

- 🟢 Green / 초록: 여유 (60% 이상 남음)
- 🟡 Yellow / 노랑: 주의 (30~60% 남음)
- 🔴 Red / 빨강: 부족 (30% 미만 남음)

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/gencrewai/aiops/main/install.sh | bash
```

This downloads `statusline.sh` to `~/.claude/` and adds the `statusLine` config to your `settings.json`.

Restart Claude Code after installing.

### Manual install

1. Download `statusline.sh` to `~/.claude/statusline.sh`
2. Add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash \"~/.claude/statusline.sh\""
  }
}
```

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/gencrewai/aiops/main/uninstall.sh | bash
```

## Requirements

- Claude Code CLI (with `statusLine` support)
- bash, git, sed, grep

## How it works

Claude Code pipes a JSON object with session metrics to the `statusLine` command's stdin on each turn. This script parses the JSON and renders a colored 3-line display using ANSI escape codes.

Available fields in the JSON input:
- `display_name`, `context_window_size`, `used_percentage`
- `total_input_tokens`, `total_output_tokens`, `total_cost_usd`
- `total_duration_ms`, `total_lines_added`, `total_lines_removed`
- `cache_read_input_tokens`, `cache_creation_input_tokens`
- `rate_limits.five_hour.used_percentage`, `rate_limits.seven_day.used_percentage`
- `current_dir`

## License

MIT
