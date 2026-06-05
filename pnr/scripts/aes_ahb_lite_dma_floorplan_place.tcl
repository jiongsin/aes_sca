############################################################
# ICC2 Floorplanning + Placement Script
# DOM-based AES-CTR AHB-Lite DMA SCA Accelerator
#
# - Array-style MCMM setup
# - M7/M8 enabled
# - Balanced PG mesh
# - DFT / scan-related commands removed
# - DOM/SCA preservation rules added
# - random_bits nets allowed to be buffered
# - Post-place PG reconnect + std-cell rail repair
# - Filler insertion after place_opt
# - Safe setup/hold/DRV reports
# - Final congestion uses high effort once
# - Legal save_block names
############################################################

source ./scripts/icc2_lib_setup.tcl

set mode    $env(MODE)
set version $env(VER)
set ntl_ver $env(DESIGN_VER)

############################################################
# 0. User switches
############################################################

set USE_SHAPE_BLOCKS 0
set USE_EXPLICIT_PG_VIA_RULES 0

set USE_DOM_SECURITY_RULES 1
set USE_DOM_SOFT_BOUNDS 1

# Filler cells for SAED32 HVT library
set FILLER_CELLS {saed32hvt/SHFILL*}

############################################################
# 1. Directory setup
############################################################

set OUTPUT_DIR ./results/${ntl_ver}
set REPORT_DIR ${OUTPUT_DIR}/reports

file mkdir $OUTPUT_DIR
file mkdir $REPORT_DIR


############################################################
# AHB-Lite DMA wrapper notes
############################################################
# This script is the wrapper-level PnR stage for:
#   aes_ahb_lite_dma_sca
# It expects DESIGN_VER to match the synthesis run name, e.g.:
#   aes_ahb_lite_dma_sca_MODE128_10p0ns
# The netlist is read from:
#   ../syn/results/${ntl_ver}/${ntl_ver}_ntl.v
############################################################

############################################################
# 2. Helper procedure
############################################################

proc safe_set_app_option {opt val} {
    if {[catch {set_app_options -name $opt -value $val} msg]} {
        puts "WARNING: Could not set app option $opt to $val"
        puts "WARNING: $msg"
    } else {
        puts "INFO: Set app option $opt = $val"
    }
}

############################################################
# 3. Runtime setup
############################################################

set_host_options -max_cores 8

############################################################
# 4. Read netlist and link design
############################################################

read_verilog ../syn/results/${ntl_ver}/${ntl_ver}_ntl.v
link_block
current_block

redirect -file ${REPORT_DIR}/01_design_summary_after_link.rpt {
    report_design -summary
}

############################################################
# 5. Technology / parasitic setup
############################################################

read_parasitic_tech \
    -layermap saed32nm_tf_itf_tluplus.map \
    -tlup saed32nm_1p9m_Cmax.tluplus \
    -name maxTLU

read_parasitic_tech \
    -layermap saed32nm_tf_itf_tluplus.map \
    -tlup saed32nm_1p9m_Cmin.tluplus \
    -name minTLU

############################################################
# 6. MCMM setup
############################################################
# Mode:
#   func
#
# Corners:
#   slow_max : setup corner, max RC
#   fast_min : hold corner, min RC
#
# Scenarios:
#   func.slow_max : setup enabled
#   func.fast_min : hold enabled
#
# Note:
# set_process_label is intentionally removed because your library
# reported CSTR-040: process label slow/fast is not used by any
# reference library.

catch {remove_scenarios -all}
catch {remove_modes -all}
catch {remove_corners -all}

array unset m_constr
array unset c_constr
array unset s_constr

set m_constr(func) "func_mode_embedded"

set c_constr(slow_max) "slow_corner_embedded"
set c_constr(fast_min) "fast_corner_embedded"

set s_constr(func.slow_max) "../syn/results/${ntl_ver}/${ntl_ver}.sdc"
set s_constr(func.fast_min) "../syn/results/${ntl_ver}/${ntl_ver}.sdc"

foreach m [array names m_constr] {
    create_mode $m
}

foreach c [array names c_constr] {
    create_corner $c
}

foreach s [array names s_constr] {
    lassign [split $s "."] m c
    create_scenario \
        -name $s \
        -mode $m \
        -corner $c
}

# Functional mode.
current_mode func

# Slow/max corner
current_corner slow_max

set_parasitic_parameters \
    -early_spec maxTLU \
    -late_spec  maxTLU

