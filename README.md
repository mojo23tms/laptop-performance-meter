# Laptop Performance Meter

A lightweight Windows telemetry + analysis toolkit for diagnosing heat, fan-noise and power-behaviour issues on gaming laptops. Initial target: **Gigabyte G5 MF / Intel Core i5-12500H / NVIDIA RTX 4050 Laptop GPU**.

> Measure first. Change one variable. Measure again.

The project separates **collection** from **analysis** so the raw evidence stays reproducible and can later be inspected by Codex, ChatGPT, Python, or plain CSV tools.

## What it records

Without paid software:

- timestamp
- Windows total CPU load
- RAM usage
- current Windows power scheme
- AC/battery state
- top CPU-consuming processes
- NVIDIA GPU utilization
- GPU memory utilization
- GPU temperature
- GPU power draw
- GPU graphics/memory clocks
- GPU P-state
- GPU VRAM usage

Optional HWiNFO CSV ingestion can add:

- CPU package temperature
- CPU package power
- CPU core temperatures
- thermal/power throttling flags
- SSD temperatures
- fan RPM where exposed
- motherboard / EC sensors

## Layout

```text
laptop-performance-meter/
├─ scripts/
│  ├─ collect.ps1
│  ├─ start-session.ps1
│  ├─ snapshot.ps1
│  └─ stop-session.ps1
├─ analysis/
│  └─ analyse.py
├─ config/
│  └─ monitor.json
├─ docs/
│  └─ TEST_PLAN.md
├─ sessions/
│  └─ .gitkeep
├─ requirements.txt
├─ CODEX.md
└─ .gitignore
```

## Requirements

- Windows 10/11
- PowerShell 5.1+ or PowerShell 7+
- NVIDIA driver / `nvidia-smi` for NVIDIA telemetry
- Python 3.10+

Install Python dependencies:

```powershell
py -m pip install -r requirements.txt
```

## Quick start

Start an idle baseline:

```powershell
.\scripts\start-session.ps1 -Label "idle-normal-setup"
```

Leave the machine alone for about 10 minutes, then stop:

```powershell
.\scripts\stop-session.ps1
```

Analyze it:

```powershell
py .\analysis\analyse.py .\sessions\<session-folder>
```

The analyzer creates:

- `summary.json`
- `report.md`
- charts under `charts/`

## Recommended diagnostic sequence

Run separate sessions for:

1. `idle-normal-setup`
2. `idle-monitor-disconnected`
3. `idle-balanced-power`
4. `idle-gigabyte-entertainment`
5. `idle-turbo-disabled-test`
6. `idle-pad-off-raised`
7. `idle-pad-on`
8. `game-normal`
9. `game-fps-capped`
10. `game-pad-on`

Do **one configuration change per session**.

See [docs/TEST_PLAN.md](docs/TEST_PLAN.md).

## Optional HWiNFO integration

Use HWiNFO GUI sensor logging and save the resulting CSV inside a session as:

```text
hwinfo.csv
```

Then rerun the analyzer. It will discover and summarize relevant numeric HWiNFO sensor columns automatically.

Automated HWiNFO CLI logging is intentionally not required because that interface is part of HWiNFO Pro.

## Sampling interval

Default: 5 seconds.

Change it in `config/monitor.json` or pass `-IntervalSeconds` to `start-session.ps1`.

For thermal diagnosis, 2–5 seconds is normally enough.

## Privacy

The collector does not intentionally collect:

- keystrokes
- browser history
- window titles
- file contents
- network payloads
- passwords

It does log process names and basic machine/power information.

Review generated logs before sharing them publicly.

## Interpretation

Temperature without power draw is incomplete evidence.

- **high temperature + high watts** may simply mean the cooling system is saturated
- **high temperature + low watts** is more suspicious for poor contact, airflow, fan behaviour, or the thermal interface
- **elevated GPU power + near-zero GPU utilization** can indicate the dGPU is being kept awake

## Roadmap

- LibreHardwareMonitor integration for CPU package temperature/power/fans
- attached-display and refresh-rate detection
- experiment-to-experiment comparison
- local HTML dashboard
- collection health checks
- unit tests
- GitHub issue/report generation
- Codex-assisted session diagnosis
