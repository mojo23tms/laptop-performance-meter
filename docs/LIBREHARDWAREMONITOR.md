# LibreHardwareMonitor setup

This project can optionally collect deeper hardware sensors through the built-in LibreHardwareMonitor web server.

The integration is **read-only**. It only downloads `data.json`; it does not write control values.

## 1. Install LibreHardwareMonitor

Use the official project/release source:

https://github.com/LibreHardwareMonitor/LibreHardwareMonitor

Extract it somewhere convenient.

## 2. Run as Administrator

Run LibreHardwareMonitor with Administrator privileges so hardware sensors have the best chance of being exposed.

## 3. Enable the local web server

Inside LibreHardwareMonitor:

`Options -> Remote Web Server -> Run`

The default port is **8085**.

Newer builds support listener configuration. For this project, prefer binding to localhost / `127.0.0.1` when available because the collector only needs local access.

## 4. Verify

Open PowerShell:

```powershell
Invoke-RestMethod http://127.0.0.1:8085/data.json | Select-Object Version, Text
```

If you get a JSON object rather than a connection error, it is working.

You can also run:

```powershell
.\scripts\check-lhm.ps1
```

## 5. Run a normal telemetry session

```powershell
& .\scripts\start-session.ps1 -Label "idle-lhm-baseline"
```

When LibreHardwareMonitor is detected, the collector writes:

```text
sessions/<session>/lhm.csv
```

This is a long-form sensor log containing timestamp, sensor id/type/name/path and numeric values.

## Sensors we care about most

Availability depends on the machine/EC support.

Useful examples include:

- CPU Package temperature
- CPU Package power
- individual core temperatures
- CPU clocks
- CPU load
- fan RPM
- GPU hotspot
- SSD/NVMe temperatures
- battery / motherboard sensors
- throttling indicators when LibreHardwareMonitor exposes them

## Troubleshooting

### Connection refused

LibreHardwareMonitor is either not running or its web server is disabled.

### Web UI works but script does not

Check `config/monitor.json` and make sure `lhm_base_url` matches the listener address/port.

### No fan RPM

Some laptops do not expose embedded-controller fan sensors to LibreHardwareMonitor. The rest of the telemetry is still useful.

### Security

Do not expose this endpoint to the Internet. Localhost is preferred.

LibreHardwareMonitor's web API also supports sensor-control requests in the application, but this repository intentionally never calls them.
