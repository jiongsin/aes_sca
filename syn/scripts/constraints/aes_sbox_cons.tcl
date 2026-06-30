
# Timing and design-rule constraints for the AES S-box block.
# Defines base/SCA clock handling, I/O timing, drive/load assumptions, transition limits, and input/output path groups.

reset_design

echo "-----------------------------------------------------------------"
echo "Applying Constraints for Sbox"
echo "-----------------------------------------------------------------"

set CLK_PERIOD $env(period)
set period [string map {. p} $CLK_PERIOD]
set DELAY [expr $CLK_PERIOD * 0.10]

if { $version == "sca" } {
    echo "Applying SCA Constraints (Sequential)"
    set CLK_PORT_NAME "clk"
    create_clock -name clk -period $CLK_PERIOD [get_ports $CLK_PORT_NAME]
    set_clock_uncertainty -setup 0.3 [get_clocks clk]
    set_clock_uncertainty -hold  0.1 [get_clocks clk]
    set_clock_transition 0.05 [get_clocks clk]
    set_clock_latency -source -max 0.1 [get_clocks clk]
    set_clock_latency -max 0.1 [get_clocks clk]
} else {
    echo "Applying Base Constraints (Combinational)"
    set CLK_PORT_NAME "v_clk"
    create_clock -name v_clk -period $CLK_PERIOD
}

if { $version == "sca" } {
    set input_ports [remove_from_collection [all_inputs] [get_ports $CLK_PORT_NAME]]
} else {
    set input_ports [all_inputs]
}

set_input_delay  -max $DELAY -clock $CLK_PORT_NAME $input_ports
set_input_delay  -min [expr $DELAY * 0.5] -clock $CLK_PORT_NAME $input_ports

set_output_delay -max $DELAY -clock $CLK_PORT_NAME [all_outputs]
set_output_delay -min [expr $DELAY * 0.5] -clock $CLK_PORT_NAME [all_outputs]

set_max_transition 0.5 [current_design]
set_max_fanout 64.0 [current_design]
set_fix_multiple_port_nets -all -buffer_constant
change_names -rules verilog -hierarchy

if { $version == "sca" } {
    group_path -name REGS -from [all_registers] -to [all_registers]
} else {
    group_path -name COMBO -from [all_inputs] -to [all_outputs]
}

echo "Constraints Application Complete."
