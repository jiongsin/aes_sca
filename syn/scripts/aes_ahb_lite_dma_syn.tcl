# =====================================================================
# AES-CTR AHB-Lite DMA SCA Synthesis Script
#
# Based on aes_operation_syn.tcl, adapted for:
#   Top        : aes_ahb_lite_dma_sca
#   RTL files  : aes_ahb_lite_dma_sca.v, aes_ctr_sca.v,
#                aes_operation_sca.v, aes_sbox_sca.v
#   Clock port : HCLK
#   Reset port : HRESETn
#
# Environment variables:
#   mode         : 128 / 192 / 256
#   version      : sca          optional, default = sca
#   fifo_depth   : FIFO depth   optional, default = 8
#   burst_cnt_w  : burst width  optional, default = 16
# =====================================================================


# =====================================================================
# 0. SETUP
# =====================================================================

source ./scripts/dc_lib_setup.tcl


# =====================================================================
# 1. SETUP & READ
# =====================================================================

set mode $env(mode)
set version $env(version)
set fifo_depth 8
set burst_cnt_w 32

if { $version != "sca" } {
    echo "ERROR: aes_ahb_lite_dma_${version}.v is not expected in this flow. Use version=sca."
    exit 1
}

set rtl_files [list \
    "aes_ahb_lite_dma_${version}.v" \
    "aes_ctr_${version}.v" \
    "aes_operation_${version}.v" \
    "aes_sbox_${version}.v" \
]

set rtl_top "aes_ahb_lite_dma_${version}"

set mode_define "AES_${mode}"
set ver_define  [string toupper "AES_${version}"]

set_app_var hdlin_keep_signal_name all
set_app_var hdlin_preserve_sequential true

analyze -f verilog $rtl_files -define [list $mode_define $ver_define]

echo "Starting Synthesis for ${rtl_top}"

elaborate $rtl_top \
    -parameters "MODE = $mode, FIFO_DEPTH = $fifo_depth, BURST_CNT_W = $burst_cnt_w"

current_design [get_designs ${rtl_top}*]

if {[link] == 0} {
    echo "ERROR: Linking Failed"
    exit 1
}

if {[check_design] == 0} {
    echo "ERROR: Check Design Failed"
    exit 1
}


# =====================================================================
# 2. APPLY CONSTRAINTS
# =====================================================================
# This is the aes_operation_cons.tcl constraint style adapted to the
# AHB-Lite wrapper clock/reset names: HCLK and HRESETn.
# =====================================================================

source -echo -verbose ./scripts/constraints/aes_ahb_lite_dma_cons.tcl

set run_name "${rtl_top}_MODE${mode}_${period}ns"

echo "============================================================"
echo "Synthesis configuration"
echo "Top         : ${rtl_top}"
echo "Mode        : ${mode}"
echo "Version     : ${version}"
echo "FIFO depth  : ${fifo_depth}"
echo "Burst cnt W : ${burst_cnt_w}"
echo "Period      : ${period} ns"
echo "Run name    : ${run_name}"
echo "============================================================"


# =====================================================================
# 3. SAFE HELPER PROCEDURES
# =====================================================================

proc safe_set_ungroup_false {pattern} {
    set objs [get_designs $pattern -quiet]
    if {[sizeof_collection $objs] > 0} {
        echo "Preserve hierarchy: $pattern"
        set_ungroup $objs false
    } else {
        echo "INFO: no design matched for set_ungroup false: $pattern"
    }
}

proc safe_set_boundary_opt_false {pattern} {
    set objs [get_designs $pattern -quiet]
    if {[sizeof_collection $objs] > 0} {
        echo "Disable boundary optimization: $pattern"
        set_boundary_optimization $objs false
    } else {
        echo "INFO: no design matched for boundary optimization false: $pattern"
    }
}

proc safe_dont_touch_nets {pattern} {
    set objs [get_nets -hierarchical $pattern -quiet]
    if {[sizeof_collection $objs] > 0} {
        echo "Dont touch nets: $pattern"
        set_dont_touch $objs
    } else {
        echo "INFO: no nets matched for dont_touch: $pattern"
    }
}

proc safe_report_cells {pattern rpt_name} {
    set objs [get_cells -hierarchical $pattern -quiet]
    if {[sizeof_collection $objs] > 0} {
        redirect $rpt_name {
            report_cell $objs
        }
    }
}


# =====================================================================
# 4. SCA PRESERVATION CONSTRAINTS
# =====================================================================

echo "Applying Side Channel Security Constraints..."

