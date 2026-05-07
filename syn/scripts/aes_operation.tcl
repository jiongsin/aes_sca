source ./scripts/dc_lib_setup.tcl

# =====================================================================
# 1. SETUP & READ
# =====================================================================
set mode $env(mode)
set version $env(version)

set rtl_files [list \
    "aes_operation_${version}.v" \
]

set rtl_top "aes_operation_${version}"

set ver_define [string toupper "AES_${version}"]
set mode_define "AES_${mode}"

set hdlin_keep_signal_name all
set hdlin_preserve_net_names true

analyze -f verilog $rtl_files -define [list $mode_define $ver_define]

echo "-----------------------------------------------------------------"
echo "Starting Synthesis for ${rtl_top}"
echo "-----------------------------------------------------------------"

elaborate $rtl_top -parameters "MODE = $mode"
current_design [get_designs ${rtl_top}*]

if {[link] == 0} { echo "Error: Linking Failed"; exit 1 }
if {[check_design] == 0} { echo "Error: Check Design Failed"; exit 1 }

# =====================================================================
# 2. APPLY CONSTRAINTS
# =====================================================================
source -echo -verbose ./scripts/constraints/aes_operation_cons.tcl

# =====================================================================
# 2.5 SCA PRESERVATION CONSTRAINTS (CRITICAL)
# =====================================================================
echo "Applying Side-Channel Security Constraints..."

# Prevent the tool from optimizing away our masked AND gates
if {[sizeof_collection [get_designs -quiet *dom_and_sca*]] > 0} {
    set_ungroup [get_designs *dom_and_sca*] false
    set_boundary_optimization [get_designs *dom_and_sca*] false
    set_dont_touch [get_nets -hierarchical *cross_*_comb*]
    set_dont_touch [get_nets -hierarchical *inner_*]
}

# Protect the random bit masks from being mathematically optimized away
if { $version == "sca" } {
    set_dont_touch [get_nets -hierarchical *mask_data*]
    set_dont_touch [get_nets -hierarchical *mask_key*]
    set_dont_touch [get_ports *random_bits*]
    set_dont_touch [get_nets -hierarchical *mixcolumns_out_0*]
    set_dont_touch [get_nets -hierarchical *mixcolumns_out_1*]
    set_dont_touch [get_nets -hierarchical *round_data_out_0*]
    set_dont_touch [get_nets -hierarchical *round_data_out_1*]
    set_dont_touch [get_nets -hierarchical *perm_table*]
    set_dont_touch [get_nets -hierarchical *cur_col_idx*]
}

# Disable aggressive register merging globally
set_optimize_registers false
set_app_var compile_enable_register_merging false

# =====================================================================
# 3. OPTIMIZATION
# =====================================================================
if {[shell_is_in_topographical_mode]} {
    set_aspect_ratio 1
    set_utilization 0.7
}

set run_name "${rtl_top}_MODE${mode}_${period}ns"
read_saif -input ../verif/sim/${run_name}/${run_name}.saif \
    -instance_name aes_operation_tb/dut

set_register_merging [all_registers] false

set_cost_priority -delay
set_dynamic_optimization true
set_leakage_optimization true
set_app_var compile_enable_constant_propagation_with_no_boundary_opt false

# set_clock_gating_style -minimum_bitwidth 4 -control_point before -positive_edge_logic {integrated}

# =====================================================================
# 4. COMPILE
# =====================================================================
check_timing

compile_ultra -no_autoungroup

set worst_path [get_timing_paths -delay_type max -nworst 1]
if {[sizeof_collection $worst_path] > 0} {
    set worst_slack [get_attribute $worst_path slack]
    if {$worst_slack < 0} {
        echo "Negative Slack ($worst_slack) found. Retrying..."
        compile_ultra -incremental -no_autoungroup 
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
