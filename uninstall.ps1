param()

$ErrorActionPreference = 'Stop'

$installDir = if ($env:CLAUDE_HOME) { $env:CLAUDE_HOME } else { Join-Path $HOME '.claude' }
$installPath = Join-Path $installDir 'claude-statusline.ps1'
$settingsFile = Join-Path $installDir 'settings.json'

function Write-Utf8NoBom {
  param(
    [string]$Path,
    [string]$Content
  )

  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

Write-Host 'Uninstalling claude-statusline...'

if (Test-Path -LiteralPath $installPath) {
  Remove-Item -LiteralPath $installPath -Force
  Write-Host "  Removed $installPath"
} else {
  Write-Host '  Script not found (already removed?)'
}

if (Test-Path -LiteralPath $settingsFile) {
  $raw = Get-Content -Raw -LiteralPath $settingsFile
  if (-not [string]::IsNullOrWhiteSpace($raw)) {
    try {
      $settings = $raw | ConvertFrom-Json
    } catch {
      throw "Failed to parse ${settingsFile}: $($_.Exception.Message)"
    }

    if ($settings -isnot [System.Management.Automation.PSCustomObject]) {
      throw "${settingsFile} must contain a JSON object"
    }

    if ($settings.PSObject.Properties['statusLine']) {
      $settings.PSObject.Properties.Remove('statusLine')
      Write-Utf8NoBom -Path $settingsFile -Content (($settings | ConvertTo-Json -Depth 20) + [Environment]::NewLine)
      Write-Host '  Removed statusLine from settings.json'
    } else {
      Write-Host '  No statusLine config found (nothing to remove)'
    }
  } else {
    Write-Host '  settings.json is empty (nothing to remove)'
  }
} else {
  Write-Host "  No settings.json found at $settingsFile"
}

Write-Host ''
Write-Host 'Done! Restart Claude Code to apply.'
