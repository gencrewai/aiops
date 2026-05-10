# aiops — CLI Status Bars

Status bars for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and [Codex CLI](https://github.com/openai/codex).

## Claude Code — status bar (full / lite)

Two modes available:

### Full mode (3-line, default)

```
Opus 4.6 │ ██████░░░░ 58% │ 234K/200K │ 💰 $1.23
📁 my-project │ main a1b2c3d │ 12m30s │ ⏳ ~3h42m │ +45 -12
ctx ████████ 42% │ 5h ██████░░ 72% │ 7d █████░░░ 65% │ 📦 89%
```

**Line 1** — Model, context usage bar, token count, session cost
**Line 2** — Project folder, git branch + hash, session duration, 5h reset timer, lines changed
**Line 3** — Remaining capacity bars (context, 5h, 7d), prompt cache hit rate

### Lite mode (1-line)

```
📁 my-project │ main │ Opus 4.6 │ 5h ██████░░ 72% │ 7d █████░░░ 65%
```

Folder, branch, model, 5-hour remaining, 7-day remaining — the essentials.

### Color coding / 색상 의미

- 🟢 Green / 초록: 여유 (60% 이상 남음)
- 🟡 Yellow / 노랑: 주의 (30~60% 남음)
- 🔴 Red / 빨강: 부족 (30% 미만 남음)

### Install

```bash
# Full mode (3-line, default)
curl -fsSL https://raw.githubusercontent.com/gencrewai/aiops/main/install.sh | bash

# Lite mode (1-line)
curl -fsSL https://raw.githubusercontent.com/gencrewai/aiops/main/install.sh | bash -s -- lite
```

Downloads `claude-statusline.sh` to `~/.claude/` and adds the `statusLine` config to your `settings.json`.

Restart Claude Code after installing. Re-run with the other mode to switch.

#### Manual install

1. Download `claude-statusline.sh` to `~/.claude/claude-statusline.sh`
2. Add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash \"~/.claude/claude-statusline.sh\""
  }
}
```

For lite mode, append `lite`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash \"~/.claude/claude-statusline.sh\" lite"
  }
}
```

### Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/gencrewai/aiops/main/uninstall.sh | bash
```

### How it works

Claude Code pipes a JSON object with session metrics to the `statusLine` command's stdin on each turn. The script parses the JSON and renders colored output using ANSI escape codes.

Available fields in the JSON input:
- `display_name`, `context_window_size`, `used_percentage`
- `total_input_tokens`, `total_output_tokens`, `total_cost_usd`
- `total_duration_ms`, `total_lines_added`, `total_lines_removed`
- `cache_read_input_tokens`, `cache_creation_input_tokens`
- `rate_limits.five_hour.used_percentage`, `rate_limits.seven_day.used_percentage`
- `current_dir`

---

## Codex CLI — native status line

Configures Codex CLI's built-in status line with optimal items.
Codex CLI의 내장 status line을 최적 항목으로 구성합니다.

```
~/my-project │ main │ o4-mini (high) │ 7d: 12%
```

### What it shows / 표시 항목

| Item | Description / 설명 |
|------|-------------------|
| `current-dir` | Working directory / 작업 디렉토리 |
| `git-branch` | Current git branch / 현재 git 브랜치 |
| `model-with-reasoning` | Model name + reasoning level / 모델명 + 추론 수준 |
| `weekly-limit` | Weekly rate limit / 주간 사용 제한 |

### Install

```bash
curl -fsSL https://raw.githubusercontent.com/gencrewai/aiops/main/codex-install.sh | bash
```

This adds `tui.status_line` config to your `~/.codex/config.toml`.

Restart Codex CLI after installing.

#### Manual install

Add to `~/.codex/config.toml`:

```toml
[tui]
status_line = ["current-dir", "git-branch", "model-with-reasoning", "weekly-limit"]
status_line_use_colors = true
```

#### Customize interactively

Inside Codex CLI, run `/statusline` to toggle and reorder items.

### Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/gencrewai/aiops/main/codex-uninstall.sh | bash
```

---

## Requirements

- **Claude Code**: Claude Code CLI (with `statusLine` support), bash, git, sed, grep
- **Codex CLI**: Codex CLI v0.1+ (with `/statusline` support)

## License

MIT
