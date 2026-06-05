############################################################
# ICC2 CTS Script
# DOM-based AES-CTR AHB-Lite DMA SCA Accelerator
#
# Input block:
#   ${ntl_ver}_final_floorplan_place
#
# Output block:
#   ${ntl_ver}_after_cts
#
# Report numbering starts at 16 because placement ended at:
#   15_stage_status_summary.rpt
#
# Notes:
# - Starts from saved floorplan/place block.
# - Does NOT read Verilog again.
# - Does NOT redo floorplan/place.
# - Removes fillers before CTS.
# - Does NOT reinsert fillers during CTS.
# - Uses classic CTS by default for balanced clock delivery.
# - CCD is optional and disabled by default for DOM/SCA stability.
############################################################

source ./scripts/icc2_lib_setup.tcl

set mode    $env(MODE)
set version $env(VER)
set ntl_ver $env(DESIGN_VER)

############################################################
# 0. User switches
############################################################

set INPUT_BLOCK  ${ntl_ver}_final_floorplan_place
set OUTPUT_BLOCK ${ntl_ver}_after_cts

set USE_DOM_SECURITY_RULES 1
set USE_CCD 0
set USE_RESTRICT_CTS_LIBCELLS 0
set USE_CLOCK_NDR 0

# Do not insert fillers in CTS stage.
# Fillers can be inserted later after legal CTS / route_opt.
set INSERT_FILLERS_IN_CTS 0

set FILLER_CELLS {saed32hvt/SHFILL*}

if {$USE_CCD} {
    set CTS_FLOW_NAME "CCD"
} else {
    set CTS_FLOW_NAME "Classic CTS"
}


############################################################
# AHB-Lite DMA wrapper notes
############################################################
# Starts from the placed wrapper block:
#   ${ntl_ver}_final_floorplan_place
# Produces the CTS wrapper block:
#   ${ntl_ver}_after_cts
############################################################

############################################################
# 1. Directory setup
############################################################

set OUTPUT_DIR ./results/${ntl_ver}
set REPORT_DIR ${OUTPUT_DIR}/reports

file mkdir $OUTPUT_DIR
file mkdir $REPORT_DIR

############################################################
# 2. Helper procedures
############################################################

proc safe_set_app_option {opt val} {
    if {[catch {set_app_options -name $opt -value $val} msg]} {
        puts "WARNING: Could not set app option $opt to $val"
        puts "WARNING: $msg"
    } else {
        puts "INFO: Set app option $opt = $val"
    }
}

proc remove_all_fillers {} {
    puts "INFO: Removing standard-cell fillers."

    catch {
        remove_stdcell_fillers
    } remove_fill_msg

    puts "INFO/WARNING from remove_stdcell_fillers:"
    puts $remove_fill_msg

    set filler_by_ref_hier [get_cells -hierarchical -quiet -filter "ref_name =~ SHFILL*"]
    set filler_by_ref_flat [get_flat_cells -quiet -filter "ref_name =~ SHFILL*"]
    set filler_by_name_hier [get_cells -hierarchical -quiet xofiller*]
    set filler_by_name_flat [get_flat_cells -quiet xofiller*]

    set all_fillers [add_to_collection $filler_by_ref_hier $filler_by_ref_flat]
    set all_fillers [add_to_collection $all_fillers $filler_by_name_hier]
    set all_fillers [add_to_collection $all_fillers $filler_by_name_flat]

    puts "INFO: Remaining filler-like cells found: [sizeof_collection $all_fillers]"

    if {[sizeof_collection $all_fillers] > 0} {
        remove_cells $all_fillers
        puts "INFO: Removed remaining filler-like cells."
    }

    set filler_check1 [get_cells -hierarchical -quiet -filter "ref_name =~ SHFILL*"]
    set filler_check2 [get_flat_cells -quiet -filter "ref_name =~ SHFILL*"]
    set filler_check [add_to_collection $filler_check1 $filler_check2]

    puts "INFO: Filler-like cells after cleanup: [sizeof_collection $filler_check]"
}

############################################################
# 3. Open saved placement block
############################################################

puts "INFO: Opening input block: $INPUT_BLOCK"

open_block $INPUT_BLOCK
current_block

redirect -file ${REPORT_DIR}/16_opened_block_summary.rpt {
    puts "Input block  : $INPUT_BLOCK"
    puts "Output block : $OUTPUT_BLOCK"
    report_design -summary
    report_utilization
}

