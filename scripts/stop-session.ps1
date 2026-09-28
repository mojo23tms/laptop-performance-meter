$ErrorActionPreference = "SilentlyContinue"
$repoRoot = Split-Path -Parent $PSScriptRoot
$stateFile = Join-Path $repoRoot ".active-session.json"

if (-not (Test-Path $stateFile)) {
    Write-Host "No active session state file found."
    exit 0
}

$state = Get-Content $stateFile -Raw | ConvertFrom-Json
$sessionDir = $state.session_directory
$stopFile = Join-Path $sessionDir "STOP"

Set-Content -Path $stopFile -Value "stop" -Encoding ascii

Write-Host "Stop requested for:"
Write-Host "  $($state.label)"
Write-Host "  $sessionDir"

for ($i = 0; $i -lt 10; $i++) {
    if (-not (Get-Process -Id $state.pid -ErrorAction SilentlyContinue)) { break }
    Start-Sleep -Milliseconds 500
}

if (Get-Process -Id $state.pid -ErrorAction SilentlyContinue) {
    Write-Host "Collector is still shutting down; leaving it to exit cleanly."
} else {
    Remove-Item $stateFile -Force
    Write-Host "Collector stopped."
}
