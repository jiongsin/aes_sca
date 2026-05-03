reset_design

echo "-----------------------------------------------------------------"
echo "Applying Constraints for Combinational Sbox"
echo "-----------------------------------------------------------------"

# PARAMETERS
set CLK_PERIOD 10.0
set period [string map {. p} $CLK_PERIOD]
set DELAY [expr $CLK_PERIOD * 0.10]

# VIRTUAL CLOCK DEFINITION
create_clock -name v_clk -period $CLK_PERIOD
set_clock_uncertainty -setup 0.3 [get_clocks v_clk]
set_clock_uncertainty -hold  0.1 [get_clocks v_clk]

# I/O TIMING
set_input_delay  -max $DELAY -clock v_clk [all_inputs]
set_input_delay  -min [expr $DELAY * 0.5] -clock v_clk [all_inputs]

set_output_delay -max $DELAY -clock v_clk [all_outputs]
set_output_delay -min [expr $DELAY * 0.5] -clock v_clk [all_outputs]

# DESIGN RULES (DRC)
set_max_transition 0.5 [current_design]
set_max_fanout 64.0 [current_design]
set_fix_multiple_port_nets -all -buffer_constant
change_names -rules verilog -hierarchy

# OPTIMIZATION GROUPS
group_path -name COMBO -from [all_inputs] -to [all_outputs]

echo "Constraints Application Complete."
