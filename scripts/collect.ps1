param(
    [Parameter(Mandatory=$true)]
    [string]$OutputDirectory,

    [int]$IntervalSeconds = 5,

    [int]$TopProcessCount = 8
)

$ErrorActionPreference = "SilentlyContinue"
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

$systemCsv = Join-Path $OutputDirectory "system.csv"
$processCsv = Join-Path $OutputDirectory "processes.csv"
$metadataJson = Join-Path $OutputDirectory "metadata.json"
$heartbeat = Join-Path $OutputDirectory "collector.heartbeat"
$stopFile = Join-Path $OutputDirectory "STOP"

function Get-PowerScheme {
    try {
        $line = powercfg /getactivescheme
        if ($line -match '\((.+)\)') { return $Matches[1] }
        return ($line -join " ").Trim()
    } catch { return $null }
}

function Get-BatteryInfo {
    try {
        $battery = Get-CimInstance Win32_Battery | Select-Object -First 1
        if ($null -eq $battery) {
            return [PSCustomObject]@{
                Present = $false
                EstimatedChargeRemaining = $null
                BatteryStatus = $null
            }
        }
        return [PSCustomObject]@{
            Present = $true
            EstimatedChargeRemaining = $battery.EstimatedChargeRemaining
            BatteryStatus = $battery.BatteryStatus
        }
    } catch {
        return [PSCustomObject]@{
            Present = $false
            EstimatedChargeRemaining = $null
            BatteryStatus = $null
        }
    }
}

function Get-NvidiaData {
    $result = [ordered]@{
        gpu_name = $null
        gpu_util_pct = $null
        gpu_mem_util_pct = $null
        gpu_temp_c = $null
        gpu_power_w = $null
        gpu_clock_mhz = $null
        gpu_mem_clock_mhz = $null
        gpu_pstate = $null
        gpu_mem_used_mb = $null
        gpu_mem_total_mb = $null
    }

    $smi = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
    if ($null -eq $smi) { return [PSCustomObject]$result }

    $query = @(
        "name",
        "utilization.gpu",
        "utilization.memory",
        "temperature.gpu",
        "power.draw",
        "clocks.current.graphics",
        "clocks.current.memory",
        "pstate",
        "memory.used",
        "memory.total"
    ) -join ","

    try {
        $raw = & nvidia-smi.exe "--query-gpu=$query" "--format=csv,noheader,nounits" 2>$null | Select-Object -First 1
        if (-not $raw) { return [PSCustomObject]$result }

        $parts = $raw -split ",\s*"
        if ($parts.Count -ge 10) {
            $result.gpu_name = $parts[0]
            $result.gpu_util_pct = $parts[1]
            $result.gpu_mem_util_pct = $parts[2]
            $result.gpu_temp_c = $parts[3]
            $result.gpu_power_w = $parts[4]
            $result.gpu_clock_mhz = $parts[5]
            $result.gpu_mem_clock_mhz = $parts[6]
            $result.gpu_pstate = $parts[7]
            $result.gpu_mem_used_mb = $parts[8]
            $result.gpu_mem_total_mb = $parts[9]
        }
    } catch {}

    return [PSCustomObject]$result
}

function Get-SystemSnapshot {
    $cpu = $null
    try {
        $cpuSample = Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction Stop
        $cpu = [math]::Round($cpuSample.CounterSamples[0].CookedValue, 2)
    } catch {
        try {
            $cpu = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
        } catch {}
    }

    $os = Get-CimInstance Win32_OperatingSystem
    $totalMemMb = if ($os.TotalVisibleMemorySize) { [math]::Round($os.TotalVisibleMemorySize / 1024, 1) } else { $null }
    $freeMemMb = if ($os.FreePhysicalMemory) { [math]::Round($os.FreePhysicalMemory / 1024, 1) } else { $null }
    $usedMemPct = if ($totalMemMb -and $freeMemMb -ne $null) {
        [math]::Round((($totalMemMb - $freeMemMb) / $totalMemMb) * 100, 2)
    } else { $null }

    $gpu = Get-NvidiaData
    $battery = Get-BatteryInfo

    [PSCustomObject]@{
        timestamp = (Get-Date).ToString("o")
        cpu_total_pct = $cpu
        memory_used_pct = $usedMemPct
        memory_total_mb = $totalMemMb
        memory_free_mb = $freeMemMb
        power_scheme = Get-PowerScheme
        battery_present = $battery.Present
        battery_pct = $battery.EstimatedChargeRemaining
        battery_status = $battery.BatteryStatus
        gpu_name = $gpu.gpu_name
        gpu_util_pct = $gpu.gpu_util_pct
        gpu_mem_util_pct = $gpu.gpu_mem_util_pct
        gpu_temp_c = $gpu.gpu_temp_c
        gpu_power_w = $gpu.gpu_power_w
        gpu_clock_mhz = $gpu.gpu_clock_mhz
        gpu_mem_clock_mhz = $gpu.gpu_mem_clock_mhz
        gpu_pstate = $gpu.gpu_pstate
        gpu_mem_used_mb = $gpu.gpu_mem_used_mb
        gpu_mem_total_mb = $gpu.gpu_mem_total_mb
    }
}