echo "============================================================"
echo "SCA MODE: WHOLE-DESIGN CLOCK GATING ENABLED"
echo "============================================================"

# ---------------------------------------------------------------------
# 4.1 Disable optimizations that can break masking
# ---------------------------------------------------------------------

set_app_var compile_enable_constant_propagation_with_no_boundary_opt false

# Do not freeze all registers using dont_touch; it blocks clock gating.
# Disable register merging and retiming instead.
set_optimize_registers false
set_app_var compile_enable_register_merging false

set_dont_retime [get_designs *]

set all_regs [all_registers]
if {[sizeof_collection $all_regs] > 0} {
    echo "SCA: disabling register merging and retiming"
    echo "SCA: allowing clock gating insertion"
    set_register_merging $all_regs false
    set_dont_retime $all_regs true
}

# ---------------------------------------------------------------------
# 4.2 Preserve wrapper / CTR / AES / DOM hierarchy without freezing GTECH
# ---------------------------------------------------------------------
# Do NOT set_dont_touch whole SCA designs before compile.
# Use set_ungroup false and boundary optimization false instead.
# ---------------------------------------------------------------------

safe_set_ungroup_false "*aes_ahb_lite_dma_sca*"
safe_set_ungroup_false "*sync_fifo_fwft_dma*"
safe_set_ungroup_false "*aes_ctr_sca*"
safe_set_ungroup_false "*aes_prng_sca*"
safe_set_ungroup_false "*aes_operation_sca*"
safe_set_ungroup_false "*aes_key_expansion_sca*"
safe_set_ungroup_false "*aes_sbox_sca*"
safe_set_ungroup_false "*isomorphic_mapping_sca*"
safe_set_ungroup_false "*multiplicative_inverter_sca*"
safe_set_ungroup_false "*merged_inverse_affine_sca*"
safe_set_ungroup_false "*gf4_inverter_sca*"
safe_set_ungroup_false "*gf4_multiplier_sca*"
safe_set_ungroup_false "*gf2_multiplier_sca*"
safe_set_ungroup_false "*dom_and_sca*"

safe_set_boundary_opt_false "*aes_ahb_lite_dma_sca*"
safe_set_boundary_opt_false "*sync_fifo_fwft_dma*"
safe_set_boundary_opt_false "*aes_ctr_sca*"
safe_set_boundary_opt_false "*aes_prng_sca*"
safe_set_boundary_opt_false "*aes_operation_sca*"
safe_set_boundary_opt_false "*aes_key_expansion_sca*"
safe_set_boundary_opt_false "*aes_sbox_sca*"
safe_set_boundary_opt_false "*isomorphic_mapping_sca*"
safe_set_boundary_opt_false "*multiplicative_inverter_sca*"
safe_set_boundary_opt_false "*merged_inverse_affine_sca*"
safe_set_boundary_opt_false "*gf4_inverter_sca*"
safe_set_boundary_opt_false "*gf4_multiplier_sca*"
safe_set_boundary_opt_false "*gf2_multiplier_sca*"
safe_set_boundary_opt_false "*dom_and_sca*"

# ---------------------------------------------------------------------
# 4.3 Protect selected security-sensitive nets only
# ---------------------------------------------------------------------
# Keep the list specific. Do not use broad *_0* / *_1* dont_touch
# patterns because they can prevent technology mapping.
# ---------------------------------------------------------------------

# Random / mask path from wrapper -> CTR -> AES operation.
safe_dont_touch_nets "*trng_reg*"
safe_dont_touch_nets "*trng_work_reg*"
safe_dont_touch_nets "*trng_in*"
safe_dont_touch_nets "*random_out*"
safe_dont_touch_nets "*random_bits*"
safe_dont_touch_nets "*key_mask*"
safe_dont_touch_nets "*data_mask*"
safe_dont_touch_nets "*masked_key_in_0*"
safe_dont_touch_nets "*masked_key_in_1*"

# Shared AES datapath nets.
safe_dont_touch_nets "*shared_sbox_in_0*"
safe_dont_touch_nets "*shared_sbox_in_1*"
safe_dont_touch_nets "*shared_sbox_out_0*"
safe_dont_touch_nets "*shared_sbox_out_1*"
safe_dont_touch_nets "*subbytes_out_0*"
safe_dont_touch_nets "*subbytes_out_1*"
safe_dont_touch_nets "*round_data_out_0*"
safe_dont_touch_nets "*round_data_out_1*"
safe_dont_touch_nets "*expanded_key_word_0*"
safe_dont_touch_nets "*expanded_key_word_1*"
safe_dont_touch_nets "*key_sbox_in_0*"
safe_dont_touch_nets "*key_sbox_in_1*"
safe_dont_touch_nets "*key_sbox_out_0*"
safe_dont_touch_nets "*key_sbox_out_1*"

