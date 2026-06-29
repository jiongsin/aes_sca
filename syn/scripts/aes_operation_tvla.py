#!/usr/bin/env python3

# TVLA analysis script for AES operation PrimePower traces.
# Reads random and fixed trace files, resamples complete encryption windows, computes Welch t-statistics, reports leakage pass/fail status, and saves the TVLA plot.

import concurrent.futures
import math
import os
import sys
import time
from typing import Dict, List, Optional, Sequence, Tuple

import matplotlib.pyplot as plt
import numpy as np
from scipy.interpolate import interp1d

DEFAULT_TIME_RESOLUTION_PS = 100.0
TVLA_THRESHOLD = 4.5

def require_env(name: str) -> str:
    value = os.environ.get(name)
    if value is None or value == "":
        raise ValueError(f"{name} is not set")
    return value

def infer_flow(workarea: str) -> str:
    flow = os.environ.get("FLOW") or os.environ.get("TARGET_FLOW")
    if flow:
        flow = flow.lower()
        if flow not in {"syn", "pnr"}:
            raise ValueError("FLOW must be either 'syn' or 'pnr'")
        return flow

    cwd = os.path.abspath(os.getcwd())
    syn_scripts = os.path.abspath(os.path.join(workarea, "syn", "scripts"))
    pnr_scripts = os.path.abspath(os.path.join(workarea, "pnr", "scripts"))

    if cwd.startswith(pnr_scripts) or f"{os.sep}pnr{os.sep}" in cwd:
        return "pnr"
    if cwd.startswith(syn_scripts) or f"{os.sep}syn{os.sep}" in cwd:
        return "syn"

    return "syn"

def read_time_resolution_ps(filename: str) -> float:
    """Read .time_resolution from the header if present."""
    try:
        with open(filename, "rb") as f:
            for _ in range(2000):
                line = f.readline()
                if not line:
                    break
                stripped = line.strip()
                if stripped.startswith(b".time_resolution"):
                    parts = stripped.split()
                    if len(parts) >= 2:
                        return float(parts[1]) * 1000.0

                if stripped.isdigit():
                    break
    except FileNotFoundError:
        raise
    except Exception as exc:
        print(f"Warning: failed to read .time_resolution from {filename}: {exc}")
    return DEFAULT_TIME_RESOLUTION_PS

def update_online_stats(mean: np.ndarray, m2: np.ndarray, n: int, trace: np.ndarray):
    n += 1
    delta = trace - mean
    mean += delta / n
    delta2 = trace - mean
    m2 += delta * delta2
    return mean, m2, n

def resample_one_trace(
    window_times: Sequence[int],
    window_values: Sequence[float],
    trace_start_ps: int,
    encryption_duration_ps: int,
    common_time_axis_ps: np.ndarray,
):
    if len(window_times) < 2:
        return None

    t_arr = np.asarray(window_times, dtype=np.float64)
    v_arr = np.asarray(window_values, dtype=np.float64)
    trace_end_ps = trace_start_ps + encryption_duration_ps

    before_start = np.where(t_arr <= trace_start_ps)[0]
    if len(before_start) == 0:
        return None

    start_idx = before_start[-1]
    rel_times = [0.0]
    rel_values = [v_arr[start_idx]]

    inside = (t_arr > trace_start_ps) & (t_arr < trace_end_ps)
    rel_times.extend((t_arr[inside] - trace_start_ps).tolist())
    rel_values.extend(v_arr[inside].tolist())

    if len(rel_times) < 2:
        return None

    t_rel = np.asarray(rel_times, dtype=np.float64)
    v_rel = np.asarray(rel_values, dtype=np.float64)

    order = np.argsort(t_rel, kind="stable")
    t_rel = t_rel[order]
    v_rel = v_rel[order]

    _, reversed_first = np.unique(t_rel[::-1], return_index=True)
    last_indices = len(t_rel) - 1 - reversed_first
    last_indices = np.sort(last_indices)
    t_unique = t_rel[last_indices]
    v_unique = v_rel[last_indices]

    if len(t_unique) < 2 or t_unique[0] != 0.0:
        return None

    func = interp1d(
        t_unique,
        v_unique,
        kind="previous",
        bounds_error=False,
        fill_value=(v_unique[0], v_unique[-1]),
        assume_sorted=True,
    )
    return func(common_time_axis_ps)

