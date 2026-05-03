#!/usr/bin/env python3

import numpy as np
import matplotlib.pyplot as plt
from scipy.interpolate import interp1d
import sys
import glob
import concurrent.futures

def process_trace_file(filename, start_time, encryption_duration, common_time_axis, label, max_traces=None):
    n = 0
    mean = np.zeros_like(common_time_axis, dtype=np.float64)
    m2 = np.zeros_like(common_time_axis, dtype=np.float64)

    current_start = start_time
    current_end = start_time + encryption_duration

    times = []
    values = []
    last_resampled = None  # Holds the data from the previous cycle

    try:
        with open(filename, 'r') as f:
            current_time = None
            for line in f:
                line = line.strip()

                if not line or line.startswith(';') or line.startswith('.'):
                    continue

                parts = line.split()

                if len(parts) == 1 and parts[0].isdigit():
                    current_time = int(parts[0])

                    while current_time > current_end:
                        trace_processed = False
                        just_processed_real_data = False

                        if len(times) > 1:
                            # We have actual data for this time window
                            t_arr = np.array(times)
                            v_arr = np.array(values)

                            last_t_carry = t_arr[-1]
                            last_v_carry = v_arr[-1]

                            t_rel = t_arr - current_start
                            t_rel_unique, unique_indices = np.unique(t_rel, return_index=True)
                            v_unique = v_arr[unique_indices]

                            if len(t_rel_unique) > 1:
                                func = interp1d(t_rel_unique, v_unique, kind='previous', fill_value="extrapolate", bounds_error=False)
                                resampled = func(common_time_axis)
                                last_resampled = resampled.copy() # Save it for the future
                                trace_processed = True
                                just_processed_real_data = True
                                
                        elif last_resampled is not None:
                            # NO data in this window! Copy the previous cycle.
                            resampled = last_resampled
                            trace_processed = True

                        if trace_processed:
                            n += 1
                            
                            if max_traces is not None and n % 50 == 0:
                                percent = int((n / max_traces) * 100)
                                print(f"[{label}] Trace status: {n}/{max_traces} [{percent}%]")

                            delta = resampled - mean
                            mean += delta / n
                            delta2 = resampled - mean
                            m2 += delta * delta2

                        if max_traces is not None and n >= max_traces:
                            break

                        current_start += encryption_duration
                        current_end += encryption_duration

                        # Only reset the buffer if we actually consumed real data
                        if just_processed_real_data:
                            times = [last_t_carry]
                            values = [last_v_carry]

                    if max_traces is not None and n >= max_traces:
                        break

                elif len(parts) >= 2 and current_time is not None:
                    try:
                        times.append(current_time)
                        values.append(float(parts[1]))
                        current_time = None
                    except ValueError:
                        pass

        # EOF CHECK: If the file ended early, pad it out by copying the last trace
        if max_traces is not None and n < max_traces and last_resampled is not None:
            print(f"\n[{label}] EOF reached at {n} traces. Padding missing cycles up to {max_traces}...")
            while n < max_traces:
                n += 1
                if n % 50 == 0:
                    percent = int((n / max_traces) * 100)
                    print(f"[{label}] Trace status: {n}/{max_traces} [{percent}%]")
                
                delta = last_resampled - mean
                mean += delta / n
                delta2 = last_resampled - mean
                m2 += delta * delta2

    except FileNotFoundError:
        print(f"Error: File '{filename}' not found.")
        return mean, m2, 0
    except Exception as e:
        print(f"[{label}] Error processing file: {e}")
        pass

    return mean, m2, n

def merge_results(results_list):
    total_n = 0
    total_mean = None
    total_m2 = None

    for mean, m2, n in results_list:
        if n == 0:
            continue
            
        if total_n == 0:
            total_mean = mean.copy()
            total_m2 = m2.copy()
            total_n = n
        else:
            new_n = total_n + n
            delta = mean - total_mean
            
            total_mean += delta * (n / new_n)
            total_m2 += m2 + (delta ** 2) * (total_n * n / new_n)
            
            total_n = new_n

    if total_n < 2:
        return total_mean, np.zeros_like(total_mean) if total_mean is not None else None, total_n
        
    total_var = total_m2 / (total_n - 1)
    return total_mean, total_var, total_n

