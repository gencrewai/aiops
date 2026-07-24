param(
  [Parameter(Position=0)]
  [ValidateSet('full', 'lite')]
  [string]$Mode = 'full',

  [switch]$left,

  [switch]$soft,

  [switch]$maskAccount
)

$View = if ($left) { 'left' } else { 'used' }
$Theme = if ($soft) { 'soft' } else { 'normal' }

$inputText = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($inputText)) {
  exit 0
}

try {
  $data = $inputText | ConvertFrom-Json
} catch {
  [Console]::Out.Write('Claude')
  exit 0
}

$esc = [char]27
$RST = "${esc}[0m"
$DIM = "${esc}[2m"
$BOLD = "${esc}[1m"

if ($Theme -eq 'soft') {
  $CYAN = "${esc}[38;2;137;207;240m"
  $GREEN = "${esc}[38;2;152;224;173m"
  $YELLOW = "${esc}[38;2;255;213;128m"
  $RED = "${esc}[38;2;255;154;139m"
  $WHITE = "${esc}[38;2;255;253;230m"
  $MAGENTA = "${esc}[38;2;200;162;200m"
  $BLUE = "${esc}[38;2;174;198;255m"
  $SEP = " ${DIM}$([char]0x00B7)${RST} "
} else {
  $CYAN = "${esc}[36m"
  $GREEN = "${esc}[32m"
  $YELLOW = "${esc}[33m"
  $RED = "${esc}[31m"
  $WHITE = "${esc}[37m"
  $MAGENTA = "${esc}[35m"
  $BLUE = "${esc}[34m"
  $SEP = " ${DIM}|${RST} "
}

function Get-StringValue {
  param(
    [object]$Value,
    [string]$Default = ''
  )

  if ($null -eq $Value) {
    return $Default
  }

  $text = [string]$Value
  if ([string]::IsNullOrWhiteSpace($text)) {
    return $Default
  }

  return $text
}

function Get-IntValue {
  param(
    [object]$Value,
    [int]$Default = 0
  )

  if ($null -eq $Value) {
    return $Default
  }

  try {
    return [int][Math]::Floor([double]$Value)
  } catch {
    return $Default
  }
}

function Clamp-Percent {
  param([int]$Percent)

  if ($Percent -lt 0) {
    return 0
  }

  if ($Percent -gt 100) {
    return 100
  }

  return $Percent
}

function Format-Tokens {
  param([int]$Count)

  if ($Count -ge 1000000) {
    return '{0}.{1}M' -f [int]($Count / 1000000), [int](($Count % 1000000) / 100000)
  }

  if ($Count -ge 1000) {
    return '{0}K' -f [int]($Count / 1000)
  }

  return [string]$Count
}

function Make-Bar {
  param(
    [int]$Percent,
    [int]$Width = 10
  )

  $Percent = Clamp-Percent $Percent
  $filled = [Math]::Min($Width, [int][Math]::Floor($Percent * $Width / 100))
  $empty = [Math]::Max(0, $Width - $filled)
  return ('#' * $filled) + ('-' * $empty)
}

function Get-PctColor {
  param([int]$Percent)

  if ($Percent -ge 80) {
    return $RED
  }

  if ($Percent -ge 50) {
    return $YELLOW
  }

  return $GREEN
}

function Get-HealthColor {
  param([int]$Percent)

  if ($Percent -le 30) {
    return $RED
  }

  if ($Percent -le 60) {
    return $YELLOW
  }

  return $GREEN
}

function Get-EffortColor {
  param([string]$Level)

  switch ($Level.ToLower()) {
    'high'   { return $MAGENTA }
    'medium' { return $BLUE }
    'med'    { return $BLUE }
    'low'    { return $GREEN }
    default  { return $DIM }
  }
}

function Invoke-GitText {
  param(
    [string]$WorkingDirectory,
    [string[]]$Arguments
  )

  if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) {
    return ''
  }

  if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    return ''
  }

  try {
    $output = & git -C $WorkingDirectory @Arguments 2>$null
    if ($LASTEXITCODE -eq 0) {
      return (($output | Out-String).Trim())
    }
  } catch {
  }

  return ''
}

function Get-Account {
  # logged-in Claude account — not present in stdin JSON, read from config file
  $cfg = if ($env:CLAUDE_CONFIG_DIR) { Join-Path $env:CLAUDE_CONFIG_DIR '.claude.json' } else { Join-Path $HOME '.claude.json' }
  if (-not (Test-Path $cfg)) { $cfg = Join-Path $HOME '.claude.json' }
  if (-not (Test-Path $cfg)) { return '' }

  try {
    $match = Select-String -Path $cfg -Pattern '"emailAddress"\s*:\s*"([^"]*)"' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($match) {
      # strip control chars (incl. ESC) to prevent terminal injection from a crafted config
      return ($match.Matches[0].Groups[1].Value -replace '[\x00-\x1F\x7F]', '')
    }
  } catch {
  }

  return ''
}