catch {set_temperature 125.0}
catch {set_voltage 0.95 -object_list VDD}
catch {set_voltage 0.00 -object_list VSS}
catch {set_operating_conditions ss0p95v125c}

# Fast/min corner
current_corner fast_min

set_parasitic_parameters \
    -early_spec minTLU \
    -late_spec  minTLU

catch {set_temperature 125.0}
catch {set_voltage 0.95 -object_list VDD}
catch {set_voltage 0.00 -object_list VSS}
catch {set_operating_conditions ff0p95v125c}

# Source SDC for each scenario
foreach s [array names s_constr] {
    current_scenario $s
    source $s_constr($s)
}

# Scenario status
set_scenario_status func.slow_max \
    -active true \
    -setup true \
    -hold false \
    -leakage_power true \
    -dynamic_power true

set_scenario_status func.fast_min \
    -active true \
    -setup false \
    -hold true \
    -leakage_power false \
    -dynamic_power false

redirect -file ${REPORT_DIR}/02_mcmm_scenarios.rpt {
    report_scenarios
}

redirect -file ${REPORT_DIR}/03_check_timing_mcmm.rpt {
    puts "===== check_timing: func.slow_max ====="
    current_scenario func.slow_max
    check_timing

    puts "===== check_timing: func.fast_min ====="
    current_scenario func.fast_min
    check_timing
}

############################################################
# 7. DOM / SCA physical-security preservation rules
############################################################
# random_bits nets are intentionally NOT dont_touch.
# They had max-cap violations, so ICC2 must be allowed to buffer them.

