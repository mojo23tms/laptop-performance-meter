param(
    [Parameter(Mandatory=$true)]
    [string]$Label,

    [int]$IntervalSeconds = 0,

    [string]$Notes = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $repoRoot "config\monitor.json"

$config = Get-Content $configPath -Raw | ConvertFrom-Json
if ($IntervalSeconds -le 0) {
    $IntervalSeconds = [int]$config.interval_seconds
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$safeLabel = ($Label -replace '[^a-zA-Z0-9._-]', '-').Trim('-')
$sessionName = "$timestamp-$safeLabel"
$sessionDir = Join-Path $repoRoot "sessions\$sessionName"

New-Item -ItemType Directory -Force -Path $sessionDir | Out-Null

$session = [ordered]@{
    label = $Label
    notes = $Notes
    started_at = (Get-Date).ToString("o")
    interval_seconds = $IntervalSeconds
}
$session | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $sessionDir "session.json") -Encoding UTF8

$collector = Join-Path $PSScriptRoot "collect.ps1"
$args = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", "`"$collector`"",
    "-OutputDirectory", "`"$sessionDir`"",
    "-IntervalSeconds", $IntervalSeconds,
    "-TopProcessCount", [int]$config.top_process_count
)

$proc = Start-Process powershell.exe -ArgumentList $args -WindowStyle Minimized -PassThru

$state = [ordered]@{
    pid = $proc.Id
    session_directory = $sessionDir
    label = $Label
    started_at = (Get-Date).ToString("o")
}
$state | ConvertTo-Json | Set-Content (Join-Path $repoRoot ".active-session.json") -Encoding UTF8

Write-Host ""
Write-Host "Session started:"
Write-Host "  $Label"
Write-Host ""
Write-Host "Directory:"
Write-Host "  $sessionDir"
Write-Host ""
Write-Host "Collector PID: $($proc.Id)"
Write-Host ""
Write-Host "Stop with:"
Write-Host "  .\scripts\stop-session.ps1"
