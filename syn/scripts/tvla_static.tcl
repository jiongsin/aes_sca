#  Setup Environment
source ./scripts/pt_lib_setup.tcl

set_app_var power_enable_analysis true

set DESIGN $env(DESIGN)
set MODE $env(MODE)
set PERIOD $env(PERIOD)
set NTL ${DESIGN}_MODE${MODE}
set NTL_TIME ${NTL}_10p0ns

file mkdir ./results/${DESIGN}_MODE${MODE}_10p0ns/tvla_static

read_verilog ${NTL_TIME}_ntl.v
link_design ${NTL}
current_design ${NTL}

# Define Constraint
create_clock -name clk -period 10.0 [get_ports clk]
set_propagated_clock [all_clocks]

# Read the SDF file
read_sdf ./results/${NTL_TIME}/${NTL_TIME}.sdf

# Annotate Activity from VCS Simulation Using time-based mode for FSDB
set_app_var power_analysis_mode time_based

#read_fsdb ./results/${NTL_TIME}/sim_static/${DESIGN}.fsdb \
    -strip_path aes_operation_tb/dut \
    -time {105 450075}
read_vcd ./results/${NTL_TIME}/sim_static/${DESIGN}.vcd \
    -strip_path aes_operation_tb/dut \
    -time {105 450075}

# Check and Report Activity
report_switching_activity > ./results/${DESIGN}_MODE${MODE}_10p0ns/tvla_static/switching_activity.rpt
report_annotated_delay > ./results/${DESIGN}_MODE${MODE}_10p0ns/tvla_static/annotated_delay.rpt

check_power

# Configure Power Analysis Options
# set_power_analysis_options -waveform_format fsdb \
                           -waveform_interval 0.001 \
                           -waveform_output ./results/${DESIGN}_MODE${MODE}_10p0ns/tvla_static/tvla_traces
# update_power

set_power_analysis_options -waveform_format out \
                           -waveform_interval 0.001 \
                           -waveform_output ./results/${DESIGN}_MODE${MODE}_10p0ns/tvla_static/tvla_traces
update_power

report_power > ./results/${DESIGN}_MODE${MODE}_10p0ns/tvla_static/power.rpt

print_message_info

quit

