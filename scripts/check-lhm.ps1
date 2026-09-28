. "$PSScriptRoot\librehardwaremonitor.ps1"

$repoRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $repoRoot "config\monitor.json"
$config = Get-Content $configPath -Raw | ConvertFrom-Json
$url = if ($config.lhm_base_url) { [string]$config.lhm_base_url } else { "http://127.0.0.1:8085" }

try {
    $sensors = @(Get-LhmSnapshot -BaseUrl $url)
    Write-Host "LibreHardwareMonitor reachable at $url"
    Write-Host "Sensors found: $($sensors.Count)"
    Write-Host ""

    $interesting = $sensors |
        Where-Object {
            $_.sensor_type -in @("Temperature", "Power", "Fan", "Clock", "Load") -or
            $_.name -match "Package|Fan|Hot Spot|Core|CPU"
        } |
        Select-Object -First 40 path, sensor_type, value, raw_value

    $interesting | Format-Table -AutoSize
} catch {
    Write-Error $_
    exit 1
}
