# PrimePower time-based simulation power-analysis script for AES designs.
# Loads the post-layout netlist, parasitics, constraints, SDF, and FSDB activity, then runs power analysis and writes the power report and trace output.

source ./scripts/pt_lib_setup.tcl

set_app_var power_enable_analysis true

set DESIGN $env(DESIGN)
set VER $env(VER)
set MODE $env(MODE)
set TVLA $env(TVLA)
set DESIGN_VER $env(DESIGN_VER)
if {$DESIGN eq "aes_ahb_lite_dma"} {
    set FIFO_DEPTH 8
    set BURST_CNT_W 32
    set TOP_MODULE ${DESIGN}_${VER}_MODE${MODE}_FIFO_DEPTH${FIFO_DEPTH}_BURST_CNT_W${BURST_CNT_W}
} else {
    set TOP_MODULE ${DESIGN}_${VER}_MODE${MODE}
}

if {($TVLA eq "dynamic") || ($TVLA eq "static")} {
    set RESULT_DIR ./results/${DESIGN_VER}/tvla_${TVLA}
    set SIM_DIR    ./results/${DESIGN_VER}/sim_${TVLA}
    set TRACE_DIR  ${RESULT_DIR}/tvla_traces
    set POWER_RPT  ./results/${DESIGN_VER}/reports_sta/power_tvla_${TVLA}.rpt
} else {
    set RESULT_DIR ./results/${DESIGN_VER}/psim
    set SIM_DIR    ./results/${DESIGN_VER}/sim
    set TRACE_DIR  ${RESULT_DIR}/tvla_traces
    set POWER_RPT  ./results/${DESIGN_VER}/reports_sta/power_psim.rpt
}

file mkdir ${RESULT_DIR}
file mkdir ./results/${DESIGN_VER}/reports_sta

read_verilog ${DESIGN_VER}.v
link_design ${TOP_MODULE}
current_design ${TOP_MODULE}

if {$DESIGN eq "aes_ahb_lite_dma"} {
    create_clock -name clk -period 10.0 [get_ports HCLK]
} else {
    create_clock -name clk -period 10.0 [get_ports clk]
}
set_propagated_clock [all_clocks]

read_sdf ./results/${DESIGN_VER}/${DESIGN_VER}_func_slow_max.sdf

set_app_var power_analysis_mode time_based

read_fsdb ${SIM_DIR}/${DESIGN_VER}.fsdb \
    -strip_path ${DESIGN}_tb/dut

report_switching_activity > ${RESULT_DIR}/switching_activity.rpt
report_annotated_delay > ${RESULT_DIR}/annotated_delay.rpt

check_power

set_power_analysis_options -waveform_format out \
                           -waveform_interval 0.05 \
                           -waveform_output ${TRACE_DIR}

update_power

report_power > ${POWER_RPT}

print_message_info

quit
