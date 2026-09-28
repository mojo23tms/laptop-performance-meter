from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd


def numeric(series: pd.Series) -> pd.Series:
    if series is None:
        return pd.Series(dtype=float)
    return pd.to_numeric(
        series.astype(str).str.replace(",", ".", regex=False),
        errors="coerce",
    )


def stats(series: pd.Series) -> dict:
    s = numeric(series).dropna()
    if s.empty:
        return {}
    return {
        "count": int(s.count()),
        "mean": round(float(s.mean()), 2),
        "median": round(float(s.median()), 2),
        "p95": round(float(s.quantile(0.95)), 2),
        "max": round(float(s.max()), 2),
        "min": round(float(s.min()), 2),
    }


def add_chart(df: pd.DataFrame, x: str, y: str, title: str, out: Path) -> None:
    if y not in df.columns:
        return
    yy = numeric(df[y])
    if yy.dropna().empty:
        return

    plt.figure(figsize=(12, 4))
    plt.plot(pd.to_datetime(df[x], errors="coerce"), yy)
    plt.title(title)
    plt.xlabel("Time")
    plt.ylabel(y)
    plt.tight_layout()
    plt.savefig(out, dpi=140)
    plt.close()


def load_hwinfo(path: Path) -> pd.DataFrame | None:
    if not path.exists():
        return None

    attempts = [
        {"encoding": "utf-8-sig"},
        {"encoding": "utf-8"},
        {"encoding": "cp1252"},
    ]

    for kwargs in attempts:
        try:
            df = pd.read_csv(path, **kwargs)
            if len(df.columns) > 2:
                return df
        except Exception:
            pass

    for kwargs in attempts:
        try:
            df = pd.read_csv(path, sep=";", **kwargs)
            if len(df.columns) > 2:
                return df
        except Exception:
            pass

    return None


def find_hwinfo_interesting_columns(df: pd.DataFrame) -> list[str]:
    patterns = [
        r"cpu.*package.*temp",
        r"cpu.*package.*power",
        r"core.*temper",
        r"thermal.*thrott",
        r"power.*limit",
        r"fan",
        r"ssd.*temp",
        r"drive.*temp",
        r"gpu.*hot.*spot",
    ]
    result = []
    for column in df.columns:
        value = str(column).lower()
        if any(re.search(pattern, value) for pattern in patterns):
            result.append(str(column))
    return result[:80]



def summarize_lhm_long(path: Path) -> dict:
    if not path.exists():
        return {}

    try:
        df = pd.read_csv(path)
    except Exception:
        return {}

    required = {"sensor_type", "name", "path", "value"}
    if not required.issubset(df.columns):
        return {}

    df["value"] = numeric(df["value"])
    df = df.dropna(subset=["value"])
    if df.empty:
        return {}

    def choose(patterns: list[str]) -> list[dict]:
        mask = pd.Series(False, index=df.index)
        text = (df["path"].fillna("") + " " + df["name"].fillna("")).str.lower()
        for pattern in patterns:
            mask = mask | text.str.contains(pattern, regex=True)

        rows = []
        for key, group in df[mask].groupby(["path", "sensor_type"], dropna=False):
            st = stats(group["value"])
            if st:
                rows.append({
                    "path": key[0],
                    "sensor_type": key[1],
                    **st,
                })
        return rows

    return {
        "cpu_package_temperature": choose([
            r"cpu package",
            r"package.*temperature",
        ]),
        "cpu_package_power": choose([
            r"cpu package.*power",
            r"package power",
            r"cpu.*package power",
        ]),
        "fans": choose([
            r"fan",
        ]),
        "cpu_temperatures": choose([
            r"cpu.*temperature",
            r"core.*temperature",
            r"core temp",
        ]),
        "storage_temperatures": choose([
            r"ssd.*temperature",
            r"nvme.*temperature",
            r"drive.*temperature",
        ]),
    }

