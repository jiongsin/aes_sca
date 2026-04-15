source ./scripts/dc_lib_setup.tcl

# =====================================================================
# 1. SETUP & READ
# =====================================================================
# Get variables from environment
set mode $env(mode)
set version $env(version)

set rtl_files [list \
    "aes_operation_${version}.v" \
]

set rtl_top "aes_operation_${version}"

# It is better to force the define to uppercase if your RTL uses caps
set ver_define [string toupper "AES_${version}"]
set mode_define "AES_${mode}"

analyze -f verilog $rtl_files -define [list $mode_define $ver_define]

echo "-----------------------------------------------------------------"
echo "Starting Synthesis for ${rtl_top}"
echo "-----------------------------------------------------------------"

# Elaborate and set the design
elaborate $rtl_top -parameters "MODE = $mode"

# Use a collection to find the design name in case DC added a suffix
current_design [get_designs ${rtl_top}*]

if {[link] == 0} { echo "Error: Linking Failed"; exit 1 }
if {[check_design] == 0} { echo "Error: Check Design Failed"; exit 1 }

# =====================================================================
# 2. APPLY CONSTRAINTS
# =====================================================================
source -echo -verbose ./scripts/constraints/aes_operation_cons.tcl

# =====================================================================
# 3. OPTIMIZATION
# =====================================================================
if {[shell_is_in_topographical_mode]} {
    set_aspect_ratio 1
    set_utilization 0.7
}

set run_name "${rtl_top}_MODE${mode}_${period}ns"
read_saif -input ../sim/${run_name}/${run_name}.saif \
    -instance_name aes_operation_tb/dut

set_register_merging [all_registers] true
set_cost_priority -delay
set_dynamic_optimization true
set_leakage_optimization true
set_app_var compile_enable_constant_propagation_with_no_boundary_opt false

set_clock_gating_style -minimum_bitwidth 4 -control_point before -positive_edge_logic {integrated}

# =====================================================================
# 4. COMPILE
# =====================================================================
check_timing
compile_ultra -retime -gate_clock

# Incremental compile check
set worst_path [get_timing_paths -delay_type max -nworst 1]
if {[sizeof_collection $worst_path] > 0} {
    set worst_slack [get_attribute $worst_path slack]
    if {$worst_slack < 0} {
        echo "Negative Slack ($worst_slack) found. Retrying..."
        compile_ultra -incremental -retime 
    }
}
check_design
check_timing

# =====================================================================
# 5. OUTPUTS
# =====================================================================
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
