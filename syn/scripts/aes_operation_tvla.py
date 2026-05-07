#!/usr/bin/env python3

import numpy as np
import matplotlib.pyplot as plt
from scipy.interpolate import interp1d
import sys
import glob
import concurrent.futures
import os

def process_trace_file(filename, start_time, encryption_duration, common_time_axis, label, max_traces=None):
    n = 0
    mean = np.zeros_like(common_time_axis, dtype=np.float64)
    m2 = np.zeros_like(common_time_axis, dtype=np.float64)

    current_start = start_time
    current_end = start_time + encryption_duration

    times = []
    values = []
    last_resampled = None

    current_time = None
    current_sum = 0.0

    try:
        with open(filename, 'r') as f:
            for line in f:
                line = line.strip()

                if not line or line.startswith(';') or line.startswith('.'):
                    continue

                parts = line.split()

                # We hit a new timestamp
                if len(parts) == 1 and parts[0].isdigit():
                    new_time = int(parts[0])

                    # Save the fully summed values from the previous timestamp
                    if current_time is not None:
                        times.append(current_time)
                        values.append(current_sum)

                    # Check if the new time crosses into the next cycle
                    while new_time > current_end:
                        trace_processed = False
                        just_processed_real_data = False

                        if len(times) > 1:
                            t_arr = np.array(times)
                            v_arr = np.array(values)

                            last_t_carry = t_arr[-1]
                            last_v_carry = v_arr[-1]

                            t_rel = t_arr - current_start
                            t_rel_unique, unique_indices = np.unique(t_rel, return_index=True)
                            v_unique = v_arr[unique_indices]

                            if len(t_rel_unique) > 1:
                                # Safe interpolation that stops Not A Number errors
                                func = interp1d(
                                    t_rel_unique, 
                                    v_unique, 
                                    kind='previous', 
                                    fill_value=(v_unique[0], v_unique[-1]), 
                                    bounds_error=False
                                )
                                resampled = func(common_time_axis)
                                last_resampled = resampled.copy()
                                trace_processed = True
                                just_processed_real_data = True
                                
                        elif last_resampled is not None:
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

                        # Reset the buffer for the next trace
                        if just_processed_real_data:
                            times = [last_t_carry]
                            values = [last_v_carry]
                        else:
                            times = []
                            values = []

                    if max_traces is not None and n >= max_traces:
                        break

                    current_time = new_time
                    current_sum = 0.0

                # Accumulate values for all nodes at the current timestamp
                elif len(parts) >= 2 and current_time is not None:
                    try:
                        current_sum += float(parts[1])
                    except ValueError:
                        pass

        # Save the very last time entry when the file ends
        if current_time is not None:
            times.append(current_time)
            values.append(current_sum)

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
    cycles_per_encryption = 99 ;#49
    encryption_duration = cycle_duration * cycles_per_encryption
    start_time = 90 * 1000
    resample_dt = 1

    common_time_axis = np.arange(0, encryption_duration, resample_dt)

    WORKAREA = os.environ.get('WORKAREA')
    DESIGN_VER = os.environ.get('DESIGN_VER')
    SYN_RES = f'{WORKAREA}/syn/results/{DESIGN_VER}'

    if DESIGN_VER:
        print(f"DESIGN_VER : {DESIGN_VER}")
    else:
        print("DESIGN_VER is not set!")

    '''
    split -n 16 -d {SYN_RES}/tvla_dynamic/tvla_traces.out ../results/aes_operation_sca_MODE128_10p0ns/tvla_dynamic/chunk_
    split -n 16 -d {SYN_RES}/tvla_static/tvla_traces.out ../results/aes_operation_sca_MODE128_10p0ns/tvla_static/chunk_
    '''
    # nproc OR lscpu

    print("Running in FULL CHUNK mode...")
    dynamic_files = glob.glob(f'{SYN_RES}/tvla_dynamic/chunk_*')
    static_files = glob.glob(f'{SYN_RES}/tvla_static/chunk_*')
    max_traces_per_file = None
    cpu_cores = 16

    output_filename = f'{WORKAREA}/syn/{DESIGN_VER}_tvla_analysis.png'

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
    time_axis_ns = common_time_axis / 1000.0

    print("Generating plot...")
    plt.figure(figsize=(10, 6))
    plt.plot(time_axis_ns, t_stats, label='t value', linewidth=0.5)
    
    plt.axhline(4.5, color='red', linestyle='--', alpha=0.7, label='Threshold (+4.5)')
    plt.axhline(-4.5, color='red', linestyle='--', alpha=0.7, label='Threshold (-4.5)')

    plt.title(f'TVLA Analysis Results for {DESIGN_VER}')
    plt.xlabel('Time (ns)')
    plt.ylabel('t value')
    plt.legend()
    plt.grid(True, alpha=0.3)

    plt.savefig(output_filename, dpi=300)

    max_t = np.max(np.abs(t_stats))
    if max_t > 4.5:
        print(f"FAILURE: Potential leakage detected! Max T value: {max_t:.4f}")
    else:
        print(f"PASS: No significant leakage detected. Max T value: {max_t:.4f}")

    print(f"Success! Plot saved to: {output_filename}")

if __name__ == "__main__":
    perform_tvla()
