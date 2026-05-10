param(
  [ValidateSet('full', 'lite')]
  [string]$Mode = 'full'
)

$ErrorActionPreference = 'Stop'

$repo = if ($env:AIOPS_REPO) { $env:AIOPS_REPO } else { 'gencrewai/aiops' }
$scriptName = 'claude-statusline.ps1'
$installDir = if ($env:CLAUDE_HOME) { $env:CLAUDE_HOME } else { Join-Path $HOME '.claude' }
$installPath = Join-Path $installDir $scriptName
$settingsFile = Join-Path $installDir 'settings.json'
$scriptSource = $env:AIOPS_SCRIPT_SOURCE

function Write-Utf8NoBom {
  param(
    [string]$Path,
    [string]$Content
  )

  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

Write-Host "Installing claude-statusline ($Mode mode)..."

New-Item -ItemType Directory -Path $installDir -Force | Out-Null
if ($scriptSource) {
  if (-not (Test-Path -LiteralPath $scriptSource)) {
    throw "AIOPS_SCRIPT_SOURCE does not exist: $scriptSource"
  }
  Copy-Item -LiteralPath $scriptSource -Destination $installPath -Force
} else {
  Invoke-WebRequest -Uri "https://raw.githubusercontent.com/$repo/main/$scriptName" -OutFile $installPath
}
Write-Host "  Downloaded $installPath"

$resolvedInstallPath = (Resolve-Path -LiteralPath $installPath).Path -replace '\\', '/'
$command = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$resolvedInstallPath`""
if ($Mode -eq 'lite') {
  $command = "$command lite"
}

$settings = [pscustomobject]@{}
if (Test-Path -LiteralPath $settingsFile) {
  $raw = Get-Content -Raw -LiteralPath $settingsFile
  if (-not [string]::IsNullOrWhiteSpace($raw)) {
    try {
      $settings = $raw | ConvertFrom-Json
    } catch {
      throw "Failed to parse ${settingsFile}: $($_.Exception.Message)"
    }
  }
}

if ($null -eq $settings) {
  $settings = [pscustomobject]@{}
}

if ($settings -isnot [System.Management.Automation.PSCustomObject]) {
  throw "${settingsFile} must contain a JSON object"
}

$existing = [ordered]@{}
$existingStatusLine = $settings.PSObject.Properties['statusLine']
if ($existingStatusLine -and $existingStatusLine.Value -is [System.Management.Automation.PSCustomObject]) {
  foreach ($property in $existingStatusLine.Value.PSObject.Properties) {
    $existing[$property.Name] = $property.Value
  }
}

$existing['type'] = 'command'
$existing['command'] = $command

if ($existingStatusLine) {
  $settings.statusLine = [pscustomobject]$existing
} else {
  $settings | Add-Member -NotePropertyName 'statusLine' -NotePropertyValue ([pscustomobject]$existing)
}

Write-Utf8NoBom -Path $settingsFile -Content (($settings | ConvertTo-Json -Depth 20) + [Environment]::NewLine)
Write-Host "  Configured statusLine in settings.json"

Write-Host ''
Write-Host 'Done! Restart Claude Code to see the status bar.'
Write-Host ''
Write-Host 'Modes:'
Write-Host '  full (default) - 3-line: model, context, cost, git, limits, cache'
Write-Host '  lite           - 1-line: folder | branch | model | 5h | 7d'
Write-Host ''
Write-Host "Switch mode: re-run installer with -Mode lite or -Mode full"
Write-Host "To uninstall: download and run https://raw.githubusercontent.com/$repo/main/uninstall.ps1"
