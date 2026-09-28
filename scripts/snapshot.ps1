$ErrorActionPreference = "SilentlyContinue"

Write-Host "=== POWER ==="
powercfg /getactivescheme

Write-Host ""
Write-Host "=== CPU / SYSTEM ==="
Get-CimInstance Win32_Processor |
    Select-Object Name, LoadPercentage, CurrentClockSpeed, MaxClockSpeed |
    Format-List

Get-CimInstance Win32_OperatingSystem |
    Select-Object Caption, Version, FreePhysicalMemory, TotalVisibleMemorySize |
    Format-List

Write-Host ""
Write-Host "=== NVIDIA GPU ==="
if (Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue) {
    nvidia-smi.exe --query-gpu=name,utilization.gpu,utilization.memory,temperature.gpu,power.draw,clocks.current.graphics,clocks.current.memory,pstate,memory.used,memory.total --format=csv
    Write-Host ""
    Write-Host "GPU processes:"
    nvidia-smi.exe
} else {
    Write-Host "nvidia-smi not found."
}

Write-Host ""
Write-Host "=== TOP CPU PROCESSES ==="
Get-Process |
    Sort-Object CPU -Descending |
    Select-Object -First 15 Name, Id, CPU, WorkingSet64 |
    Format-Table -AutoSize
