#!/usr/bin/env python3

'''import numpy as np
import matplotlib.pyplot as plt
from scipy.interpolate import interp1d
import sys
import glob
import concurrent.futures

def process_one_file(filename, start_time, encryption_duration, common_time_axis):
    n = 0
    mean = np.zeros_like(common_time_axis, dtype=np.float64)
    m2 = np.zeros_like(common_time_axis, dtype=np.float64)

    current_start = start_time
    current_end = start_time + encryption_duration

    times = []
    values = []
    last_t = None
    last_v = None

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
                        if len(times) > 1:
                            t_arr = np.array(times)
                            v_arr = np.array(values)

                            last_t = t_arr[-1]
                            last_v = v_arr[-1]

                            t_rel = t_arr - current_start
                            t_rel_unique, unique_indices = np.unique(t_rel, return_index=True)
                            v_unique = v_arr[unique_indices]

                            if len(t_rel_unique) > 1:
                                func = interp1d(t_rel_unique, v_unique, kind='previous', fill_value="extrapolate", bounds_error=False)
                                resampled = func(common_time_axis)

                                n += 1
                                delta = resampled - mean
                                mean += delta / n
                                delta2 = resampled - mean
                                m2 += delta * delta2

                        current_start += encryption_duration
                        current_end += encryption_duration

                        if last_t is not None:
                            times = [last_t]
                            values = [last_v]
                        else:
                            times = []
                            values = []

                elif len(parts) >= 2 and current_time is not None:
                    try:
                        times.append(current_time)
                        values.append(float(parts[1]))
                        current_time = None
                    except ValueError:
                        pass
    except Exception:
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
        return total_mean, np.zeros_like(total_mean), total_n
        
    total_var = total_m2 / (total_n - 1)
    return total_mean, total_var, total_n

def perform_tvla():
    dynamic_folder = 'dynamic_chunks/*'
    static_folder = 'static_chunks/*'

    dynamic_files = glob.glob(dynamic_folder)
    static_files = glob.glob(static_folder)

    cycle_duration = 10000
    cycles_per_encryption = 49
    encryption_duration = cycle_duration * cycles_per_encryption
    start_time = 0
    resample_dt = 1

    common_time_axis = np.arange(0, encryption_duration, resample_dt)

    print(f"Found {len(dynamic_files)} random files and {len(static_files)} fixed files.")
    print("Starting 8 CPU cores to read files...")

    dynamic_results = []
    with concurrent.futures.ProcessPoolExecutor(max_workers=8) as executor:
        futures = []
        for f in dynamic_files:
            futures.append(executor.submit(process_one_file, f, start_time, encryption_duration, common_time_axis))
        
        for i, future in enumerate(concurrent.futures.as_completed(futures)):
            dynamic_results.append(future.result())
            print(f"Random files progress: {i+1} out of {len(dynamic_files)} done", end='\r')
    print()

    static_results = []
    with concurrent.futures.ProcessPoolExecutor(max_workers=8) as executor:
        futures = []
        for f in static_files:
            futures.append(executor.submit(process_one_file, f, start_time, encryption_duration, common_time_axis))
        
        for i, future in enumerate(concurrent.futures.as_completed(futures)):
            static_results.append(future.result())
            print(f"Fixed files progress: {i+1} out of {len(static_files)} done", end='\r')
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
    perform_tvla()'''


import numpy as np
import matplotlib.pyplot as plt
from scipy.interpolate import interp1d
import sys
import concurrent.futures

def compute_stats(filename, start_time, encryption_duration, sample_size, common_time_axis, label):
    n = 0
    mean = np.zeros_like(common_time_axis, dtype=np.float64)
    m2 = np.zeros_like(common_time_axis, dtype=np.float64)

    current_start = start_time
    current_end = start_time + encryption_duration

    times = []
    values = []
    last_t = None
    last_v = None

    print(f"[{label}] Reading and processing started...")

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
                        if len(times) > 1:
                            t_arr = np.array(times)
                            v_arr = np.array(values)

                            last_t = t_arr[-1]
                            last_v = v_arr[-1]

                            t_rel = t_arr - current_start
                            t_rel_unique, unique_indices = np.unique(t_rel, return_index=True)
                            v_unique = v_arr[unique_indices]

                            if len(t_rel_unique) > 1:
                                func = interp1d(t_rel_unique, v_unique, kind='previous', fill_value="extrapolate", bounds_error=False)
                                resampled = func(common_time_axis)
                            elif len(t_rel_unique) == 1:
                                resampled = np.full_like(common_time_axis, v_unique[0])
                            else:
                                resampled = np.zeros_like(common_time_axis)
                        else:
                            # If there are no new events in this cycle, 
                            # the power is just a flat line of the last known value
                            if last_v is not None:
                                resampled = np.full_like(common_time_axis, last_v)
                            else:
                                resampled = np.zeros_like(common_time_axis)

                        n += 1
                        
                        if n % 50 == 0:
                            percent = int((n / sample_size) * 100)
                            print(f"[{label}] Trace status: {n}/{sample_size} [{percent}%]")

                        delta = resampled - mean
                        mean += delta / n
                        delta2 = resampled - mean
                        m2 += delta * delta2

                        if n >= sample_size:
                            break

                        current_start += encryption_duration
                        current_end += encryption_duration

                        # Retain the last known state for the next cycle
                        if last_t is not None:
                            times = [last_t]
                            values = [last_v]
                        else:
                            times = []
                            values = []

                    if n >= sample_size:
                        break

                elif len(parts) >= 2 and current_time is not None:
                    try:
                        times.append(current_time)
                        values.append(float(parts[1]))
                        current_time = None
                    except ValueError:
                        pass

    except FileNotFoundError:
        print(f"Error: File '{filename}' not found.")
        sys.exit(1)

    if n < 2:
        print(f"Error: Not enough traces found in {filename}.")
        sys.exit(1)

    variance = m2 / (n - 1)
    
    print(f"[{label}] Finished processing!")
    
    return mean, variance, n

def perform_tvla():
    random_file = '../results/aes_sbox_sca_MODEx_10p0ns/tvla_dynamic/tvla_traces.out'
    fixed_file = '../results/aes_sbox_sca_MODEx_10p0ns/tvla_static/tvla_traces.out'

    cycle_duration = 10000
    cycles_per_encryption = 1
    encryption_duration = cycle_duration * cycles_per_encryption
    start_time = 7000
    sample_size = 256
    resample_dt = 1

    common_time_axis = np.arange(0, encryption_duration, resample_dt)

    print("Starting multiple CPU cores...")
    
    with concurrent.futures.ProcessPoolExecutor(max_workers=2) as executor:
        future_r = executor.submit(compute_stats, random_file, start_time, encryption_duration, sample_size, common_time_axis, "RANDOM")
        future_f = executor.submit(compute_stats, fixed_file, start_time, encryption_duration, sample_size, common_time_axis, "FIXED ")

        mean_r, var_r, n_r = future_r.result()
        mean_f, var_f, n_f = future_f.result()

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