if {$USE_DOM_SECURITY_RULES} {

    puts "INFO: Applying DOM/SCA + AHB-DMA physical-security rules."

    set sbox_cells        [get_cells -hierarchical -quiet *sbox*]
    set sbox_gen_cells    [get_cells -hierarchical -quiet *sbox_gen*]
    set inv_cells         [get_cells -hierarchical -quiet *inv_unit*]
    set mult_inv_cells    [get_cells -hierarchical -quiet *multiplicative_inverter_sca*]
    set dom_and_cells     [get_cells -hierarchical -quiet *dom_and_sca*]
    set gf2_cells         [get_cells -hierarchical -quiet *gf2_multiplier_sca*]
    set gf4_cells         [get_cells -hierarchical -quiet *gf4_multiplier_sca*]
    set gf4_inv_cells     [get_cells -hierarchical -quiet *gf4_inverter_sca*]

    ############################################################
    # Share-domain cell collections for DOM/SCA placement bounds
    ############################################################
    
    set share0_cells ""
    set share1_cells ""

    foreach pat {
        *state_reg_A_0*
        *state_reg_B_0*
        *round_key_reg_0*
        *key_reg_0*
        *sbox_buffer_0*
        *data_out_0*
        *subbytes_out_0*
        *mixcolumns_out_0*
        *round_data_out_0*
        *expanded_key_word_0*
        *data_in_0*
        *q_0*
        *a_0*
        *k_0*
        *q_inv_0*
    } {
        set tmp [get_cells -hierarchical -quiet $pat]
        if {[sizeof_collection $tmp] > 0} {
            set share0_cells [add_to_collection $share0_cells $tmp]
        }
    }

    foreach pat {
        *state_reg_A_1*
        *state_reg_B_1*
        *round_key_reg_1*
        *key_reg_1*
        *sbox_buffer_1*
        *data_out_1*
        *subbytes_out_1*
        *mixcolumns_out_1*
        *round_data_out_1*
        *expanded_key_word_1*
        *data_in_1*
        *q_1*
        *a_1*
        *k_1*
        *q_inv_1*
    } {
        set tmp [get_cells -hierarchical -quiet $pat]
        if {[sizeof_collection $tmp] > 0} {
            set share1_cells [add_to_collection $share1_cells $tmp]
        }
    }

    puts "INFO: SCA share0_cells = [sizeof_collection $share0_cells]"
    puts "INFO: SCA share1_cells = [sizeof_collection $share1_cells]"

    set dom_critical_cells [add_to_collection $dom_and_cells $mult_inv_cells]
    set dom_critical_cells [add_to_collection $dom_critical_cells $gf2_cells]
    set dom_critical_cells [add_to_collection $dom_critical_cells $gf4_cells]
    set dom_critical_cells [add_to_collection $dom_critical_cells $gf4_inv_cells]
    set dom_critical_cells [add_to_collection $dom_critical_cells $sbox_cells]
    set dom_critical_cells [add_to_collection $dom_critical_cells $sbox_gen_cells]
    set dom_critical_cells [add_to_collection $dom_critical_cells $inv_cells]

    if {[sizeof_collection $dom_critical_cells] > 0} {
        set_dont_touch $dom_critical_cells true
        puts "INFO: Applied set_dont_touch to DOM/SCA critical cells."
    } else {
        puts "WARNING: No DOM/SCA critical cells matched. Check synthesized hierarchy names."
    }

    if {[sizeof_collection $dom_critical_cells] > 0} {
        catch {
            set_freeze_ports -all $dom_critical_cells
            puts "INFO: Applied set_freeze_ports to DOM/SCA critical cells."
        }
    }

    ########################################################
    # Preserve security-critical nets, excluding random_bits
    ########################################################

    set random_nets       [get_nets -hierarchical -quiet *random_bits*]

    set mask_nets         [get_nets -hierarchical -quiet *mask*]
    set key_mask_nets     [get_nets -hierarchical -quiet *key_mask*]
    set data_mask_nets    [get_nets -hierarchical -quiet *data_mask*]

    set masked_key0_nets  [get_nets -hierarchical -quiet *masked_key_in_0*]
    set masked_key1_nets  [get_nets -hierarchical -quiet *masked_key_in_1*]

    set subbytes0_nets    [get_nets -hierarchical -quiet *subbytes_out_0*]
    set subbytes1_nets    [get_nets -hierarchical -quiet *subbytes_out_1*]

    set expanded0_nets    [get_nets -hierarchical -quiet *expanded_key_word_0*]
    set expanded1_nets    [get_nets -hierarchical -quiet *expanded_key_word_1*]

    set cross_comb_nets   [get_nets -hierarchical -quiet *cross_*_comb*]
    set inner0_nets       [get_nets -hierarchical -quiet *inner_0*]
    set inner1_nets       [get_nets -hierarchical -quiet *inner_1*]

    set dom_security_nets $mask_nets
    set dom_security_nets [add_to_collection $dom_security_nets $key_mask_nets]
    set dom_security_nets [add_to_collection $dom_security_nets $data_mask_nets]
    set dom_security_nets [add_to_collection $dom_security_nets $masked_key0_nets]
    set dom_security_nets [add_to_collection $dom_security_nets $masked_key1_nets]
    set dom_security_nets [add_to_collection $dom_security_nets $subbytes0_nets]
    set dom_security_nets [add_to_collection $dom_security_nets $subbytes1_nets]
    set dom_security_nets [add_to_collection $dom_security_nets $expanded0_nets]
    set dom_security_nets [add_to_collection $dom_security_nets $expanded1_nets]
    set dom_security_nets [add_to_collection $dom_security_nets $cross_comb_nets]
    set dom_security_nets [add_to_collection $dom_security_nets $inner0_nets]
    set dom_security_nets [add_to_collection $dom_security_nets $inner1_nets]

    if {[sizeof_collection $dom_security_nets] > 0} {
        set_dont_touch $dom_security_nets true
        puts "INFO: Applied set_dont_touch to DOM/SCA security nets, excluding random_bits."
    } else {
        puts "WARNING: No DOM/SCA security nets matched. Check net names after synthesis."
    }

    ########################################################
    # Preserve selected security registers
    ########################################################

    set state_regs        [get_cells -hierarchical -quiet *state_reg*]
    set cross_regs        [get_cells -hierarchical -quiet *cross_*_reg*]
    set inner_regs        [get_cells -hierarchical -quiet *inner_*_reg*]
    set sbox_buffer_regs  [get_cells -hierarchical -quiet *sbox_buffer*]

    set dom_security_regs [add_to_collection $state_regs $cross_regs]
    set dom_security_regs [add_to_collection $dom_security_regs $inner_regs]
    set dom_security_regs [add_to_collection $dom_security_regs $sbox_buffer_regs]

    if {[sizeof_collection $dom_security_regs] > 0} {
        set_dont_touch $dom_security_regs true
        puts "INFO: Applied set_dont_touch to DOM/SCA security registers."
    } else {
        puts "INFO: No DOM/SCA security registers matched."
    }

    ########################################################
    # Optional share soft bounds
    ########################################################

    if {$USE_DOM_SOFT_BOUNDS} {

        set SHARE0_BOUND {{20 20} {245 450}}
        set SHARE1_BOUND {{275 20} {500 450}}

        if {[sizeof_collection $share0_cells] > 0} {
            create_bound \
                -name BOUND_SHARE0 \
                -type soft \
                -boundary $SHARE0_BOUND \
                $share0_cells
        }

        if {[sizeof_collection $share1_cells] > 0} {
            create_bound \
                -name BOUND_SHARE1 \
                -type soft \
                -boundary $SHARE1_BOUND \
                $share1_cells
        }

    } else {
        puts "INFO: USE_DOM_SOFT_BOUNDS = 0. Skipping share bounds."
    }

    redirect -file ${REPORT_DIR}/04_dom_security_structure.rpt {
        puts "===== DOM/SCA + AHB-DMA physical-security structure report ====="
        puts "sbox_cells             : [sizeof_collection $sbox_cells]"
        puts "sbox_gen_cells         : [sizeof_collection $sbox_gen_cells]"
        puts "inv_cells              : [sizeof_collection $inv_cells]"
        puts "mult_inv_cells         : [sizeof_collection $mult_inv_cells]"
        puts "dom_and_cells          : [sizeof_collection $dom_and_cells]"
        puts "gf2_cells              : [sizeof_collection $gf2_cells]"
        puts "gf4_cells              : [sizeof_collection $gf4_cells]"
        puts "gf4_inv_cells          : [sizeof_collection $gf4_inv_cells]"
        puts "share0_cells           : [sizeof_collection $share0_cells]"
        puts "share1_cells           : [sizeof_collection $share1_cells]"
        puts "dom_critical_cells     : [sizeof_collection $dom_critical_cells]"
        puts "dom_security_nets      : [sizeof_collection $dom_security_nets]"
        puts "dom_security_regs      : [sizeof_collection $dom_security_regs]"
        puts "random_nets_not_locked : [sizeof_collection $random_nets]"
    }

} else {
    puts "INFO: USE_DOM_SECURITY_RULES = 0. Skipping DOM/SCA security rules."
}

