#  Setup Environment
source ./scripts/pt_lib_setup.tcl

set_app_var power_enable_analysis true

set DESIGN $env(DESIGN)
set VER $env(VER)
set TVLA $env(TVLA)
set DESIGN_VER $env(DESIGN_VER)

file mkdir ./results/${DESIGN_VER}/tvla_${TVLA}

read_verilog ${DESIGN_VER}_ntl.v
link_design ${DESIGN}_${VER}
current_design ${DESIGN}_${VER}

# Define Constraint
create_clock -name v_clk -period 10.0

# Read the SDF file
read_sdf ./results/${DESIGN_VER}/${DESIGN_VER}.sdf

# Annotate Activity from VCS Simulation Using time-based mode for FSDB
set_app_var power_analysis_mode time_based

read_fsdb ./results/${DESIGN_VER}/sim_${TVLA}/${DESIGN_VER}.fsdb \
    -strip_path ${DESIGN}_tb/dut \
    -time {7 2547}
    #{95 490085}
# read_vcd ./results/${DESIGN_VER}/sim_${TVLA}/aes_operation.vcd \
    -strip_path aes_operation_tb/dut \
    -time {95 490085}

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

