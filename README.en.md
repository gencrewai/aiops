[한국어](./README.md)

# aiops - CLI Status Bars

Status bars for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and [Codex CLI](https://github.com/openai/codex).

---

## Claude Code - Status Bar (full / lite)

Two modes and optional flags are available.

| Option | Description |
|--------|-------------|
| (default) | Full mode (3-line), used bars |
| `lite` | Lite mode (1-line) |
| `--left` | Switch to remaining capacity bars |
| `--soft` | Pastel ice-cream colors |

Options can be combined freely: `lite --left --soft`

### Full Mode (3-line, default)

```text
Opus 4.6 │ In:180K Out:54K │ 234K/200K │ $1.23
my-project │ main a1b2c3d │ ⏱ 12m30s │ +45 -12
ctx █████░░░ 58% │ 5h █████░░░ 72%(3h42m) │ 7d █████░░░ 65% │ cache 89%
```

- `Line 1`: Model, input/output tokens, total tokens/context size, session cost
- `Line 2`: Project folder, git branch + commit hash, session duration, lines changed
- `Line 3`: Usage bars (`ctx`, `5h`, `7d`), 5h reset remaining time, prompt cache hit rate

With `--left` flag, Line 3 switches to remaining capacity:

```text
ctx left ███░░░░░ 42% │ 5h left ██░░░░░░ 28%(3h42m) │ 7d left ██░░░░░░ 35% │ cache 89%
```

### Lite Mode (1-line)

```text
my-project │ main │ Opus 4.6 │ 5h █████░░░ 72% │ 7d █████░░░ 65%
```

Folder, branch, model, 5-hour and 7-day usage only. Use `--left` to show remaining capacity instead.

### --soft (Pastel Colors)

Add the `--soft` flag for ice-cream pastel tone colors. Requires a truecolor (24-bit) terminal.

```text
Opus 4.6 · In:180K Out:54K · 234K/200K · $1.23
my-project · main a1b2c3d · ⏱ 12m30s · +45 -12
ctx █████░░░ 58% · 5h █████░░░ 72%(3h42m) · 7d █████░░░ 65% · cache 89%
```

The separator changes from `│` to `·` and colors become pastel tones.

### Color Coding

| Color | used (default) | --left |
|:---:|---------|---------|
| Green | Low usage | Plenty remaining |
| Yellow | Caution zone | Caution zone |
| Red | High usage, near limit | Low remaining |

### Install

```bash
# macOS / Linux / Git Bash - Full mode (3-line, default)
curl -fsSL https://raw.githubusercontent.com/gencrewai/aiops/main/install.sh | bash

# macOS / Linux / Git Bash - Lite mode (1-line)
curl -fsSL https://raw.githubusercontent.com/gencrewai/aiops/main/install.sh | bash -s -- lite
```

```powershell
# Windows PowerShell - Full mode (3-line, default)
$script = Join-Path $env:TEMP 'aiops-install.ps1'
Invoke-WebRequest https://raw.githubusercontent.com/gencrewai/aiops/main/install.ps1 -OutFile $script
powershell -NoProfile -ExecutionPolicy Bypass -File $script

# Windows PowerShell - Lite mode (1-line)
powershell -NoProfile -ExecutionPolicy Bypass -File $script -Mode lite
```

Downloads the platform-specific status line script to `~/.claude/` and adds the `statusLine` config to your `settings.json`.

Restart Claude Code after installing. Re-run with the other mode to switch.

#### Manual Install

**macOS / Linux / Git Bash:**

1. Download `claude-statusline.sh` to `~/.claude/claude-statusline.sh`
2. Add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/claude-statusline.sh"
  }
}
```

Combine options freely:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/claude-statusline.sh lite --left --soft"
  }
}
```

**Windows PowerShell:**

1. Download `claude-statusline.ps1` to `~/.claude/claude-statusline.ps1`
2. Add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "powershell -NoProfile -ExecutionPolicy Bypass -File C:/Users/username/.claude/claude-statusline.ps1"
  }
}
```

Combine options freely:

```json
{
  "statusLine": {
    "type": "command",
    "command": "powershell -NoProfile -ExecutionPolicy Bypass -File C:/Users/username/.claude/claude-statusline.ps1 lite --left --soft"
  }
}
```

### Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/gencrewai/aiops/main/uninstall.sh | bash
```

```powershell
$script = Join-Path $env:TEMP 'aiops-uninstall.ps1'
Invoke-WebRequest https://raw.githubusercontent.com/gencrewai/aiops/main/uninstall.ps1 -OutFile $script
powershell -NoProfile -ExecutionPolicy Bypass -File $script
```

### How It Works

Claude Code pipes a JSON object with session metrics to the `statusLine` command's stdin on each turn. The script parses the JSON and renders colored output using ANSI escape codes.

Available fields in the JSON input:

- `model.display_name`, `context_window.context_window_size`, `context_window.used_percentage`
- `context_window.total_input_tokens`, `context_window.total_output_tokens`, `cost.total_cost_usd`
- `cost.total_duration_ms`, `cost.total_lines_added`, `cost.total_lines_removed`
- `cache_read_input_tokens`, `cache_creation_input_tokens`
- `rate_limits.five_hour.used_percentage`, `rate_limits.seven_day.used_percentage`
- `workspace.current_dir`, `cwd`

### Troubleshooting

- Claude Code user/project trust must be accepted or the `statusLine` command will be skipped.
- If `disableAllHooks` is `true`, the status line is disabled too.
- Existing `~/.claude/settings.json` must be valid JSON. Older installers that appended text directly could break one-line JSON files.
- Do not use `bash "~/.claude/claude-statusline.sh"`. The quoted `~` does not expand to your home directory, so Claude Code may fail to find the script.
- If you installed an older version, re-run the installer once to rewrite `statusLine.command` to the fixed format for your environment.
- Newer builds label context usage as `ctx used` and remaining capacity as `left` so `used %` and `remaining %` are not mixed visually.
- The status script expects numeric percentages and now truncates decimal values before doing bash arithmetic.
- On Windows without Git Bash, use `install.ps1` and `claude-statusline.ps1`. A bash-only install will not run on a pure PowerShell machine.

---

## Codex CLI - Native Status Line

Configures Codex CLI's built-in status line with practical default items.

```text
~/my-project | main | o4-mini (high) | 7d: 12%
```

### What It Shows

| Item | Description |
|------|-------------|
| `current-dir` | Working directory |
| `git-branch` | Current git branch |
| `model-with-reasoning` | Model name + reasoning level |
| `weekly-limit` | Weekly rate limit |

### Install

```bash
curl -fsSL https://raw.githubusercontent.com/gencrewai/aiops/main/codex-install.sh | bash
```

This adds `tui.status_line` config to your `~/.codex/config.toml`.
The installer assumes a bash-capable environment. On Windows without Git Bash or WSL, edit `config.toml` manually.

Restart Codex CLI after installing.

#### Manual Install

Add to `~/.codex/config.toml`:

```toml
[tui]
status_line = ["current-dir", "git-branch", "model-with-reasoning", "weekly-limit"]
status_line_use_colors = true
```

#### Customize Interactively

Inside Codex CLI, run `/statusline` to toggle and reorder items.

### Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/gencrewai/aiops/main/codex-uninstall.sh | bash
```

---

## Requirements

- **Claude Code**: Claude Code CLI with `statusLine` support, plus bash for `.sh` installs or PowerShell for Windows installs
- **Codex CLI**: Codex CLI v0.1+ with `/statusline` support

## License

MIT