############################################################
# 8. Site, routing direction, track, and routing layer setup
############################################################

set_attribute [get_site_defs unit] symmetry Y
set_attribute [get_site_defs unit] is_default true

set_attribute [get_layers {M1 M3 M5 M7 M9}] routing_direction horizontal
set_attribute [get_layers {M2 M4 M6 M8}]    routing_direction vertical

set_attribute [get_layers M1] track_offset 0.03
set_attribute [get_layers M2] track_offset 0.04

set_ignored_layers \
    -min_routing_layer M1 \
    -max_routing_layer M8

redirect -file ${REPORT_DIR}/05_ignored_layers.rpt {
    report_ignored_layers
}

############################################################
# 9. Initial floorplan
############################################################

initialize_floorplan \
    -side_ratio {1 1} \
    -core_offset {15} \
    -core_utilization 0.70

if {$USE_SHAPE_BLOCKS} {
    shape_blocks
} else {
    puts "INFO: USE_SHAPE_BLOCKS = 0. Skipping shape_blocks."
}

redirect -file ${REPORT_DIR}/06_floorplan_utilization.rpt {
    report_utilization
}

############################################################
# 10. Floorplan placement setup
############################################################

safe_set_app_option place.coarse.fix_hard_macros false
safe_set_app_option plan.place.auto_create_blockages auto
safe_set_app_option place.legalize.enable_prerouted_net_check true

############################################################
# 11. Coarse floorplan placement
############################################################

create_placement -floorplan

set hard_macros [get_flat_cells -quiet -filter "is_hard_macro == true"]

if {[sizeof_collection $hard_macros] > 0} {
    set_fixed_objects $hard_macros
    puts "INFO: Hard macros fixed."
} else {
    puts "INFO: No hard macros found. Skipping set_fixed_objects."
}

############################################################
# 12. Block pin placement
############################################################

set_block_pin_constraints \
    -self \
    -allowed_layers {M3 M4 M5 M6}

place_pins -self

############################################################
# 13. Power network cleanup
############################################################

remove_pg_strategies -all
remove_pg_patterns   -all

############################################################
# 14. Create and connect PG nets
############################################################

if {[sizeof_collection [get_nets -quiet VDD]] == 0} {
    create_net -power VDD
}

if {[sizeof_collection [get_nets -quiet VSS]] == 0} {
    create_net -ground VSS
}

connect_pg_net -automatic

set vdd_pins [get_pins -hierarchical -quiet */VDD]
set vss_pins [get_pins -hierarchical -quiet */VSS]

if {[sizeof_collection $vdd_pins] > 0} {
    connect_pg_net -net VDD $vdd_pins
}