def first_window_at_or_after(first_time_ps: int, start_time_ps: int, duration_ps: int) -> int:
    if first_time_ps <= start_time_ps:
        return start_time_ps
    k = math.ceil((first_time_ps - start_time_ps) / duration_ps)
    return start_time_ps + k * duration_ps

def process_completed_windows(
    *,
    times: List[int],
    values: List[float],
    current_start_ps: int,
    current_end_ps: int,
    encryption_duration_ps: int,
    common_time_axis_ps: np.ndarray,
    mean: np.ndarray,
    m2: np.ndarray,
    n: int,
    force_until_ps: int,
):
    """Process all windows whose end is at or before force_until_ps.

    Since this function is used on a whole file, there are no artificial byte
    boundaries. A window is skipped only if it genuinely lacks enough samples to
    resample it.
    """
    while force_until_ps >= current_end_ps:
        previous_t = None
        previous_v = None
        trace_times = []
        trace_values = []

        for t, v in zip(times, values):
            if t <= current_start_ps:
                previous_t = t
                previous_v = v
            elif t < current_end_ps:
                trace_times.append(t)
                trace_values.append(v)

        if previous_t is not None:
            trace_times.insert(0, previous_t)
            trace_values.insert(0, previous_v)

        resampled = resample_one_trace(
            trace_times,
            trace_values,
            current_start_ps,
            encryption_duration_ps,
            common_time_axis_ps,
        )
        if resampled is not None:
            mean, m2, n = update_online_stats(mean, m2, n, resampled)

        next_start_ps = current_start_ps + encryption_duration_ps
        next_end_ps = current_end_ps + encryption_duration_ps

        keep_from = 0
        for i, t in enumerate(times):
            if t <= next_start_ps:
                keep_from = i
            else:
                break
        times = times[keep_from:]
        values = values[keep_from:]

        current_start_ps = next_start_ps
        current_end_ps = next_end_ps

    return times, values, current_start_ps, current_end_ps, mean, m2, n

def is_timestamp_line(stripped: bytes) -> bool:
    return stripped.isdigit()

def process_whole_file(
    label: str,
    filename: str,
    time_resolution_ps: float,
    start_time_ps: int,
    encryption_duration_ps: int,
    common_time_axis_ps: np.ndarray,
):
    """Read one tvla_traces.out file from start to EOF in a single process."""
    mean = np.zeros_like(common_time_axis_ps, dtype=np.float64)
    m2 = np.zeros_like(common_time_axis_ps, dtype=np.float64)
    n = 0

    times: List[int] = []
    values: List[float] = []
    current_time: Optional[int] = None
    current_sum = 0.0
    parsed_first_time_ps: Optional[int] = None
    current_start_ps: Optional[int] = None
    current_end_ps: Optional[int] = None

    with open(filename, "rb", buffering=1024 * 1024) as f:
        for line in f:
            stripped = line.strip()
            if not stripped:
                continue
            if stripped.startswith(b";") or stripped.startswith(b"."):
                continue

            if is_timestamp_line(stripped):
                raw_time = int(stripped)
                new_time = int(round(raw_time * time_resolution_ps))

                if parsed_first_time_ps is None:
                    parsed_first_time_ps = new_time
                    current_start_ps = first_window_at_or_after(
                        parsed_first_time_ps,
                        start_time_ps,
                        encryption_duration_ps,
                    )
                    current_end_ps = current_start_ps + encryption_duration_ps

                if current_time is not None:
                    if new_time < current_time:
                        raise ValueError(
                            f"[{label}] timestamp went backwards in {filename}: "
                            f"previous={current_time}, new={new_time}"
                        )
                    times.append(current_time)
                    values.append(current_sum)

                    (
                        times,
                        values,
                        current_start_ps,
                        current_end_ps,
                        mean,
                        m2,
                        n,
                    ) = process_completed_windows(
                        times=times,
                        values=values,
                        current_start_ps=current_start_ps,
                        current_end_ps=current_end_ps,
                        encryption_duration_ps=encryption_duration_ps,
                        common_time_axis_ps=common_time_axis_ps,
                        mean=mean,
                        m2=m2,
                        n=n,
                        force_until_ps=new_time,
                    )

                current_time = new_time
                current_sum = 0.0
            else:

                if current_time is not None:
                    parts = stripped.split()
                    if len(parts) >= 2:
                        try:
                            current_sum += float(parts[1])
                        except ValueError:
                            pass

    if current_time is not None and current_start_ps is not None:
        times.append(current_time)
        values.append(current_sum)
        (
            times,
            values,
            current_start_ps,
            current_end_ps,
            mean,
            m2,
            n,
        ) = process_completed_windows(
            times=times,
            values=values,
            current_start_ps=current_start_ps,
            current_end_ps=current_end_ps,
            encryption_duration_ps=encryption_duration_ps,
            common_time_axis_ps=common_time_axis_ps,
            mean=mean,
            m2=m2,
            n=n,
            force_until_ps=current_time,
        )

    if n < 2:
        var = np.zeros_like(mean)
    else:
        var = m2 / (n - 1)

    return label, mean, var, n

