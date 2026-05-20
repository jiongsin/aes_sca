source ./scripts/dc_lib_setup.tcl

# =====================================================================
# 1. SETUP & READ
# =====================================================================
set mode $env(mode)
set version $env(version)

set rtl_files [list "aes_ctr_${version}.v" "aes_operation_${version}.v" "aes_sbox_${version}.v"]
set rtl_top "aes_ctr_${version}"

set ver_define [string toupper "AES_${version}"]
set mode_define "AES_${mode}"

set hdlin_keep_signal_name all
set hdlin_preserve_net_names true

analyze -f verilog $rtl_files -define [list $mode_define $ver_define]

echo "Starting Synthesis for ${rtl_top}"

elaborate $rtl_top -parameters "MODE = $mode"
current_design [get_designs ${rtl_top}*]

if {[link] == 0} { echo "Error: Linking Failed"; exit 1 }
if {[check_design] == 0} { echo "Error: Check Design Failed"; exit 1 }

# =====================================================================
# 2. APPLY CONSTRAINTS
# =====================================================================
source -echo -verbose ./scripts/constraints/aes_ctr_cons.tcl

# =====================================================================
# 3. SCA PRESERVATION CONSTRAINTS
# =====================================================================
echo "Applying Side Channel Security Constraints..."

if { $version == "sca" } {
    # 1. Protect DOM AND Gates
    set_ungroup [get_designs *dom_and_sca*] false
    set_boundary_optimization [get_designs *dom_and_sca*] false

    # Stop constants from sneaking through the boundary
    set_app_var compile_enable_constant_propagation_with_no_boundary_opt false
    
    # Protect combinational nets inside DOM
    set_dont_touch [get_nets -hierarchical *cross_*_comb*]
    set_dont_touch [get_nets -hierarchical *inner_0*]
    set_dont_touch [get_nets -hierarchical *inner_1*]

    # 2. Protect Logic Boundaries and Masks
    set_dont_touch [get_nets *random_bits*]
    set_dont_touch [get_nets -hierarchical *data_mask*]
    set_dont_touch [get_nets -hierarchical *key_mask*]
     
    # Protect initial masking boundaries
    set_dont_touch [get_nets -hierarchical *masked_key_in_0*]
    set_dont_touch [get_nets -hierarchical *masked_key_in_1*]

    # Protect Sbox boundaries
    set_dont_touch [get_nets -hierarchical *subbytes_out_0*]
    set_dont_touch [get_nets -hierarchical *subbytes_out_1*]

    # Protect key expansion boundaries
    set_dont_touch [get_nets -hierarchical *expanded_key_word_0*]
    set_dont_touch [get_nets -hierarchical *expanded_key_word_1*]

    # 3. Protect Sbox Math Blocks
    set_ungroup [get_designs *multiplicative_inverter_sca*] false
}

# Enable global merging for normal logic save area
set_optimize_registers true
set_app_var compile_enable_register_merging true
set_register_merging [all_registers] true

# Strictly protect only the DOM registers using a safe search
set protected_regs [get_cells -hierarchical {*state_reg_* *cross_*_reg* *inner_*_reg*} -quiet]
if {[sizeof_collection $protected_regs] > 0} {
    set_register_merging $protected_regs false
    set_dont_retime $protected_regs true
}

# =====================================================================
# 4. OPTIMIZATION & COMPILE
# =====================================================================
if {[shell_is_in_topographical_mode]} {
    set_aspect_ratio 1
    set_utilization 0.7
}

set run_name "${rtl_top}_MODE${mode}_${period}ns"
read_saif -input ../verif/sim/${run_name}/${run_name}.saif -instance_name aes_ctr_tb/dut

set_cost_priority -delay
set_dynamic_optimization true 
set_leakage_optimization true
set_fix_hold [get_clocks clk]

# Enable Clock Gating for Power Savings
if { $version == "sca" } {
    set_clock_gating_style -minimum_bitwidth 32 -positive_edge_logic {integrated} -control_point before
    insert_clock_gating
}

check_timing

# Compile with gate clock enabled
if { $version == "sca" } {
    compile_ultra -no_autoungroup -gate_clock
} else {
    compile_ultra 
}

set worst_path [get_timing_paths -delay_type max -nworst 1]
if {[sizeof_collection $worst_path] > 0} {
    set worst_slack [get_attribute $worst_path slack]
    if {$worst_slack < 0} {
        echo "Negative Slack ($worst_slack) found. Retrying..."
	if { $version == "sca" } {
            compile_ultra -no_autoungroup -gate_clock -incremental 
        } else {
            compile_ultra -incremental 
        }
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
report_timing -path full -delay max -max_paths 10 > ./results/${run_name}/reports/timing_setup.rpt
report_timing -path full -delay min -max_paths 10 > ./results/${run_name}/reports/timing_hold.rpt
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
