# Codex project instructions

This repository diagnoses laptop thermal/noise behaviour.

## Priorities

1. Preserve raw telemetry.
2. Never silently mutate system power, BIOS, fan, voltage or clock settings.
3. Any system-setting helper must default to read-only / dry-run and require explicit opt-in for changes.
4. Compare power draw with temperature; do not classify temperature alone as a hardware fault.
5. Keep collectors deterministic and low overhead.
6. Store generated telemetry only under `sessions/`.
7. Keep `sessions/` ignored by Git.
8. Prefer Windows-native APIs and documented vendor CLIs.
9. Any heuristic warning must be described as a heuristic, not a diagnosis.

## Near-term roadmap

- Add LibreHardwareMonitor integration for CPU temperature/package power/fans.
- Detect attached displays and refresh rates.
- Add experiment-to-experiment comparison.
- Add an HTML report.
- Add collection health checks.
- Add unit tests for CSV parsing and heuristic rules.