def perform_tvla():
    cycle_duration = 10 * 1000
    cycles_per_encryption = 49
    encryption_duration = cycle_duration * cycles_per_encryption
    start_time = 95 * 1000
    resample_dt = 1

    common_time_axis = np.arange(0, encryption_duration, resample_dt)

    # ==========================================
    # CHOOSE YOUR MODE HERE
    # ==========================================

    # MODE 1: QUICK TEST
    print("Running in QUICK TEST mode...")
    dynamic_files = ['../results/aes_operation_opt_MODE128_10p0ns/tvla_dynamic/tvla_traces.out']
    static_files = ['../results/aes_operation_opt_MODE128_10p0ns/tvla_static/tvla_traces.out']
    max_traces_per_file = 1000
    cpu_cores = 2

    # MODE 2: FULL CHUNK RUN
    # print("Running in FULL CHUNK mode...")
    # dynamic_files = glob.glob('dynamic_chunks/*')
    # static_files = glob.glob('static_chunks/*')
    # max_traces_per_file = None
    # cpu_cores = 8

    # ==========================================

    print(f"Found {len(dynamic_files)} random files and {len(static_files)} fixed files.")

    dynamic_results = []
    with concurrent.futures.ProcessPoolExecutor(max_workers=cpu_cores) as executor:
        futures = []
        for f in dynamic_files:
            futures.append(executor.submit(process_trace_file, f, start_time, encryption_duration, common_time_axis, "RANDOM", max_traces_per_file))
        
        for i, future in enumerate(concurrent.futures.as_completed(futures)):
            dynamic_results.append(future.result())
            if len(dynamic_files) > 1:
                print(f"[RANDOM] Files progress: {i+1} out of {len(dynamic_files)} done", end='\r')
    if len(dynamic_files) > 1:
        print()

    static_results = []
    with concurrent.futures.ProcessPoolExecutor(max_workers=cpu_cores) as executor:
        futures = []
        for f in static_files:
            futures.append(executor.submit(process_trace_file, f, start_time, encryption_duration, common_time_axis, "FIXED ", max_traces_per_file))
        
        for i, future in enumerate(concurrent.futures.as_completed(futures)):
            static_results.append(future.result())
            if len(static_files) > 1:
                print(f"[FIXED ] Files progress: {i+1} out of {len(static_files)} done", end='\r')
    if len(static_files) > 1:
        print()

    print("Merging the math results...")
    mean_r, var_r, n_r = merge_results(dynamic_results)
    mean_f, var_f, n_f = merge_results(static_results)

    print(f"Total random traces found: {n_r}")
    print(f"Total fixed traces found: {n_f}")

    if n_r < 2 or n_f < 2:
        print("Error: Not enough traces found. Check your file locations.")
        sys.exit(1)

    print("Computing Welch t test...")
    t_stats = (mean_r - mean_f) / np.sqrt((var_r / n_r) + (var_f / n_f) + 1e-12)

    print("Generating plot...")
    plt.figure(figsize=(10, 6))
    plt.plot(common_time_axis, t_stats, label='t value', linewidth=1)

    plt.axhline(4.5, color='red', linestyle='--', alpha=0.7, label='Threshold (+4.5)')
    plt.axhline(-4.5, color='red', linestyle='--', alpha=0.7, label='Threshold (-4.5)')

    plt.title('TVLA Analysis Results')
    plt.xlabel('Time (ps)')
    plt.ylabel('t value')
    plt.legend()
    plt.grid(True, alpha=0.3)

    output_filename = 'tvla_analysis.png'
    plt.savefig(output_filename, dpi=150)

    max_t = np.max(np.abs(t_stats))
    if max_t > 4.5:
        print(f"FAILURE: Potential leakage detected! Max T value: {max_t:.4f}")
    else:
        print(f"PASS: No significant leakage detected. Max T value: {max_t:.4f}")

    print(f"Success! Plot saved to: {output_filename}")

if __name__ == "__main__":
    perform_tvla()
