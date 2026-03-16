source ./scripts/dc_lib_setup.tcl

# =====================================================================
# 1. SETUP & READ
# =====================================================================
set rtl_files { 
    aes_operation.v
}

# Define Variables
set rtl_top aes_operation
set mode $env(mode)

analyze -f verilog $rtl_files

echo "-----------------------------------------------------------------"
echo "Starting Synthesis for ${rtl_top}"
echo "-----------------------------------------------------------------"

elaborate $rtl_top -parameters "MODE = $mode"
current_design ${rtl_top}_MODE${mode}

if {[link] == 0} { echo "Error: Linking Failed"; exit 1 }
if {[check_design] == 0} { echo "Error: Check Design Failed"; exit 1 }

# =====================================================================
# 2. APPLY CONSTRAINTS
# =====================================================================
source -echo -verbose ./scripts/constraints/aes_operation_cons.tcl

# =====================================================================
# 3. OPTIMIZATION CONFIGURATION
# =====================================================================
# Physical Hints (DC-Topo only)
if {[shell_is_in_topographical_mode]} {
    set_aspect_ratio 1
    set_utilization 0.7
}

# Register & Power Optimization
set_register_merging [all_registers] true
# set_optimize_registers true -design [current_design]
set_cost_priority -delay
set_dynamic_optimization true
set_leakage_optimization true
# set_ungroup [get_cells -hierarchical round_pipeline*.standard_unified_round.round_inst] false
set_app_var compile_enable_constant_propagation_with_no_boundary_opt false

# Integrated Clock Gating
set_clock_gating_style -minimum_bitwidth 4 -control_point before -positive_edge_logic {integrated}

# =====================================================================
# 4. COMPILE
# =====================================================================
check_timing

# Run Compile
compile_ultra -retime -gate_clock

# Rerun compile if timing failed
set worst_path [get_timing_paths -delay_type max -nworst 1]
if {[sizeof_collection $worst_path] > 0} {
    set worst_slack [get_attribute $worst_path slack]
    
    if {$worst_slack < 0} {
        echo "-----------------------------------------------------------------"
        echo " Negative Slack ($worst_slack) detected. Running Incremental Compile..."
        echo "-----------------------------------------------------------------"
        # Run incremental with retime to try and squeeze the last bit of timing
        compile_ultra -incremental -retime 
    } else {
        echo "-----------------------------------------------------------------"
        echo " Timing Met (Slack: $worst_slack). Skipping Incremental Compile."
        echo "-----------------------------------------------------------------"
    }
}

# =====================================================================
# 5. REPORTS & OUTPUT
# =====================================================================
check_design
check_timing

set run_name   "${rtl_top}_MODE${mode}_${period}ns"

file mkdir ./results/${run_name}
file mkdir ./results/${run_name}/reports

report_area -physical > ./results/${run_name}/reports/area.rpt
report_timing -path full -delay max -max_paths 20 > ./results/${run_name}/reports/timing.rpt
report_power > ./results/${run_name}/reports/power.rpt
report_qor > ./results/${run_name}/reports/qor.rpt
report_constraints -all_violators > ./results/${run_name}/reports/constraints_violators.rpt
report_clock_gating -style > ./results/${run_name}/reports/clock_gating.rpt

write_file -format verilog -hierarchy -out ./results/${run_name}/${run_name}_ntl.v
write_file -format ddc -hierarchy -out ./results/${run_name}/${run_name}.ddc
write_sdc ./results/${run_name}/${run_name}.sdc
write_sdf ./results/${run_name}/${run_name}.sdf

echo "Finished Synthesis for ${run_name}"

exit
