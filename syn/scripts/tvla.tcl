#  Setup Environment
source ./scripts/pt_lib_setup.tcl

set_app_var power_enable_analysis true

set DESIGN $env(DESIGN)
set MODE $env(MODE)
set PERIOD $env(PERIOD)
set TVLA $env(TVLA)
set NTL ${DESIGN}_MODE${MODE}
set DESIGN_VER $env(DESIGN_VER)

file mkdir ./results/${DESIGN}_MODE${MODE}_10p0ns/tvla_${TVLA}

read_verilog ${DESIGN_VER}_ntl.v
link_design ${NTL}
current_design ${NTL}

# Define Constraint
create_clock -name clk -period 10.0 [get_ports clk]
set_propagated_clock [all_clocks]

# Read the SDF file
read_sdf ./results/${DESIGN_VER}/${DESIGN_VER}.sdf

# Annotate Activity from VCS Simulation Using time-based mode for FSDB
set_app_var power_analysis_mode time_based

read_fsdb ./results/${DESIGN_VER}/sim_${TVLA}/${DESIGN_VER}.fsdb \
    -strip_path aes_operation_tb/dut \
    -time {105 450075}
# read_vcd ./results/${DESIGN_VER}/sim_${TVLA}/${DESIGN_VER}.vcd \
    -strip_path aes_operation_tb/dut \
    -time {105 450075}

# Check and Report Activity
report_switching_activity > ./results/${DESIGN_VER}/tvla_${TVLA}/switching_activity.rpt
report_annotated_delay > ./results/${DESIGN_VER}/tvla_${TVLA}/annotated_delay.rpt

check_power

# Configure Power Analysis Options
# set_power_analysis_options -waveform_format fsdb \
                           -waveform_interval 0.001 \
                           -waveform_output ./results/${DESIGN_VER}/tvla_${TVLA}/tvla_traces
# update_power

set_power_analysis_options -waveform_format out \
                           -waveform_interval 0.001 \
                           -waveform_output ./results/${DESIGN_VER}/tvla_${TVLA}/tvla_traces
update_power

report_power > ./results/${DESIGN_VER}/tvla_${TVLA}/power.rpt

print_message_info

quit

