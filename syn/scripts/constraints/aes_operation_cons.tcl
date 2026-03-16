reset_design

echo "-----------------------------------------------------------------"
echo "Applying Constraints"
echo "-----------------------------------------------------------------"

# PARAMETERS
set CLK_PORT_NAME "clk"
set CLK_PERIOD 10.0; # 100 MHz
set period [string map {. p} $CLK_PERIOD]
set DELAY [expr $CLK_PERIOD * 0.10]; # Time Budgeting

# CLOCK DEFINITION
create_clock -name clk -period $CLK_PERIOD [get_ports $CLK_PORT_NAME]
set_clock_uncertainty -setup 0.3 [get_clocks clk]
set_clock_uncertainty -hold  0.1 [get_clocks clk]
set_clock_transition 0.05 [get_clocks clk]
set_clock_latency -source -max 0.1 [get_clocks clk]
set_clock_latency -max 0.1 [get_clocks clk]

# I/O TIMING & DRIVERS
set all_inputs_no_clk [remove_from_collection [all_inputs] [get_ports $CLK_PORT_NAME]]
# Input/Output Delays 
set_input_delay  -max $DELAY -clock clk $all_inputs_no_clk
set_input_delay  -min [expr $DELAY * 0.5] -clock clk $all_inputs_no_clk
set_output_delay -max $DELAY -clock clk [all_outputs]
set_output_delay -min [expr $DELAY * 0.5] -clock clk [all_outputs]
# Driving Cell & Loads
set_driving_cell -max -no_design_rule -lib_cell INVX1_RVT [all_inputs]
set MAX_INPUT_LOAD [expr [load_of saed32rvt_ss0p95v125c/AND2X1_RVT/A1] * 10]
set_max_capacitance $MAX_INPUT_LOAD [all_inputs]
set_load [expr $MAX_INPUT_LOAD * 3] [all_outputs]

# DESIGN RULES (DRC)
set_max_transition 0.5 [current_design]
set_max_fanout 64.0 [current_design]
set_fix_multiple_port_nets -all -buffer_constant
change_names -rules verilog -hierarchy

# 5. OPTIMIZATION GROUPS
group_path -name INPUT -from [all_inputs]
group_path -name OUTPUT -to [all_outputs]

echo "Constraints Application Complete."