def render_progress(done_by_label: Dict[str, int], traces_by_label: Dict[str, int], start_wall: float) -> None:
    elapsed = max(time.time() - start_wall, 1e-9)
    done = sum(done_by_label.values())
    rate = done / elapsed

    def one(label: str) -> str:
        status = "done" if done_by_label[label] else "running"
        return f"{label:6s} {status:7s} traces={traces_by_label[label]}"

    print(
        "\r"
        + one("RANDOM")
        + " | "
        + one("FIXED")
        + f" | files {done}/2 | {rate:.2f} files/s",
        end="",
        flush=True,
    )

def perform_tvla():
    ver = require_env("VER")
    mode = require_env("MODE")
    workarea = require_env("WORKAREA")
    design_ver = require_env("DESIGN_VER")
    flow = infer_flow(workarea)

    cycles_map = {
        "base": {"128": 19, "192": 23, "256": 27},
        "opt": {"128": 49, "192": 59, "256": 69},
        "sca": {"128": 99, "192": 119, "256": 139},
    }
    if ver not in cycles_map or mode not in cycles_map[ver]:
        raise ValueError(f"Unknown VER or MODE: VER={ver}, MODE={mode}")

    cycles_per_encryption = cycles_map[ver][mode]
    clock_period_ps = int(round(float(os.environ.get("PERIOD", "10.0")) * 1000.0))
    encryption_duration_ps = clock_period_ps * cycles_per_encryption
    start_time_ps = int(os.environ.get("TVLA_START_PS", "90000"))
    resample_dt_ps = int(os.environ.get("TVLA_RESAMPLE_DT_PS", "100"))
    common_time_axis_ps = np.arange(0, encryption_duration_ps, resample_dt_ps)

    result_root = os.path.join(workarea, flow, "results", design_ver)
    dynamic_file = os.path.join(result_root, "tvla_dynamic", "tvla_traces.out")
    static_file = os.path.join(result_root, "tvla_static", "tvla_traces.out")

    for path in (dynamic_file, static_file):
        if not os.path.exists(path):
            print(f"Error: waveform not found: {path}")
            sys.exit(1)

    total_workers = int(os.environ.get("TVLA_TOTAL_WORKERS", "2"))
    if total_workers < 2:
        print("Warning: TVLA_TOTAL_WORKERS < 2. Dynamic and static files will run serially.")

    print(f"DESIGN_VER             : {design_ver}")
    print(f"FLOW                   : {flow}")
    print(f"cycles_per_encryption  : {cycles_per_encryption}")
    print(f"clock_period           : {clock_period_ps} ps")
    print(f"start_time             : {start_time_ps} ps")
    print(f"encryption_duration    : {encryption_duration_ps} ps")
    print(f"samples per trace      : {len(common_time_axis_ps)}")
    print(f"total workers          : {total_workers}")
    print("byte ranges per file   : 1  # disabled; each file is read once from start to EOF")
    print(f"Random/dynamic waveform: {dynamic_file}")
    print(f"Fixed/static waveform  : {static_file}")

    dynamic_time_res = read_time_resolution_ps(dynamic_file)
    static_time_res = read_time_resolution_ps(static_file)
    print(f"Dynamic time resolution: {dynamic_time_res} ps")
    print(f"Static time resolution : {static_time_res} ps")

    jobs = [
        ("RANDOM", dynamic_file, dynamic_time_res),
        ("FIXED", static_file, static_time_res),
    ]

    print("\nProcessing dynamic and static files in parallel...")
    print("Each file is read by one process; no byte-range splitting is used.\n")

    done_by_label = {"RANDOM": 0, "FIXED": 0}
    traces_by_label = {"RANDOM": 0, "FIXED": 0}
    results = {}
    start_wall = time.time()
    render_progress(done_by_label, traces_by_label, start_wall)

    with concurrent.futures.ProcessPoolExecutor(max_workers=total_workers) as executor:
        futures = [
            executor.submit(
                process_whole_file,
                label,
                filename,
                time_res,
                start_time_ps,
                encryption_duration_ps,
                common_time_axis_ps,
            )
            for label, filename, time_res in jobs
        ]

        for future in concurrent.futures.as_completed(futures):
            label, mean, var, n = future.result()
            results[label] = (mean, var, n)
            done_by_label[label] = 1
            traces_by_label[label] = n
            render_progress(done_by_label, traces_by_label, start_wall)

    print("\n")

    mean_r, var_r, n_r = results["RANDOM"]
    mean_f, var_f, n_f = results["FIXED"]

    print(f"Total random traces found: {n_r}")
    print(f"Total fixed traces found : {n_f}")

    if n_r < 2 or n_f < 2:
        print("Error: not enough complete traces found. Check TVLA_START_PS, PERIOD, VER, and MODE.")
        sys.exit(1)

    denominator = np.sqrt((var_r / n_r) + (var_f / n_f))
    t_stats = np.divide(
        mean_r - mean_f,
        denominator,
        out=np.zeros_like(mean_r),
        where=denominator > 0,
    )

    time_axis_ns = common_time_axis_ps / 1000.0
    base_output = os.path.join(result_root, f"{design_ver}_{flow}_tvla_analysis")
    output_filename = f"{base_output}.png"
    counter = 1
    while os.path.exists(output_filename):
        output_filename = f"{base_output}_{counter}.png"
        counter += 1

    plt.figure(figsize=(10, 6))
    plt.plot(time_axis_ns, t_stats, label="t value", linewidth=0.5)
    plt.axhline(TVLA_THRESHOLD, color="red", linestyle="--", alpha=0.7, label="Threshold (+4.5)")
    plt.axhline(-TVLA_THRESHOLD, color="red", linestyle="--", alpha=0.7, label="Threshold (-4.5)")
    plt.title(f"TVLA Analysis Results for {design_ver} ({flow})")
    plt.xlabel("Time (ns)")
    plt.ylabel("t value")
    plt.legend()
    plt.grid(True, alpha=0.3)
    plt.tight_layout()
    plt.savefig(output_filename, dpi=300)

    max_t = float(np.max(np.abs(t_stats)))
    if max_t > TVLA_THRESHOLD:
        print(f"FAILURE: Potential leakage detected! Max T value: {max_t:.4f}")
    else:
        print(f"PASS: No significant leakage detected. Max T value: {max_t:.4f}")
    print(f"Success! Plot saved to: {output_filename}")

if __name__ == "__main__":
    perform_tvla()