############################################################
# 4. Check existing MCMM scenarios
############################################################

set slow_scen [get_scenarios -quiet func.slow_max]
set fast_scen [get_scenarios -quiet func.fast_min]

if {[sizeof_collection $slow_scen] == 0} {
    puts "WARNING: Scenario func.slow_max not found."
}

if {[sizeof_collection $fast_scen] == 0} {
    puts "WARNING: Scenario func.fast_min not found."
}

if {[sizeof_collection $slow_scen] > 0} {
    set_scenario_status func.slow_max \
        -active true \
        -setup true \
        -hold false \
        -leakage_power true \
        -dynamic_power true
}

if {[sizeof_collection $fast_scen] > 0} {
    set_scenario_status func.fast_min \
        -active true \
        -setup false \
        -hold true \
        -leakage_power false \
        -dynamic_power false
}

redirect -file ${REPORT_DIR}/17_mcmm_scenarios.rpt {
    report_scenarios
}

############################################################
# 5. Pre-CTS checks
############################################################

redirect -file ${REPORT_DIR}/18_pre_cts_check_design.rpt {
    check_design -checks pre_clock_tree_stage
}

redirect -file ${REPORT_DIR}/19_pre_cts_qor.rpt {
    report_qor -summary
    report_utilization
}

redirect -file ${REPORT_DIR}/20_pre_cts_timing.rpt {
    if {[sizeof_collection $slow_scen] > 0} {
        current_scenario func.slow_max
        puts "===== Pre-CTS setup timing: func.slow_max ====="
        report_timing \
            -delay_type max \
            -path_type full \
            -max_paths 20

        puts "===== Pre-CTS setup constraints: func.slow_max ====="
        catch {
            report_constraints \
                -max_delay \
                -all_violators
        } setup_pre_msg
        puts $setup_pre_msg
    }

    if {[sizeof_collection $fast_scen] > 0} {
        current_scenario func.fast_min
        puts "===== Pre-CTS hold timing: func.fast_min ====="
        report_timing \
            -delay_type min \
            -path_type full \
            -max_paths 20

        puts "===== Pre-CTS hold constraints: func.fast_min ====="
        catch {
            report_constraints \
                -min_delay \
                -all_violators
        } hold_pre_msg
        puts $hold_pre_msg
    }
}

redirect -file ${REPORT_DIR}/21_pre_cts_drv.rpt {
    if {[sizeof_collection $slow_scen] > 0} {
        current_scenario func.slow_max
        puts "===== Pre-CTS DRV: func.slow_max ====="
        catch {
            report_constraints \
                -max_capacitance \
                -max_transition \
                -all_violators
        } drv_slow_pre_msg
        puts $drv_slow_pre_msg
    }

    if {[sizeof_collection $fast_scen] > 0} {
        current_scenario func.fast_min
        puts "===== Pre-CTS DRV: func.fast_min ====="
        catch {
            report_constraints \
                -max_capacitance \
                -max_transition \
                -all_violators
        } drv_fast_pre_msg
        puts $drv_fast_pre_msg
    }
}

############################################################
# 6. Remove fillers before CTS
############################################################

remove_all_fillers

connect_pg_net -automatic

redirect -file ${REPORT_DIR}/22_pre_cts_pg_connectivity.rpt {
    check_pg_connectivity
}

redirect -file ${REPORT_DIR}/23_pre_cts_pg_drc_ignore_std_cells.rpt {
    check_pg_drc -ignore_std_cells
}

redirect -file ${REPORT_DIR}/23a_pre_cts_util_after_filler_removal.rpt {
    puts "===== Utilization after filler removal, before CTS ====="
    report_utilization
}

redirect -file ${REPORT_DIR}/23b_pre_cts_filler_check.rpt {
    set f1 [get_cells -hierarchical -quiet -filter "ref_name =~ SHFILL*"]
    set f2 [get_flat_cells -quiet -filter "ref_name =~ SHFILL*"]
    set f3 [get_cells -hierarchical -quiet xofiller*]
    set f4 [get_flat_cells -quiet xofiller*]
    set ff [add_to_collection $f1 $f2]
    set ff [add_to_collection $ff $f3]
    set ff [add_to_collection $ff $f4]
    puts "Remaining filler-like cells before CTS: [sizeof_collection $ff]"
}