# DOM sensitive combinational nets.
safe_dont_touch_nets "*cross_0_comb*"
safe_dont_touch_nets "*cross_1_comb*"
safe_dont_touch_nets "*cross_*_comb*"
safe_dont_touch_nets "*inner_0*"
safe_dont_touch_nets "*inner_1*"


# =====================================================================
# 5. PHYSICAL / TOPOGRAPHICAL SETUP
# =====================================================================

if {[shell_is_in_topographical_mode]} {
    set_aspect_ratio 1
    set_utilization 0.7
}


# =====================================================================
# 6. SAIF READ
# =====================================================================

set saif_path "../verif/sim/${run_name}/${run_name}.saif"

if {[file exists $saif_path]} {
    echo "Reading SAIF: ${saif_path}"
    read_saif -input $saif_path -instance_name aes_ahb_lite_dma_tb/dut
} else {
    set saif_path_alt "./verif/sim/${run_name}/${run_name}.saif"

    if {[file exists $saif_path_alt]} {
        echo "Reading SAIF: ${saif_path_alt}"
        read_saif -input $saif_path_alt -instance_name aes_ahb_lite_dma_tb/dut
    } else {
        echo "WARNING: SAIF not found."
        echo "WARNING: Continue synthesis without SAIF."
    }
}


# =====================================================================
# 7. OPTIMIZATION OPTIONS
# =====================================================================

set_cost_priority -delay
set_fix_hold [get_clocks clk]

set_dynamic_optimization true
set_leakage_optimization true

# Whole-design clock gating.
set_clock_gating_style \
    -minimum_bitwidth 1 \
    -positive_edge_logic {integrated} \
    -control_point before

insert_clock_gating


# =====================================================================
# 8. PRE-COMPILE CHECKS
# =====================================================================

check_design
check_timing


# =====================================================================
# 9. COMPILE
# =====================================================================

echo "============================================================"
echo "Starting compile for ${run_name}"
echo "============================================================"

compile_ultra -gate_clock


# =====================================================================
# 10. INCREMENTAL TIMING REPAIR
# =====================================================================

set worst_path [get_timing_paths -delay_type max -nworst 1]

if {[sizeof_collection $worst_path] > 0} {
    set worst_slack [get_attribute $worst_path slack]
    echo "Worst setup slack after compile: ${worst_slack}"

    if {$worst_slack < 0} {
        echo "Negative Slack (${worst_slack}) found. Retrying incremental compile..."
        compile_ultra -no_autoungroup -gate_clock -incremental
    }
}


# =====================================================================
# 11. POST-COMPILE CHECKS
# =====================================================================

check_design
check_timing


# =====================================================================
# 12. CHECK FOR UNMAPPED / GTECH CELLS
# =====================================================================

echo "============================================================"
echo "Checking for unmapped / GTECH cells"
echo "============================================================"

set gtech_cells [get_cells -hierarchical *GTECH* -quiet]

if {[sizeof_collection $gtech_cells] > 0} {
    echo "ERROR: GTECH cells remain after compile."
    echo "This netlist is not suitable for gate-level simulation."
    report_cell $gtech_cells
    exit 1
}

# Some DC versions support is_unmapped. If yours does not, comment this block.
set unmapped_cells [get_cells -hierarchical -filter "is_unmapped == true" -quiet]

if {[sizeof_collection $unmapped_cells] > 0} {
    echo "ERROR: Unmapped cells remain after compile."
    report_cell $unmapped_cells
    exit 1
}

echo "No GTECH or unmapped cells found."


# =====================================================================
# 13. OUTPUT DIRECTORIES
# =====================================================================

file mkdir ./results/${run_name}
file mkdir ./results/${run_name}/reports


# =====================================================================
# 14. REPORTS
# =====================================================================

report_area -physical \
    > ./results/${run_name}/reports/area.rpt

report_timing -path full -delay max -max_paths 10 \
    > ./results/${run_name}/reports/timing_setup.rpt

report_timing -path full -delay min -max_paths 10 \
    > ./results/${run_name}/reports/timing_hold.rpt

report_power \
    > ./results/${run_name}/reports/power.rpt

report_qor \
    > ./results/${run_name}/reports/qor.rpt

report_constraints -all_violators \
    > ./results/${run_name}/reports/constraints_violators.rpt

