reset_design

echo "----------------------------------------------------------------"
echo "Applying Constraints"
echo "----------------------------------------------------------------"

# PARAMETERS
set CLK_PORT_NAME "HCLK"
set CLK_PERIOD 10.0
set period [string map {. p} $CLK_PERIOD]
set DELAY [expr $CLK_PERIOD * 0.40]

# CLOCK DEFINITION
create_clock -name clk -period $CLK_PERIOD [get_ports $CLK_PORT_NAME]
set_clock_uncertainty -setup 0.3 [get_clocks clk]
set_clock_uncertainty -hold  0.1 [get_clocks clk]
set_clock_transition 0.05 [get_clocks clk]
set_clock_latency -source -max 0.1 [get_clocks clk]
set_clock_latency -max 0.1 [get_clocks clk]

# I/O TIMING AND DRIVERS
set all_inputs_no_clk [remove_from_collection [all_inputs] [get_ports $CLK_PORT_NAME]]

set_input_delay  -max $DELAY -clock clk $all_inputs_no_clk
set_input_delay  -min [expr $DELAY * 0.5] -clock clk $all_inputs_no_clk
set_output_delay -max $DELAY -clock clk [all_outputs]
set_output_delay -min [expr $DELAY * 0.5] -clock clk [all_outputs]

# DESIGN RULES
set_driving_cell -lib_cell INVX1_HVT $all_inputs_no_clk
set_load 0.05 [all_outputs]
set_max_transition 0.5 [current_design]

# Stop the compiler from buffering the reset wire
set_propagated_clock [all_clocks]
set_ideal_network [get_ports clk]
set_ideal_network [get_ports rst_n]

set_fix_multiple_port_nets -all -buffer_constant
change_names -rules verilog -hierarchy

# OPTIMIZATION GROUPS
group_path -name INPUT -from [all_inputs]
group_path -name OUTPUT -to [all_outputs]

echo "Constraints Application Complete."