############################################################
# 7. DOM/SCA + AHB-DMA pre-CTS structure report
############################################################

if {$USE_DOM_SECURITY_RULES} {

    set sbox_cells        [get_cells -hierarchical -quiet *sbox*]
    set sbox_gen_cells    [get_cells -hierarchical -quiet *sbox_gen*]
    set inv_cells         [get_cells -hierarchical -quiet *inv_unit*]
    set mult_inv_cells    [get_cells -hierarchical -quiet *multiplicative_inverter_sca*]
    set dom_and_cells     [get_cells -hierarchical -quiet *dom_and_sca*]
    set gf2_cells         [get_cells -hierarchical -quiet *gf2_multiplier_sca*]
    set gf4_cells         [get_cells -hierarchical -quiet *gf4_multiplier_sca*]
    set gf4_inv_cells     [get_cells -hierarchical -quiet *gf4_inverter_sca*]

    set share0_cells      [get_cells -hierarchical -quiet *_0*]
    set share1_cells      [get_cells -hierarchical -quiet *_1*]

    set random_nets       [get_nets -hierarchical -quiet *random_bits*]

    set mask_nets         [get_nets -hierarchical -quiet *mask*]
    set key_mask_nets     [get_nets -hierarchical -quiet *key_mask*]
    set data_mask_nets    [get_nets -hierarchical -quiet *data_mask*]

    set state_regs        [get_cells -hierarchical -quiet *state_reg*]
    set cross_regs        [get_cells -hierarchical -quiet *cross_*_reg*]
    set inner_regs        [get_cells -hierarchical -quiet *inner_*_reg*]
    set sbox_buffer_regs  [get_cells -hierarchical -quiet *sbox_buffer*]

    redirect -file ${REPORT_DIR}/24_dom_security_pre_cts.rpt {
        puts "===== DOM/SCA + AHB-DMA pre-CTS structure report ====="
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
        puts "random_nets_not_locked : [sizeof_collection $random_nets]"
        puts "mask_nets              : [sizeof_collection $mask_nets]"
        puts "key_mask_nets          : [sizeof_collection $key_mask_nets]"
        puts "data_mask_nets         : [sizeof_collection $data_mask_nets]"
        puts "state_regs             : [sizeof_collection $state_regs]"
        puts "cross_regs             : [sizeof_collection $cross_regs]"
        puts "inner_regs             : [sizeof_collection $inner_regs]"
        puts "sbox_buffer_regs       : [sizeof_collection $sbox_buffer_regs]"
    }
}

############################################################
# 8. Clock structure reports
############################################################

redirect -file ${REPORT_DIR}/25_clock_structure_pre_cts.rpt {
    puts "===== clocks ====="
    report_clocks

    puts "===== case analysis ====="
    report_case_analysis

    puts "===== disabled timing arcs ====="
    report_disable_timing

    puts "===== clock balance points ====="
    catch {
        report_clock_balance_points
    } cbp_msg
    puts $cbp_msg

    puts "===== clock tree options ====="
    catch {
        report_clock_tree_options
    } cto_msg
    puts $cto_msg
}

############################################################
# 9. CTS setup
############################################################

if {$USE_CCD} {
    safe_set_app_option clock_opt.flow.enable_ccd true
    safe_set_app_option ccd.hold_control_effort high
} else {
    safe_set_app_option clock_opt.flow.enable_ccd false
}

safe_set_app_option cts.common.enable_auto_exceptions true
safe_set_app_option cts.common.verbose 1

# Important change:
# false gives legalizer/CTS more freedom. The previous result still had
# hundreds of overlap violations after CTS.
safe_set_app_option cts.compile.fix_clock_tree_sinks false

safe_set_app_option cts.compile.enable_cell_relocation timing_aware

safe_set_app_option clock_opt.place.effort high
safe_set_app_option clock_opt.congestion.effort high
safe_set_app_option opt.common.hold_effort high

safe_set_app_option cts.compile.remove_existing_clock_trees true

# Stronger legalizer behavior.
safe_set_app_option place.legalize.enable_advanced_legalizer true
safe_set_app_option place.legalize.always_continue false

############################################################
# 10. Optional CTS lib-cell restriction
############################################################