function Get-TopProcesses {
    param([int]$Count)

    try {
        $logical = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
        if (-not $logical) { $logical = 1 }

        $samples = Get-CimInstance Win32_PerfFormattedData_PerfProc_Process |
            Where-Object { $_.Name -notin @("_Total", "Idle") } |
            Sort-Object PercentProcessorTime -Descending |
            Select-Object -First $Count

        foreach ($p in $samples) {
            [PSCustomObject]@{
                timestamp = (Get-Date).ToString("o")
                process = $p.Name
                pid = $p.IDProcess
                cpu_pct_approx = [math]::Round(([double]$p.PercentProcessorTime / $logical), 2)
                working_set_mb = [math]::Round(([double]$p.WorkingSetPrivate / 1MB), 1)
            }
        }
    } catch {}
}

$cs = Get-CimInstance Win32_ComputerSystem
$cpuInfo = Get-CimInstance Win32_Processor | Select-Object -First 1
$gpuInfo = Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion, AdapterRAM
$osInfo = Get-CimInstance Win32_OperatingSystem

$metadata = [ordered]@{
    started_at = (Get-Date).ToString("o")
    computer_model = $cs.Model
    manufacturer = $cs.Manufacturer
    cpu = $cpuInfo.Name
    logical_processors = $cs.NumberOfLogicalProcessors
    total_memory_gb = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
    os = $osInfo.Caption
    os_version = $osInfo.Version
    power_scheme_at_start = Get-PowerScheme
    video_controllers = @($gpuInfo)
    interval_seconds = $IntervalSeconds
    collector_version = "0.1.0"
}
$metadata | ConvertTo-Json -Depth 5 | Set-Content -Path $metadataJson -Encoding UTF8

Write-Host "Collecting telemetry into $OutputDirectory"
Write-Host "Interval: $IntervalSeconds s"
Write-Host "Create $stopFile or use stop-session.ps1 to stop."

while (-not (Test-Path $stopFile)) {
    try {
        $snapshot = Get-SystemSnapshot
        if (-not (Test-Path $systemCsv)) {
            $snapshot | Export-Csv -Path $systemCsv -NoTypeInformation -Encoding UTF8
        } else {
            $snapshot | Export-Csv -Path $systemCsv -NoTypeInformation -Append -Encoding UTF8
        }

        $procs = @(Get-TopProcesses -Count $TopProcessCount)
        if ($procs.Count -gt 0) {
            if (-not (Test-Path $processCsv)) {
                $procs | Export-Csv -Path $processCsv -NoTypeInformation -Encoding UTF8
            } else {
                $procs | Export-Csv -Path $processCsv -NoTypeInformation -Append -Encoding UTF8
            }
        }

        Set-Content -Path $heartbeat -Value (Get-Date).ToString("o") -Encoding ascii
    } catch {
        Add-Content -Path (Join-Path $OutputDirectory "collector-errors.log") -Value "$((Get-Date).ToString('o')) $($_.Exception.Message)"
    }

    Start-Sleep -Seconds $IntervalSeconds
}

Remove-Item $stopFile -Force -ErrorAction SilentlyContinue
$metadata.finished_at = (Get-Date).ToString("o")
$metadata | ConvertTo-Json -Depth 5 | Set-Content -Path $metadataJson -Encoding UTF8
Write-Host "Collector stopped."
