# Gigabyte G5 MF Thermal / Noise Test Plan

The purpose is to determine whether excessive noise comes primarily from:

1. unnecessary power consumption,
2. external-monitor / dGPU behaviour,
3. fan-control policy,
4. poor airflow,
5. poor heatsink / thermal-interface contact,
6. genuinely high CPU/GPU workload.

## Ground rules

- Keep room conditions approximately similar.
- Do one configuration change per session.
- Keep the laptop in the same physical position unless position is the variable.
- Use at least 8–10 minutes for idle sessions.
- For gaming tests, use the same game, scene/settings and roughly the same duration.
- Do not compare temperatures without comparing power draw.

## Test A — normal idle baseline

Normal workstation setup:

- charger connected
- cooling pad as normally used
- external monitor connected
- usual peripherals connected
- normal Windows/Gigabyte profile

```powershell
.\scripts\start-session.ps1 -Label "idle-normal-setup"
```

Do nothing for 10 minutes.

## Test B — external monitor removed

Disconnect the external monitor physically.

```powershell
.\scripts\start-session.ps1 -Label "idle-monitor-disconnected"
```

Compare GPU power, P-state, graphics/memory clocks, temperature, and fan behaviour.

A large reduction in idle GPU power strongly implicates display routing or dGPU wakefulness.

## Test C — Windows Balanced

Set Windows power mode to Balanced.

```powershell
.\scripts\start-session.ps1 -Label "idle-windows-balanced"
```

## Test D — Gigabyte Entertainment / balanced-like profile

Change only the Gigabyte performance profile.

```powershell
.\scripts\start-session.ps1 -Label "idle-gigabyte-entertainment"
```

## Test E — temporary CPU boost experiment

Temporarily test with processor boost disabled or reduced using a reversible Windows power configuration.

```powershell
.\scripts\start-session.ps1 -Label "idle-cpu-boost-disabled"
```

If fan behaviour changes dramatically while ordinary desktop responsiveness remains acceptable, CPU boost policy is likely a major contributor.

## Test F — passive elevation

Turn cooling-pad fans off but leave the laptop elevated.

```powershell
.\scripts\start-session.ps1 -Label "idle-pad-off-raised"
```

## Test G — cooling pad enabled

Same physical position, pad fans on.

```powershell
.\scripts\start-session.ps1 -Label "idle-pad-on"
```

The F/G difference estimates the cooling pad's contribution beyond simple elevation.

## Gaming baseline

Use a repeatable game and preferably a fixed FPS target.

```powershell
.\scripts\start-session.ps1 -Label "game-baseline"
```

Then repeat with exactly one change, for example:

```powershell
.\scripts\start-session.ps1 -Label "game-90fps-cap"
```

## Optional HWiNFO capture

Log HWiNFO sensors during the same experiment and save the result as:

```text
<session>\hwinfo.csv
```

Especially useful HWiNFO metrics:

- CPU Package Temperature
- CPU Package Power
- Core temperatures
- Core Effective Clocks
- Thermal Throttling
- Power Limit Exceeded
- GPU temperature / hotspot
- fan RPM
- SSD temperatures

## Interpretation

### Possible software / power issue

Typical pattern:

- low foreground workload
- unexpectedly high CPU utilization
- or GPU utilization near zero while GPU power remains meaningfully elevated

Inspect `processes.csv`, display routing, refresh rate, browser/Electron acceleration and power profiles.

### Possible cooling/contact issue

Typical pattern:

- high temperature at surprisingly low package/board power
- especially if the other chip stays relatively cool while dissipating more power

Inspect airflow, fan behaviour, heatsink mounting pressure, thermal pads/TIM and fin-stack cleanliness.

### Likely normal thermal saturation

Typical pattern under gaming:

- high CPU/GPU power
- temperature rises proportionally
- performance is stable

Reduce generated heat with FPS caps, power limits, GPU undervolting or CPU boost policy, or improve external airflow.
