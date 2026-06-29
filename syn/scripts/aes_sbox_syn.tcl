# Synthesis script for the AES S-box implementation.
# Reads the selected base or SCA S-box RTL, applies constraints and preservation rules, compiles the block, and writes reports/netlist/database outputs.

source ./scripts/dc_lib_setup.tcl

set version $env(version)

set rtl_files [list \
    "aes_sbox_${version}.v" \
]

set rtl_top "aes_sbox_${version}"

analyze -f verilog $rtl_files
echo "-----------------------------------------------------------------"
echo "Starting Synthesis for ${rtl_top}"
echo "-----------------------------------------------------------------"

elaborate $rtl_top

current_design [get_designs ${rtl_top}*]

if {[link] == 0} { echo "Error: Linking Failed"; exit 1 }
if {[check_design] == 0} { echo "Error: Check Design Failed"; exit 1 }

source -echo -verbose ./scripts/constraints/aes_sbox_cons.tcl

echo "Applying Side-Channel Security Constraints..."

if {[sizeof_collection [get_designs -quiet *masked_and*]] > 0} {
    set_ungroup [get_designs *masked_and*] false
    set_boundary_optimization [get_designs *masked_and*] false
}

if {[sizeof_collection [get_designs -quiet *multiplicative_inverter_sca*]] > 0} {
    set_ungroup [get_designs *multiplicative_inverter_sca*] false
    set_boundary_optimization [get_designs *multiplicative_inverter_sca*] false
}

if {[shell_is_in_topographical_mode]} {
    set_aspect_ratio 1
    set_utilization 0.7
}

set run_name "${rtl_top}_${period}ns"
read_saif -input ../verif/sim/${run_name}/${run_name}.saif \
    -instance_name aes_sbox_tb/dut

set_register_merging [all_registers] false

set_cost_priority -delay
set_dynamic_optimization true
set_leakage_optimization true
set_app_var compile_enable_constant_propagation_with_no_boundary_opt false

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

file mkdir ./results/${run_name}
file mkdir ./results/${run_name}/reports

report_area -physical > ./results/${run_name}/reports/area.rpt
report_timing -path full -delay max -max_paths 10 > ./results/${run_name}/reports/timing_setup.rpt
report_timing -path full -delay min -max_paths 10 > ./results/${run_name}/reports/timing_hold.rpt
report_power > ./results/${run_name}/reports/power.rpt
report_qor > ./results/${run_name}/reports/qor.rpt
report_constraints -all_violators > ./results/${run_name}/reports/constraints_violators.rpt

write_file -format verilog -hierarchy -out ./results/${run_name}/${run_name}_ntl.v
write_file -format ddc -hierarchy -out ./results/${run_name}/${run_name}.ddc
write_sdc ./results/${run_name}/${run_name}.sdc
write_sdf ./results/${run_name}/${run_name}.sdf

echo "Finished Synthesis for ${run_name}"

exit