function Mask-Email {
  param([string]$Email)

  if ($Email -match '^(.{1,2})[^@]*@(.+)$') {
    return ('{0}***@{1}' -f $Matches[1], $Matches[2])
  }

  return $Email
}

$modelName = Get-StringValue $data.model.display_name 'Claude'
$modelShort = if ($modelName -like 'Claude *') { $modelName.Substring(7) } else { $modelName }

# reasoning effort (Opus 4.5+): "effort":{"level":"high"} or "effort":"high"
$effortLevel = ''
if ($null -ne $data.effort) {
  if ($data.effort -is [string]) {
    $effortLevel = Get-StringValue $data.effort ''
  } else {
    $effortLevel = Get-StringValue $data.effort.level ''
  }
}

$ctx = $data.context_window
$cost = $data.cost
$workspace = $data.workspace
$rateLimits = $data.rate_limits
$currentUsage = $ctx.current_usage

$inputTokens = Get-IntValue $ctx.total_input_tokens 0
$outputTokens = Get-IntValue $ctx.total_output_tokens 0
$ctxSize = Get-IntValue $ctx.context_window_size 200000
$ctxPct = Clamp-Percent (Get-IntValue $ctx.used_percentage 0)
$costUsd = if ($null -eq $cost.total_cost_usd) { 0.0 } else { [double]$cost.total_cost_usd }

$durationMs = Get-IntValue $cost.total_duration_ms 0
$linesAdded = Get-IntValue $cost.total_lines_added 0
$linesRemoved = Get-IntValue $cost.total_lines_removed 0

$cacheReadFallback = Get-IntValue $currentUsage.cache_read_input_tokens 0
$cacheCreateFallback = Get-IntValue $currentUsage.cache_creation_input_tokens 0
$cacheRead = Get-IntValue $data.cache_read_input_tokens $cacheReadFallback
$cacheCreate = Get-IntValue $data.cache_creation_input_tokens $cacheCreateFallback

$cwd = Get-StringValue $workspace.current_dir (Get-StringValue $data.cwd '')
$projectName = if ($cwd) { Split-Path -Leaf $cwd } else { '' }
if ([string]::IsNullOrWhiteSpace($projectName)) {
  $projectName = if ($cwd) { $cwd } else { '?' }
}

# repo name from the main repo root (resolves worktrees/subdirs); prefixed when it differs
$gitCommonDir = Invoke-GitText -WorkingDirectory $cwd -Arguments @('rev-parse', '--git-common-dir')
if (-not [string]::IsNullOrWhiteSpace($gitCommonDir)) {
  if (-not [System.IO.Path]::IsPathRooted($gitCommonDir)) {
    $gitCommonDir = Join-Path $cwd $gitCommonDir
  }
  # physical resolve so relative segments like ".." don't leak into the name
  $repoRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $gitCommonDir))
  $repoName = Split-Path -Leaf $repoRoot
  if ($repoName -and $repoName -ne $projectName) {
    $projectName = "$repoName/$projectName"
  }
}

$accountEmail = Get-Account

$fivePct = Clamp-Percent (Get-IntValue $rateLimits.five_hour.used_percentage 0)
$fiveReset = Get-IntValue $rateLimits.five_hour.resets_at 0
$sevenPct = Clamp-Percent (Get-IntValue $rateLimits.seven_day.used_percentage 0)

$totalTokens = $inputTokens + $outputTokens

$durationSec = [int][Math]::Floor($durationMs / 1000)
$durMin = [int][Math]::Floor($durationSec / 60)
$durSec = $durationSec % 60
if ($durMin -ge 60) {
  $durDisplay = '{0}h{1}m' -f [int]($durMin / 60), ($durMin % 60)
} else {
  $durDisplay = '{0}m{1}s' -f $durMin, $durSec
}

$fiveRemainDisplay = ''
if ($fiveReset -gt 0) {
  $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $diff = $fiveReset - $now
  if ($diff -gt 0) {
    $hours = [int][Math]::Floor($diff / 3600)
    $minutes = [int][Math]::Floor(($diff % 3600) / 60)
    $fiveRemainDisplay = '{0}h{1}m' -f $hours, $minutes
  }
}

$gitBranch = Invoke-GitText -WorkingDirectory $cwd -Arguments @('branch', '--show-current')
if ([string]::IsNullOrWhiteSpace($gitBranch)) {
  $gitBranch = '-'
}

$gitHash = Invoke-GitText -WorkingDirectory $cwd -Arguments @('rev-parse', '--short', 'HEAD')
if ([string]::IsNullOrWhiteSpace($gitHash)) {
  $gitHash = '-'
}

