#!/usr/bin/env python3

import os
import glob
import re

def generate_ppa_report():
    # Define paths based on the script location
    script_dir = os.path.dirname(os.path.abspath(__file__))
    workarea_syn = os.path.abspath(os.path.join(script_dir, '..'))
    
    results_dir = os.path.join(workarea_syn, 'results')
    output_report_path = os.path.join(workarea_syn, 'ppa_overview.rpt')
    
    # Get WORKAREA from terminal environment
    workarea_env = os.environ.get('WORKAREA', '')
    
    # Find all design directories
    search_pattern = os.path.join(results_dir, '*')
    design_dirs = [d for d in glob.glob(search_pattern) if os.path.isdir(d)]
    
    # Sort the directories alphabetically by the capital letters of the design name
    design_dirs.sort(key=lambda d: os.path.basename(d).upper())
    
    processed_designs = []
    
    print("Checking designs...")
    
    with open(output_report_path, 'w') as out_file:
        for design_path in design_dirs:
            design_name = os.path.basename(design_path)
            qor_file = os.path.join(design_path, 'reports', 'qor.rpt')
            power_file = os.path.join(design_path, 'reports', 'power.rpt')
            
            # Check if paths exist, report error and skip if they don't
            if not os.path.exists(qor_file) or not os.path.exists(power_file):
                print(f"  [Error] Missing report files for design '{design_name}'. Skipping...")
                continue
                
            processed_designs.append(design_name)
                
            # Variables for qor
            min_slack = float('inf')
            clk_period = 0.0
            combo_area = 0.0
            noncombo_area = 0.0
            design_area = 0.0
            net_length = ""
            
            with open(qor_file, 'r') as f:
                qor_lines = f.readlines()
                
            current_slack = None
            current_period = None
            
            # Read qor data
            for line in qor_lines:
                if "Critical Path Slack:" in line:
                    try:
                        current_slack = float(line.split(':')[1].strip())
                    except ValueError:
                        current_slack = None
                elif "Critical Path Clk Period:" in line:
                    try:
                        current_period = float(line.split(':')[1].strip())
                    except ValueError:
                        current_period = None
                    
                    if current_slack is not None and current_period is not None:
                        if current_slack < min_slack:
                            min_slack = current_slack
                            clk_period = current_period
                        current_slack = None
                        current_period = None
                        
                elif "Combinational Area:" in line:
                    combo_area = float(line.split(':')[1].strip())
                elif "Noncombinational Area:" in line:
                    noncombo_area = float(line.split(':')[1].strip())
                elif "Design Area:" in line:
                    design_area = float(line.split(':')[1].strip())
                elif "Net Length" in line and ":" in line:
                    net_length = line.split(':')[1].strip()
                    
            # Calculate Maximum Frequency in MHz
            if min_slack != float('inf') and clk_period > 0:
                denominator = clk_period - min_slack
                if denominator > 0:
                    max_freq = 1000 / denominator
                    freq_str = f"{max_freq:.2f} MHz"
                else:
                    freq_str = "Invalid values"
            else:
                freq_str = "Data not found"
                
            # Variables for power
            int_val = sw_val = stat_val = tot_val = 0.0
            int_unit = sw_unit = stat_unit = tot_unit = ""
            
            with open(power_file, 'r') as f:
                pwr_content = f.read()
                
            # Extract data from the Total row
            total_match = re.search(r'Total\s+([\d\.\+e]+)\s+(\w+)\s+([\d\.\+e]+)\s+(\w+)\s+([\d\.\+e]+)\s+(\w+)\s+([\d\.\+e]+)\s+(\w+)', pwr_content)
            
            if total_match:
                int_val = float(total_match.group(1))
                int_unit = total_match.group(2)
                sw_val = float(total_match.group(3))
                sw_unit = total_match.group(4)
                stat_val = float(total_match.group(5))
                stat_unit = total_match.group(6)
                tot_val = float(total_match.group(7))
                tot_unit = total_match.group(8)
                
            # Calculate Dynamic Power
            dyn_val = int_val + sw_val
            
            # Helper to convert power to uW for correct percentages
            def to_uW(val, unit):
                if unit == 'pW': return val / 1e6
                if unit == 'mW': return val * 1000
                if unit == 'W': return val * 1e6
                return val
                
            tot_val_uW = to_uW(tot_val, tot_unit)
            dyn_val_uW = to_uW(dyn_val, int_unit)
            stat_val_uW = to_uW(stat_val, stat_unit)
            
            dyn_pct = (dyn_val_uW / tot_val_uW * 100) if tot_val_uW > 0 else 0
            stat_pct = (stat_val_uW / tot_val_uW * 100) if tot_val_uW > 0 else 0
            
            # Calculate Area details
            kge = (design_area / 2.54144 / 1000) if design_area > 0 else 0
            combo_pct = (combo_area / design_area * 100) if design_area > 0 else 0
            noncombo_pct = (noncombo_area / design_area * 100) if design_area > 0 else 0
            
            # Use the environment variable for the full path
            qor_rel_path = f"{workarea_env}/syn/results/{design_name}/reports/qor.rpt"
            pwr_rel_path = f"{workarea_env}/syn/results/{design_name}/reports/power.rpt"
            
            # Write aligned format to report
            out_file.write(f"Design: {design_name}\n\n")
            
            out_file.write(f"Performance: {qor_rel_path}\n")
            if min_slack != float('inf'):
                out_file.write(f"  Critical Path Clk Period : {clk_period:.1f} ns\n")
                out_file.write(f"  Critical Path Slack      : {min_slack:.2f} ns\n")
                out_file.write(f"  Maximum Frequency        : {freq_str}\n\n")
            else:
                out_file.write("  Data not found\n\n")
                
            out_file.write(f"Power: {pwr_rel_path}\n")
            out_file.write(f"Total power                : {tot_val:.4f} {tot_unit}\n")
            out_file.write(f"  Dynamic power            : {dyn_val:.4e} {int_unit} ({dyn_pct:.1f}%)\n")
            out_file.write(f"    Internal power         : {int_val:.4f} {int_unit}\n")
            out_file.write(f"    Switching power        : {sw_val:.4f} {sw_unit}\n")
            out_file.write(f"  Static power             : {stat_val:.4e} {stat_unit} ({stat_pct:.1f}%)\n\n")
            
            out_file.write(f"Area: {qor_rel_path}\n")
            out_file.write(f"  Design Area              : {design_area:.4f} ({kge:.4f} kGE)\n")
            out_file.write(f"    Combinational Area     : {combo_area:.6f} ({combo_pct:.1f}%)\n")
            out_file.write(f"    Noncombinational Area  : {noncombo_area:.6f} ({noncombo_pct:.1f}%)\n")
            out_file.write(f"  Net Length               : {net_length}\n")
            out_file.write("\n" + "*"*65 + "\n\n")

    # Print results to the console
    print("\nReport generation complete.\n")
    print("Successfully processed designs:")
    if processed_designs:
        for name in processed_designs:
            print("  - " + name)
    else:
        print("  None")
        
    print(f"\nFile saved at:\n  {output_report_path}\n")

if __name__ == '__main__':
    generate_ppa_report()