def analyse(session: Path) -> dict:
    system_path = session / "system.csv"
    if not system_path.exists():
        raise SystemExit(f"Missing {system_path}")

    df = pd.read_csv(system_path)
    if "timestamp" not in df.columns:
        raise SystemExit("system.csv does not contain timestamp")

    df["timestamp"] = pd.to_datetime(df["timestamp"], errors="coerce")

    metrics = {}
    for column in [
        "cpu_total_pct",
        "memory_used_pct",
        "gpu_util_pct",
        "gpu_mem_util_pct",
        "gpu_temp_c",
        "gpu_power_w",
        "gpu_clock_mhz",
        "gpu_mem_clock_mhz",
        "gpu_mem_used_mb",
    ]:
        if column in df.columns:
            metrics[column] = stats(df[column])

    config_path = session.parent.parent / "config" / "monitor.json"
    config = {}
    if config_path.exists():
        config = json.loads(config_path.read_text(encoding="utf-8"))

    flags = []

    gpu_util = numeric(df.get("gpu_util_pct", pd.Series(dtype=float)))
    gpu_power = numeric(df.get("gpu_power_w", pd.Series(dtype=float)))
    gpu_temp = numeric(df.get("gpu_temp_c", pd.Series(dtype=float)))
    cpu = numeric(df.get("cpu_total_pct", pd.Series(dtype=float)))

    idle_util_threshold = float(config.get("gpu_idle_utilization_threshold_pct", 5))
    idle_power_warning = float(config.get("gpu_idle_power_warning_w", 12))
    gpu_hot_warning = float(config.get("gpu_hot_warning_c", 80))
    cpu_busy_warning = float(config.get("cpu_busy_warning_pct", 20))

    valid = gpu_util.notna() & gpu_power.notna()
    if valid.any():
        idle_gpu = valid & (gpu_util <= idle_util_threshold)
        if idle_gpu.any():
            idle_power_mean = float(gpu_power[idle_gpu].mean())
            idle_power_p95 = float(gpu_power[idle_gpu].quantile(0.95))
            if idle_power_mean >= idle_power_warning:
                flags.append({
                    "severity": "warning",
                    "code": "GPU_IDLE_POWER",
                    "message": (
                        f"GPU averaged {idle_power_mean:.1f} W while utilization was "
                        f"<= {idle_util_threshold:.0f}% (p95 {idle_power_p95:.1f} W). "
                        "Investigate external-display routing, refresh rate, hardware acceleration "
                        "and applications preventing the dGPU from sleeping."
                    ),
                })

    if gpu_temp.notna().any() and float(gpu_temp.quantile(0.95)) >= gpu_hot_warning:
        flags.append({
            "severity": "info",
            "code": "GPU_HOT",
            "message": (
                f"GPU temperature p95 is {float(gpu_temp.quantile(0.95)):.1f} C. "
                "Interpret this together with GPU power draw rather than temperature alone."
            ),
        })

    if cpu.notna().any() and float(cpu.mean()) >= cpu_busy_warning:
        flags.append({
            "severity": "warning",
            "code": "CPU_BACKGROUND_LOAD",
            "message": (
                f"Average Windows CPU utilization was {float(cpu.mean()):.1f}%. "
                "Review processes.csv before blaming the cooling system."
            ),
        })

    low_power_hot = (
        gpu_temp.notna()
        & gpu_power.notna()
        & (gpu_temp >= 75)
        & (gpu_power <= 25)
    )

    if low_power_hot.sum() >= 3:
        flags.append({
            "severity": "warning",
            "code": "GPU_HOT_AT_LOW_POWER",
            "message": (
                f"Found {int(low_power_hot.sum())} samples with GPU >=75 C at <=25 W. "
                "If sustained, inspect airflow, fan behaviour, heatsink contact and thermal interface."
            ),
        })

    process_summary = []
    process_file = session / "processes.csv"
    if process_file.exists():
        process_df = pd.read_csv(process_file)
        if "cpu_pct_approx" in process_df.columns and "process" in process_df.columns:
            process_df["cpu_pct_approx"] = numeric(process_df["cpu_pct_approx"])
            grouped = (
                process_df.groupby("process", as_index=False)["cpu_pct_approx"]
                .mean()
                .sort_values("cpu_pct_approx", ascending=False)
                .head(15)
            )
            process_summary = grouped.to_dict(orient="records")

    lhm_summary = summarize_lhm_long(session / "lhm.csv")

    hwinfo_summary = {}
    hwinfo_path = session / "hwinfo.csv"
    hwinfo = load_hwinfo(hwinfo_path)
    if hwinfo is not None:
        for column in find_hwinfo_interesting_columns(hwinfo):
            column_stats = stats(hwinfo[column])
            if column_stats:
                hwinfo_summary[column] = column_stats

    duration_seconds = None
    valid_timestamps = df["timestamp"].dropna()
    if len(valid_timestamps) >= 2:
        duration_seconds = round(
            (valid_timestamps.max() - valid_timestamps.min()).total_seconds(),
            1,
        )

    result = {
        "session": session.name,
        "samples": int(len(df)),
        "duration_seconds": duration_seconds,
        "metrics": metrics,
        "flags": flags,
        "top_processes_by_average_cpu": process_summary,
        "lhm_detected": bool(lhm_summary),
        "lhm_summary": lhm_summary,
        "hwinfo_detected": hwinfo is not None,
        "hwinfo_interesting_metrics": hwinfo_summary,
    }

    (session / "summary.json").write_text(
        json.dumps(result, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )

    charts = session / "charts"
    charts.mkdir(exist_ok=True)
    add_chart(df, "timestamp", "cpu_total_pct", "CPU utilization", charts / "cpu-util.png")
    add_chart(df, "timestamp", "gpu_util_pct", "GPU utilization", charts / "gpu-util.png")
    add_chart(df, "timestamp", "gpu_power_w", "GPU power", charts / "gpu-power.png")
    add_chart(df, "timestamp", "gpu_temp_c", "GPU temperature", charts / "gpu-temp.png")
    add_chart(df, "timestamp", "gpu_clock_mhz", "GPU graphics clock", charts / "gpu-clock.png")

    lines = [
        f"# Thermal session report — {session.name}",
        "",
        f"- Samples: **{result['samples']}**",
        f"- Duration: **{duration_seconds if duration_seconds is not None else 'unknown'} s**",
        f"- LibreHardwareMonitor data detected: **{'yes' if lhm_summary else 'no'}**",
        f"- HWiNFO CSV detected: **{'yes' if hwinfo is not None else 'no'}**",
        "",
        "## Core telemetry",
        "",
        "| Metric | Mean | Median | P95 | Max |",
        "|---|---:|---:|---:|---:|",
    ]

    for name, metric_stats in metrics.items():
        if metric_stats:
            lines.append(
                f"| {name} | {metric_stats.get('mean', '')} | "
                f"{metric_stats.get('median', '')} | "
                f"{metric_stats.get('p95', '')} | "
                f"{metric_stats.get('max', '')} |"
            )

    lines += ["", "## Diagnostic flags", ""]
    if flags:
        for flag in flags:
            lines.append(f"- **{flag['code']}** — {flag['message']}")
    else:
        lines.append("- No heuristic warning conditions triggered.")

    lines += ["", "## Top processes by average sampled CPU", ""]
    if process_summary:
        lines += [
            "| Process | Approx. sampled CPU % |",
            "|---|---:|",
        ]
        for row in process_summary[:10]:
            lines.append(f"| {row['process']} | {row['cpu_pct_approx']:.2f} |")
    else:
        lines.append("- No process data available.")

    if lhm_summary:
        lines += ["", "## LibreHardwareMonitor highlights", ""]
        for section, rows in lhm_summary.items():
            if not rows:
                continue
            lines += [f"### {section.replace('_', ' ').title()}", ""]
            for row in rows[:12]:
                lines.append(
                    f"- **{row['path']}** ({row['sensor_type']}): "
                    f"mean {row['mean']}, p95 {row['p95']}, max {row['max']}"
                )
            lines.append("")

    if hwinfo_summary:
        lines += ["", "## HWiNFO interesting metrics", ""]
        for name, metric_stats in list(hwinfo_summary.items())[:30]:
            lines.append(
                f"- **{name}**: mean {metric_stats['mean']}, "
                f"p95 {metric_stats['p95']}, max {metric_stats['max']}"
            )

    lines += [
        "",
        "## Interpretation reminder",
        "",
        "Temperature without power draw is incomplete evidence.",
        "",
        "- High temperature + high power may be normal thermal saturation.",
        "- High temperature + low power is more suspicious for airflow/contact/TIM problems.",
        "- Elevated GPU power at very low GPU utilization can indicate the dGPU is being kept awake.",
        "",
        "Compare this session only against sessions where one configuration variable was changed.",
    ]

    (session / "report.md").write_text("\n".join(lines), encoding="utf-8")
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("session", type=Path)
    args = parser.parse_args()

    result = analyse(args.session.resolve())
    print(json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
