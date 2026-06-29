
# Timing and design-rule constraints for the AES CTR block.
# Defines the main clock, I/O timing, drive/load assumptions, reset/clock ideal networks, net-fixing rules, and input/output path groups.

reset_design

echo "----------------------------------------------------------------"
echo "Applying Constraints"
echo "----------------------------------------------------------------"

set CLK_PORT_NAME "clk"
set CLK_PERIOD 10.0
set period [string map {. p} $CLK_PERIOD]
set DELAY [expr $CLK_PERIOD * 0.10]

create_clock -name clk -period $CLK_PERIOD [get_ports $CLK_PORT_NAME]
set_clock_uncertainty -setup 0.3 [get_clocks clk]
set_clock_uncertainty -hold  0.1 [get_clocks clk]
set_clock_transition 0.05 [get_clocks clk]
set_clock_latency -source -max 0.1 [get_clocks clk]
set_clock_latency -max 0.1 [get_clocks clk]

set all_inputs_no_clk [remove_from_collection [all_inputs] [get_ports $CLK_PORT_NAME]]

set_input_delay  -max $DELAY -clock clk $all_inputs_no_clk
set_input_delay  -min [expr $DELAY * 0.5] -clock clk $all_inputs_no_clk
set_output_delay -max $DELAY -clock clk [all_outputs]
set_output_delay -min [expr $DELAY * 0.5] -clock clk [all_outputs]

set_driving_cell -lib_cell INVX1_HVT $all_inputs_no_clk
set_load 0.05 [all_outputs]
set_max_transition 0.5 [current_design]

set_propagated_clock [all_clocks]
set_ideal_network [get_ports clk]
set_ideal_network [get_ports rst_n]

set_fix_multiple_port_nets -all -buffer_constant
change_names -rules verilog -hierarchy

group_path -name INPUT -from [all_inputs]
group_path -name OUTPUT -to [all_outputs]

echo "Constraints Application Complete."