$cacheTotal = $cacheRead + $cacheCreate
$cachePct = if ($cacheTotal -gt 0) { [int][Math]::Floor($cacheRead * 100 / $cacheTotal) } else { 0 }

$ctxRemain = Clamp-Percent (100 - $ctxPct)
$fiveRemain = Clamp-Percent (100 - $fivePct)
$sevenRemain = Clamp-Percent (100 - $sevenPct)

$costFmt = '{0:F2}' -f $costUsd

# reasoning effort segment (shown right after model, only if present)
$effortSeg = ''
if ($effortLevel) {
  $brain = [char]::ConvertFromUtf32(0x1F9E0)
  $effortSeg = " ${DIM}${brain}${RST}$(Get-EffortColor $effortLevel)${effortLevel}${RST}"
}

$line1 = @(
  "${BOLD}${CYAN}${modelShort}${RST}${effortSeg}"
  "${DIM}In:${RST}${WHITE}$(Format-Tokens $inputTokens)${RST} ${DIM}Out:${RST}${WHITE}$(Format-Tokens $outputTokens)${RST}"
  "${WHITE}$(Format-Tokens $totalTokens)/$(Format-Tokens $ctxSize)${RST}"
  "${BOLD}${YELLOW}`$$costFmt${RST}"
) -join $SEP

$accountDisplay = if ($maskAccount) { Mask-Email $accountEmail } else { $accountEmail }

$line2Parts = @(
  "${BLUE}${projectName}${RST}"
  "${YELLOW}${gitBranch}${RST} ${DIM}${gitHash}${RST}"
  "${MAGENTA}$([char]0x23F1) ${durDisplay}${RST}"
  "${GREEN}+${linesAdded}${RST} ${RED}-${linesRemoved}${RST}"
)
if ($accountEmail) {
  $person = [char]::ConvertFromUtf32(0x1F464)
  $line2Parts += "${person} ${WHITE}${accountDisplay}${RST}"
}
$line2 = $line2Parts -join $SEP

if ($View -eq 'left') {
  $ctxV = $ctxRemain; $fiveV = $fiveRemain; $sevenV = $sevenRemain
  $ctxVc = Get-HealthColor $ctxV
  $fiveVc = Get-HealthColor $fiveV
  $sevenVc = Get-HealthColor $sevenV
  $ctxLabel = 'ctx left'; $fiveLabel = '5h left'; $sevenLabel = '7d left'
} else {
  $ctxV = $ctxPct; $fiveV = $fivePct; $sevenV = $sevenPct
  $ctxVc = Get-PctColor $ctxV
  $fiveVc = Get-PctColor $fiveV
  $sevenVc = Get-PctColor $sevenV
  $ctxLabel = 'ctx'; $fiveLabel = '5h'; $sevenLabel = '7d'
}

$line3 = @(
  "${DIM}${ctxLabel}${RST} ${ctxVc}$(Make-Bar -Percent $ctxV -Width 8) ${ctxV}%${RST}"
  "${DIM}${fiveLabel}${RST} ${fiveVc}$(Make-Bar -Percent $fiveV -Width 8) ${fiveV}%${RST}$(
    if ($fiveRemainDisplay) { "${DIM}(${fiveRemainDisplay})${RST}" } else { '' }
  )"
  "${DIM}${sevenLabel}${RST} ${sevenVc}$(Make-Bar -Percent $sevenV -Width 8) ${sevenV}%${RST}"
  "${DIM}cache${RST} ${GREEN}${cachePct}%${RST}"
) -join $SEP

if ($Mode -eq 'lite') {
  $liteParts = @(
    "${BLUE}${projectName}${RST}"
    "${YELLOW}${gitBranch}${RST}"
    "${BOLD}${CYAN}${modelShort}${RST}${effortSeg}"
  )
  if ($View -eq 'left') {
    $liteParts += "${DIM}5h left${RST} ${fiveVc}$(Make-Bar -Percent $fiveV -Width 8) ${fiveV}%${RST}"
    $liteParts += "${DIM}7d left${RST} ${sevenVc}$(Make-Bar -Percent $sevenV -Width 8) ${sevenV}%${RST}"
  } else {
    $liteParts += "${DIM}5h${RST} ${fiveVc}$(Make-Bar -Percent $fiveV -Width 8) ${fiveV}%${RST}"
    $liteParts += "${DIM}7d${RST} ${sevenVc}$(Make-Bar -Percent $sevenV -Width 8) ${sevenV}%${RST}"
  }
  [Console]::Out.Write($liteParts -join $SEP)
  exit 0
}

[Console]::Out.WriteLine($line1)
[Console]::Out.WriteLine($line2)
[Console]::Out.Write($line3)