if {$USE_RESTRICT_CTS_LIBCELLS} {

    set cts_libcells [get_lib_cells -quiet { \
        saed32hvt/*BUF* \
        saed32hvt/*INV* \
        saed32hvt/*CK*  \
        saed32hvt/*CG*  \
    }]

    redirect -file ${REPORT_DIR}/26_cts_setup_options.rpt {
        puts "===== CTS lib cells ====="
        puts "CTS libcell count: [sizeof_collection $cts_libcells]"
        if {[sizeof_collection $cts_libcells] > 0} {
            report_lib_cells $cts_libcells
        }
    }

    if {[sizeof_collection $cts_libcells] > 0} {
        set_lib_cell_purpose -exclude cts [get_lib_cells]
        set_lib_cell_purpose -include cts $cts_libcells
        set_dont_touch $cts_libcells false
    } else {
        puts "WARNING: USE_RESTRICT_CTS_LIBCELLS=1 but no CTS lib cells matched."
        puts "WARNING: CTS cell restriction skipped."
    }

} else {
    redirect -file ${REPORT_DIR}/26_cts_setup_options.rpt {
        puts "USE_RESTRICT_CTS_LIBCELLS = 0"
        puts "CTS lib-cell restriction skipped."
    }
}

############################################################
# 11. Optional clock NDR / routing rule setup
############################################################

if {$USE_CLOCK_NDR} {

    catch {
        create_routing_rule CLK_NDR_M4_M6 \
            -widths   {M4 0.14 M5 0.14 M6 0.14} \
            -spacings {M4 0.28 M5 0.28 M6 0.28}
    } ndr_msg

    puts "INFO/WARNING from create_routing_rule CLK_NDR_M4_M6:"
    puts $ndr_msg

    catch {
        set_clock_routing_rules \
            -rules CLK_NDR_M4_M6 \
            -min_routing_layer M4 \
            -max_routing_layer M6
    } clock_rule_msg

    puts "INFO/WARNING from set_clock_routing_rules with NDR:"
    puts $clock_rule_msg

} else {
    puts "INFO: USE_CLOCK_NDR = 0. No explicit clock routing rule applied."
}

redirect -append -file ${REPORT_DIR}/26_cts_setup_options.rpt {
    puts ""
    puts "===== CTS app options ====="

    catch {
        report_app_options clock_opt.*
    } clock_opt_msg
    puts $clock_opt_msg

    catch {
        report_app_options cts.*
    } cts_msg
    puts $cts_msg

    puts ""
    puts "===== clock routing rules ====="
    catch {
        report_clock_routing_rules
    } rcr_msg
    puts $rcr_msg

    puts ""
    puts "===== clock tree options ====="
    catch {
        report_clock_tree_options
    } rcto_msg
    puts $rcto_msg

    puts ""
    puts "===== clock balance points ====="
    catch {
        report_clock_balance_points
    } rcbp_msg
    puts $rcbp_msg
}

############################################################
# 12. CTS stage 1: build clock
############################################################

clock_opt \
    -to build_clock

legalize_placement

redirect -file ${REPORT_DIR}/27_after_build_clock_qor.rpt {
    report_qor -summary
    report_utilization
}

redirect -file ${REPORT_DIR}/28_after_build_clock_clock_qor.rpt {
    puts "===== clock QoR after build_clock ====="
    catch {
        report_clock_qor -type summary
    } rcq_build_msg
    puts $rcq_build_msg

    puts "===== clock timing/skew after build_clock ====="
    catch {
        report_clock_timing -type skew
    } rct_build_msg
    puts $rct_build_msg
}

redirect -file ${REPORT_DIR}/28a_after_build_clock_legality.rpt {
    check_legality
    report_utilization
}

save_block -as ${ntl_ver}_cts_build_clock
save_lib

############################################################
# 13. CTS stage 2: route clock
############################################################

clock_opt \
    -from route_clock \
    -to route_clock

catch {
    compute_clock_latency
} compute_lat_msg

puts "INFO/WARNING from compute_clock_latency:"
puts $compute_lat_msg

legalize_placement

redirect -file ${REPORT_DIR}/29_after_route_clock_qor.rpt {
    report_qor -summary
    report_utilization
}

redirect -file ${REPORT_DIR}/30_after_route_clock_clock_qor.rpt {
    puts "===== clock QoR after route_clock ====="
    catch {
        report_clock_qor -type summary
    } rcq_route_msg
    puts $rcq_route_msg

    puts "===== clock timing/skew after route_clock ====="
    catch {
        report_clock_timing -type skew
    } rct_route_msg
    puts $rct_route_msg
}

redirect -file ${REPORT_DIR}/30a_after_route_clock_legality.rpt {
    check_legality
    report_utilization
}

save_block -as ${ntl_ver}_cts_route_clock
save_lib

############################################################
# 14. CTS stage 3: final optimization
############################################################

clock_opt \
    -from final_opto

# Do not insert fillers here.
# Just legalize CTS and optimization cells.
legalize_placement

redirect -file ${REPORT_DIR}/31a_post_cts_check_legality.rpt {
    check_legality
    report_utilization
}

save_block -as ${ntl_ver}_cts_final_opto
save_lib

############################################################
# 15. Post-CTS PG repair
############################################################

# Make sure fillers are still absent.
remove_all_fillers

connect_pg_net -automatic

catch {
    compile_pg -strategies {S_std_rails}
} pg_rail_msg

puts "INFO/WARNING from post-CTS compile_pg S_std_rails:"
puts $pg_rail_msg

connect_pg_net -automatic

redirect -file ${REPORT_DIR}/31_post_cts_pg_connectivity.rpt {
    check_pg_connectivity
}

redirect -file ${REPORT_DIR}/32_post_cts_pg_drc_ignore_std_cells.rpt {
    check_pg_drc -ignore_std_cells
}

redirect -file ${REPORT_DIR}/32a_post_cts_filler_check.rpt {
    set f1 [get_cells -hierarchical -quiet -filter "ref_name =~ SHFILL*"]
    set f2 [get_flat_cells -quiet -filter "ref_name =~ SHFILL*"]
    set f3 [get_cells -hierarchical -quiet xofiller*]
    set f4 [get_flat_cells -quiet xofiller*]
    set ff [add_to_collection $f1 $f2]
    set ff [add_to_collection $ff $f3]
    set ff [add_to_collection $ff $f4]
    puts "Remaining filler-like cells after CTS: [sizeof_collection $ff]"
}

############################################################
# 16. Post-CTS QoR, timing, and DRV reports
############################################################

redirect -file ${REPORT_DIR}/33_post_cts_qor.rpt {
    report_qor -summary
    report_utilization
}

redirect -file ${REPORT_DIR}/34_post_cts_timing.rpt {
    if {[sizeof_collection $slow_scen] > 0} {
        current_scenario func.slow_max
        puts "===== Post-CTS setup timing: func.slow_max ====="
        report_timing \
            -delay_type max \
            -path_type full \
            -max_paths 30

        puts "===== Post-CTS setup constraints: func.slow_max ====="
        catch {
            report_constraints \
                -max_delay \
                -all_violators
        } setup_post_msg
        puts $setup_post_msg
    }

    if {[sizeof_collection $fast_scen] > 0} {
        current_scenario func.fast_min
        puts "===== Post-CTS hold timing: func.fast_min ====="
        report_timing \
            -delay_type min \
            -path_type full \
            -max_paths 30

        puts "===== Post-CTS hold constraints: func.fast_min ====="
        catch {
            report_constraints \
                -min_delay \
                -all_violators
        } hold_post_msg
        puts $hold_post_msg
    }
}

redirect -file ${REPORT_DIR}/35_post_cts_drv.rpt {
    if {[sizeof_collection $slow_scen] > 0} {
        current_scenario func.slow_max
        puts "===== Post-CTS DRV: func.slow_max ====="
        catch {
            report_constraints \
                -max_capacitance \
                -max_transition \
                -all_violators
        } drv_slow_post_msg
        puts $drv_slow_post_msg
    }

    if {[sizeof_collection $fast_scen] > 0} {
        current_scenario func.fast_min
        puts "===== Post-CTS DRV: func.fast_min ====="
        catch {
            report_constraints \
                -max_capacitance \
                -max_transition \
                -all_violators
        } drv_fast_post_msg
        puts $drv_fast_post_msg
    }
}

redirect -file ${REPORT_DIR}/36_post_cts_clock_qor.rpt {
    puts "===== post-CTS clock QoR ====="
    catch {
        report_clock_qor -type summary
    } rcq_post_msg
    puts $rcq_post_msg

    puts "===== post-CTS clock timing/skew ====="
    catch {
        report_clock_timing -type skew
    } rct_post_msg
    puts $rct_post_msg

    puts "===== post-CTS clock balance points ====="
    catch {
        report_clock_balance_points
    } rbp_post_msg
    puts $rbp_post_msg

    puts "===== post-CTS clock tree options ====="
    catch {
        report_clock_tree_options
    } rto_post_msg
    puts $rto_post_msg
}

redirect -file ${REPORT_DIR}/36a_sca_register_clock_timing.rpt {
    puts "===== Clock timing to share 0 registers ====="

    foreach pat {
        *state_reg_A_0*
        *state_reg_B_0*
        *round_key_reg_0*
        *key_reg_0*
        *sbox_buffer_0*
    } {
        set regs [get_cells -hierarchical -quiet $pat]
        if {[sizeof_collection $regs] > 0} {
            puts ""
            puts "Pattern: $pat"
            catch {report_clock_timing -to $regs -type skew} msg
            puts $msg
        }
    }

    puts ""
    puts "===== Clock timing to share 1 registers ====="

    foreach pat {
        *state_reg_A_1*
        *state_reg_B_1*
        *round_key_reg_1*
        *key_reg_1*
        *sbox_buffer_1*
    } {
        set regs [get_cells -hierarchical -quiet $pat]
        if {[sizeof_collection $regs] > 0} {
            puts ""
            puts "Pattern: $pat"
            catch {report_clock_timing -to $regs -type skew} msg
            puts $msg
        }
    }
}

############################################################
# 17. Post-CTS DOM/SCA report
############################################################

if {$USE_DOM_SECURITY_RULES} {
    redirect -file ${REPORT_DIR}/37_post_cts_dom_security.rpt {
        puts "===== DOM/SCA post-CTS structure report ====="
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
        puts "random_nets_not_locked : [sizeof_collection $random_nets]"
        puts "mask_nets              : [sizeof_collection $mask_nets]"
        puts "key_mask_nets          : [sizeof_collection $key_mask_nets]"
        puts "data_mask_nets         : [sizeof_collection $data_mask_nets]"
        puts "state_regs             : [sizeof_collection $state_regs]"
        puts "cross_regs             : [sizeof_collection $cross_regs]"
        puts "inner_regs             : [sizeof_collection $inner_regs]"
        puts "sbox_buffer_regs       : [sizeof_collection $sbox_buffer_regs]"
    }
}

############################################################
# 18. Post-CTS congestion check
############################################################

route_global \
    -effort_level high \
    -congestion_map_only true

redirect -file ${REPORT_DIR}/38_post_cts_congestion.rpt {
    report_congestion
}

############################################################
# 19. Pre-route readiness check
############################################################

redirect -file ${REPORT_DIR}/39_check_design_pre_route.rpt {
    check_design -checks pre_route_stage
}

############################################################
# 20. CTS stage summary
############################################################

redirect -file ${REPORT_DIR}/40_cts_stage_summary.rpt {
    puts "===== CTS Stage Summary ====="
    puts "Input block        : $INPUT_BLOCK"
    puts "Output block       : $OUTPUT_BLOCK"
    puts "CTS flow           : $CTS_FLOW_NAME"
    puts ""
    puts "Important legality reports:"
    puts "  28a_after_build_clock_legality.rpt"
    puts "  30a_after_route_clock_legality.rpt"
    puts "  31a_post_cts_check_legality.rpt"
    puts ""
    puts "Main reports:"
    puts "  18_pre_cts_check_design.rpt"
    puts "  20_pre_cts_timing.rpt"
    puts "  21_pre_cts_drv.rpt"
    puts "  31_post_cts_pg_connectivity.rpt"
    puts "  32_post_cts_pg_drc_ignore_std_cells.rpt"
    puts "  33_post_cts_qor.rpt"
    puts "  34_post_cts_timing.rpt"
    puts "  35_post_cts_drv.rpt"
    puts "  36_post_cts_clock_qor.rpt"
    puts "  37_post_cts_dom_security.rpt"
    puts "  38_post_cts_congestion.rpt"
    puts "  39_check_design_pre_route.rpt"
    puts ""
    puts "Note:"
    puts "  Fillers are intentionally not inserted in this CTS script."
    puts "  Insert fillers later only after CTS legality is clean."
}

############################################################
# 21. Save final CTS checkpoint
############################################################

save_block -as $OUTPUT_BLOCK
save_lib

############################################################
# End of CTS script
############################################################

# exit