report_clock_gating -style \
    > ./results/${run_name}/reports/clock_gating.rpt

report_hierarchy \
    > ./results/${run_name}/reports/hierarchy.rpt

report_reference \
    > ./results/${run_name}/reports/reference.rpt

report_compile_options \
    > ./results/${run_name}/reports/compile_options.rpt


# =====================================================================
# 15. SCA / WRAPPER DEBUG REPORTS
# =====================================================================

redirect ./results/${run_name}/reports/sca_registers.rpt {
    echo "All registers:"
    report_cell [all_registers]
}

redirect ./results/${run_name}/reports/sca_clock_gating_cells.rpt {
    echo "Clock gating report:"
    report_clock_gating -gated -ungated -style
}

redirect ./results/${run_name}/reports/sca_dom_cells.rpt {
    echo "DOM cells:"
    report_cell [get_cells -hierarchical *dom_and_sca* -quiet]
}

redirect ./results/${run_name}/reports/sca_sbox_cells.rpt {
    echo "S-box related cells:"
    report_cell [get_cells -hierarchical *aes_sbox_sca* -quiet]
    report_cell [get_cells -hierarchical *multiplicative_inverter_sca* -quiet]
    report_cell [get_cells -hierarchical *gf4_inverter_sca* -quiet]
    report_cell [get_cells -hierarchical *gf4_multiplier_sca* -quiet]
    report_cell [get_cells -hierarchical *gf2_multiplier_sca* -quiet]
}

redirect ./results/${run_name}/reports/sca_random_mask_nets.rpt {
    echo "Random and mask nets:"
    report_net [get_nets -hierarchical *trng_reg* -quiet]
    report_net [get_nets -hierarchical *trng_work_reg* -quiet]
    report_net [get_nets -hierarchical *random_out* -quiet]
    report_net [get_nets -hierarchical *random_bits* -quiet]
    report_net [get_nets -hierarchical *data_mask* -quiet]
    report_net [get_nets -hierarchical *key_mask* -quiet]
    report_net [get_nets -hierarchical *masked_key_in_0* -quiet]
    report_net [get_nets -hierarchical *masked_key_in_1* -quiet]
}

redirect ./results/${run_name}/reports/sca_share_nets.rpt {
    echo "Top share nets:"
    report_net [get_nets -hierarchical *shared_sbox_in_0* -quiet]
    report_net [get_nets -hierarchical *shared_sbox_in_1* -quiet]
    report_net [get_nets -hierarchical *shared_sbox_out_0* -quiet]
    report_net [get_nets -hierarchical *shared_sbox_out_1* -quiet]
    report_net [get_nets -hierarchical *round_data_out_0* -quiet]
    report_net [get_nets -hierarchical *round_data_out_1* -quiet]
    report_net [get_nets -hierarchical *expanded_key_word_0* -quiet]
    report_net [get_nets -hierarchical *expanded_key_word_1* -quiet]
}

redirect ./results/${run_name}/reports/ahb_dma_cells.rpt {
    echo "AHB-Lite DMA wrapper cells:"
    report_cell [get_cells -hierarchical *u_pt_fifo* -quiet]
    report_cell [get_cells -hierarchical *u_ct_fifo* -quiet]
    report_cell [get_cells -hierarchical *u_aes_ctr_sca* -quiet]
    report_cell [get_cells -hierarchical *u_aes_operation* -quiet]
    report_cell [get_cells -hierarchical *u_aes_prng* -quiet]
}


# =====================================================================
# 16. WRITE OUTPUTS
# =====================================================================

write_file -format verilog -hierarchy \
    -out ./results/${run_name}/${run_name}_ntl.v

write_file -format ddc -hierarchy \
    -out ./results/${run_name}/${run_name}.ddc

write_sdc ./results/${run_name}/${run_name}.sdc

write_sdf ./results/${run_name}/${run_name}.sdf


# =====================================================================
# 17. FINAL GREP-LIKE NETLIST WARNING
# =====================================================================

echo "============================================================"
echo "Finished Synthesis for ${run_name}"
echo "Netlist : ./results/${run_name}/${run_name}_ntl.v"
echo "DDC     : ./results/${run_name}/${run_name}.ddc"
echo "SDC     : ./results/${run_name}/${run_name}.sdc"
echo "SDF     : ./results/${run_name}/${run_name}.sdf"
echo "Reports : ./results/${run_name}/reports"
echo ""
echo "After synthesis, verify:"
echo "  grep -n GTECH ./results/${run_name}/${run_name}_ntl.v"
echo "Expected: no output"
echo "============================================================"

exit
