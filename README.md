# claude-statusline

A 3-line status bar for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI.

```
Opus 4.6 │ ██████░░░░ 58% │ 234K/200K │ 💰 $1.23
📁 my-project │ main a1b2c3d │ 12m30s │ ⏳ ~3h42m │ +45 -12
ctx ████████ 42% │ 5h ██████░░ 72% │ 7d █████░░░ 65% │ 📦 89%
```

## What it shows

**Line 1** — Model, context usage bar, token count, session cost

**Line 2** — Project folder, git branch + hash, session duration, 5h reset timer, lines changed

**Line 3** — Remaining capacity bars (context window, 5-hour rate limit, 7-day rate limit), prompt cache hit rate

### Color coding

- Green: plenty of room (>60% remaining)
- Yellow: getting used (30-60% remaining)
- Red: running low (<30% remaining)

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