if {[sizeof_collection $vss_pins] > 0} {
    connect_pg_net -net VSS $vss_pins
}

connect_pg_net -automatic

############################################################
# 15. PG via master rule
############################################################

set_pg_via_master_rule \
    -via_array_dimension {2 1} \
    pgvia_2x1

############################################################
# 16. PG patterns
############################################################

create_pg_ring_pattern ring_M5_M6 \
    -horizontal_layer M5 \
    -vertical_layer   M6 \
    -horizontal_width {3} \
    -vertical_width   {3} \
    -horizontal_spacing {2} \
    -vertical_spacing   {2}

create_pg_mesh_pattern M2_mesh \
    -layers { \
        {{vertical_layer : M2} {width : 0.25} {pitch : 30} {offset : 15} {trim : true}} \
    }

create_pg_mesh_pattern M7_M8_mesh \
    -layers { \
        {{horizontal_layer : M7} {width : 3} {spacing : interleaving} {offset : 20} {pitch : 40} {trim : true}} \
        {{vertical_layer   : M8} {width : 3} {spacing : interleaving} {offset : 20} {pitch : 40} {trim : true}} \
    }

create_pg_std_cell_conn_pattern P_std_cell_rail \
    -layers {M1}

############################################################
# 17. PG strategies
############################################################

set_pg_strategy core_pgring \
    -core \
    -pattern {{name : ring_M5_M6} {nets : {VDD VSS}} {offset : {2 2}}}

set_pg_strategy S_upper_mesh \
    -core \
    -pattern {{name : M7_M8_mesh} {nets : {VDD VSS}}} \
    -extension {{{stop : design_boundary_and_generate_pin}}}

set_pg_strategy S_m2_straps \
    -core \
    -pattern {{name : M2_mesh} {nets : {VDD VSS}}} \
    -extension {{{stop : design_boundary_and_generate_pin}}}

set_pg_strategy S_std_rails \
    -core \
    -pattern {{name : P_std_cell_rail} {nets : {VDD VSS}}} \
    -extension {{{stop : core_boundary}}}

############################################################
# 18. Compile PG
############################################################

if {$USE_EXPLICIT_PG_VIA_RULES} {

    set_pg_strategy_via_rule R_upper_to_m2 \
        -via_rule { \
            {{strategies: S_m2_straps} {layers: M2} {strategies: S_upper_mesh} {layers: M7}} \
        }

    set_pg_strategy_via_rule R_m2_to_rails \
        -via_rule { \
            {{strategies: S_std_rails} {layers: M1} {strategies: S_m2_straps} {layers: M2} {via_master: VIA12SQ_C}} \
        }

    compile_pg \
        -strategies {core_pgring S_upper_mesh S_m2_straps S_std_rails} \
        -via_rule   {R_upper_to_m2 R_m2_to_rails}

} else {

    puts "INFO: USE_EXPLICIT_PG_VIA_RULES = 0. Running compile_pg without explicit via rules."

    compile_pg \
        -strategies {core_pgring S_upper_mesh S_m2_straps S_std_rails}
}

connect_pg_net -automatic

############################################################
# 19. Pre-place power-grid checks
############################################################

redirect -file ${REPORT_DIR}/07_pre_place_pg_connectivity.rpt {
    check_pg_connectivity
}

redirect -file ${REPORT_DIR}/08_pre_place_pg_drc_ignore_std_cells.rpt {
    check_pg_drc -ignore_std_cells
}

############################################################
# 20. Write floorplan output and save checkpoint
############################################################

write_floorplan -force \
    -output ${OUTPUT_DIR}/${ntl_ver}.fp

save_block -as ${ntl_ver}_after_floorplan
save_lib

############################################################
# 21. Pre-placement checks
############################################################

redirect -file ${REPORT_DIR}/09_check_design_pre_place.rpt {
    check_design -checks pre_placement_stage
    check_design -checks physical_constraints
}

redirect -file ${REPORT_DIR}/10_pre_place_qor.rpt {
    report_qor -summary
    report_utilization
}

############################################################
# 22. Placement QoR / hold setup
############################################################

safe_set_app_option place.coarse.enhanced_auto_density_control true
safe_set_app_option opt.common.hold_effort high

############################################################
# 23. Placement and optimization
############################################################

place_opt

############################################################
# 23a. Post-place PG reconnect, rail repair, and filler insertion
############################################################

connect_pg_net -automatic

compile_pg \
    -strategies {S_std_rails}

connect_pg_net -automatic

create_stdcell_fillers \
    -lib_cells $FILLER_CELLS

connect_pg_net -automatic

redirect -file ${REPORT_DIR}/11a_post_place_pg_connectivity.rpt {
    check_pg_connectivity
}

redirect -file ${REPORT_DIR}/11b_post_place_pg_drc_ignore_std_cells.rpt {
    check_pg_drc -ignore_std_cells
}

save_block -as ${ntl_ver}_after_place_opt
save_lib

############################################################
# 24. Post-placement QoR reports
############################################################

redirect -file ${REPORT_DIR}/11_post_place_qor.rpt {
    report_qor -summary
    report_utilization
}

############################################################
# 24a. Post-placement setup/hold timing reports
############################################################

redirect -file ${REPORT_DIR}/12_post_place_timing_mcmm.rpt {

    puts "===== setup timing: func.slow_max ====="
    current_scenario func.slow_max

    report_timing \
        -delay_type max \
        -path_type full \
        -max_paths 20

    puts "===== setup constraints: func.slow_max ====="
    catch {
        report_constraints \
            -max_delay \
            -all_violators
    } setup_const_msg

    if {$setup_const_msg ne ""} {
        puts "INFO/WARNING from setup constraint report:"
        puts $setup_const_msg
    }

    puts "===== hold timing: func.fast_min ====="
    current_scenario func.fast_min

    report_timing \
        -delay_type min \
        -path_type full \
        -max_paths 20

    puts "===== hold constraints: func.fast_min ====="
    catch {
        report_constraints \
            -min_delay \
            -all_violators
    } hold_const_msg

    if {$hold_const_msg ne ""} {
        puts "INFO/WARNING from hold constraint report:"
        puts $hold_const_msg
    }
}

############################################################
# 24b. Post-placement DRV reports
############################################################

redirect -file ${REPORT_DIR}/12a_post_place_drv.rpt {

    puts "===== DRV constraints: func.slow_max ====="
    current_scenario func.slow_max

    catch {
        report_constraints \
            -max_capacitance \
            -max_transition \
            -all_violators
    } drv_slow_msg

    if {$drv_slow_msg ne ""} {
        puts "INFO/WARNING from slow DRV report:"
        puts $drv_slow_msg
    }

    puts "===== DRV constraints: func.fast_min ====="
    current_scenario func.fast_min

    catch {
        report_constraints \
            -max_capacitance \
            -max_transition \
            -all_violators
    } drv_fast_msg

    if {$drv_fast_msg ne ""} {
        puts "INFO/WARNING from fast DRV report:"
        puts $drv_fast_msg
    }
}

############################################################
# 24c. DOM/SCA post-placement report
############################################################

if {$USE_DOM_SECURITY_RULES} {
    redirect -file ${REPORT_DIR}/13_post_place_dom_security.rpt {
        puts "===== Post-placement DOM/SCA security report ====="
        puts "dom_critical_cells     : [sizeof_collection $dom_critical_cells]"
        puts "dom_security_nets      : [sizeof_collection $dom_security_nets]"
        puts "dom_security_regs      : [sizeof_collection $dom_security_regs]"
        puts "random_nets_not_locked : [sizeof_collection $random_nets]"
        puts "share0_cells           : [sizeof_collection $share0_cells]"
        puts "share1_cells           : [sizeof_collection $share1_cells]"
        report_utilization
        report_qor -summary
    }
}

############################################################
# 25. Post-placement congestion analysis
############################################################

route_global \
    -effort_level high \
    -congestion_map_only true

redirect -file ${REPORT_DIR}/14_post_place_congestion.rpt {
    report_congestion
}

############################################################
# 26. Final stage status summary
############################################################

redirect -file ${REPORT_DIR}/15_stage_status_summary.rpt {
    puts "===== Floorplan/Placement Stage Summary ====="
    puts "PG connectivity: check 11a_post_place_pg_connectivity.rpt"
    puts "PG DRC: check 11b_post_place_pg_drc_ignore_std_cells.rpt"
    puts "Timing: setup should be clean; hold may need CTS/post-CTS repair"
    puts "DRV: review 12a_post_place_drv.rpt"
    puts "Congestion: check 14_post_place_congestion.rpt"
    puts "DOM/SCA: check 13_post_place_dom_security.rpt"
}

############################################################
# 27. Final checkpoint
############################################################

save_block -as ${ntl_ver}_final_floorplan_place
save_lib

############################################################
# End of script
############################################################

# exit
