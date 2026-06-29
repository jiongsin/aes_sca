# ICC2 routing and post-route optimization script for the AES PNR flow.
# Opens the post-CTS AES block, applies routing/security options, performs signal routing and route optimization, checks timing/DRC, inserts fillers, and saves the routed block.

source ./scripts/icc2_lib_setup.tcl

set mode    $env(MODE)
set version $env(VER)
set ntl_ver $env(DESIGN_VER)

set INPUT_BLOCK  ${ntl_ver}_after_cts
set OUTPUT_BLOCK ${ntl_ver}_after_route

set USE_DOM_SECURITY_RULES 1

set USE_POST_ROUTE_CCD 0

set USE_POST_ROUTE_POWER_OPT 0

set USE_ANTENNA_RULES 1
set ANTENNA_RULE_FILE /data/synopsys/lib/saed32nm/lib/tech/milkyway/saed32nm_ant_1p9m.tcl

set INSERT_FILLERS_AFTER_ROUTE 1
set FILLER_CELLS {saed32hvt/SHFILL*}

set OUTPUT_DIR ./results/${ntl_ver}
set REPORT_DIR ${OUTPUT_DIR}/reports

file mkdir $OUTPUT_DIR
file mkdir $REPORT_DIR

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

    set filler_by_ref_hier  [get_cells -hierarchical -quiet -filter "ref_name =~ SHFILL*"]
    set filler_by_ref_flat  [get_flat_cells -quiet -filter "ref_name =~ SHFILL*"]
    set filler_by_name_hier [get_cells -hierarchical -quiet xofiller*]
    set filler_by_name_flat [get_flat_cells -quiet xofiller*]

    set all_fillers [add_to_collection $filler_by_ref_hier $filler_by_ref_flat]
    set all_fillers [add_to_collection $all_fillers $filler_by_name_hier]
    set all_fillers [add_to_collection $all_fillers $filler_by_name_flat]

    puts "INFO: Filler-like cells found: [sizeof_collection $all_fillers]"

    if {[sizeof_collection $all_fillers] > 0} {
        remove_cells $all_fillers
        puts "INFO: Removed filler-like cells."
    }

    set filler_check1 [get_cells -hierarchical -quiet -filter "ref_name =~ SHFILL*"]
    set filler_check2 [get_flat_cells -quiet -filter "ref_name =~ SHFILL*"]
    set filler_check [add_to_collection $filler_check1 $filler_check2]

    puts "INFO: Filler-like cells after cleanup: [sizeof_collection $filler_check]"
}

puts "INFO: Opening input block: $INPUT_BLOCK"

open_block $INPUT_BLOCK
current_block

redirect -file ${REPORT_DIR}/41_opened_route_block_summary.rpt {
    puts "Input block  : $INPUT_BLOCK"
    puts "Output block : $OUTPUT_BLOCK"
    report_design -summary
    report_utilization
}

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

redirect -file ${REPORT_DIR}/42_route_mcmm_scenarios.rpt {
    report_scenarios
}

redirect -file ${REPORT_DIR}/43_pre_route_check_design.rpt {
    check_design -checks pre_route_stage
}

redirect -file ${REPORT_DIR}/44_pre_route_check_legality.rpt {
    check_legality
    report_utilization
}

redirect -file ${REPORT_DIR}/45_pre_route_pg_connectivity.rpt {
    check_pg_connectivity
}

redirect -file ${REPORT_DIR}/46_pre_route_pg_drc_ignore_std_cells.rpt {
    check_pg_drc -ignore_std_cells
}

redirect -file ${REPORT_DIR}/47_pre_route_check_routes.rpt {
    check_routes
}

redirect -file ${REPORT_DIR}/48_pre_route_qor.rpt {
    report_qor -summary
    report_utilization
}

redirect -file ${REPORT_DIR}/49_pre_route_timing.rpt {
    if {[sizeof_collection $slow_scen] > 0} {
        current_scenario func.slow_max
        puts "===== Pre-route setup timing: func.slow_max ====="
        report_timing \
            -delay_type max \
            -path_type full \
            -max_paths 30
    }

    if {[sizeof_collection $fast_scen] > 0} {
        current_scenario func.fast_min
        puts "===== Pre-route hold timing: func.fast_min ====="
        report_timing \
            -delay_type min \
            -path_type full \
            -max_paths 30
    }
}

redirect -file ${REPORT_DIR}/50_pre_route_drv.rpt {
    if {[sizeof_collection $slow_scen] > 0} {
        current_scenario func.slow_max
        puts "===== Pre-route DRV: func.slow_max ====="
        catch {
            report_constraints \
                -max_capacitance \
                -max_transition \
                -all_violators
        } drv_slow_msg
        puts $drv_slow_msg
    }

    if {[sizeof_collection $fast_scen] > 0} {
        current_scenario func.fast_min
        puts "===== Pre-route DRV: func.fast_min ====="
        catch {
            report_constraints \
                -max_capacitance \
                -max_transition \
                -all_violators
        } drv_fast_msg
        puts $drv_fast_msg
    }
}

safe_set_app_option route.common.verbose_level 1

safe_set_app_option route.global.timing_driven true
safe_set_app_option route.track.timing_driven true
safe_set_app_option route.detail.timing_driven true

safe_set_app_option route.global.crosstalk_driven false
safe_set_app_option route.track.crosstalk_driven true

safe_set_app_option time.si_enable_analysis true

safe_set_app_option time.enable_ccs_rcv_cap true
safe_set_app_option time.delay_calc_waveform_analysis_mode full_design
safe_set_app_option time.enable_si_timing_windows true

safe_set_app_option route.common.post_detail_route_redundant_via_insertion off
safe_set_app_option route.common.concurrent_redundant_via_mode reserve_space
safe_set_app_option route.common.eco_route_concurrent_redundant_via_mode reserve_space

safe_set_app_option route.detail.optimize_wire_via_effort_level high

safe_set_app_option route.detail.force_max_number_iterations false

if {$USE_ANTENNA_RULES} {
    if {[file exists $ANTENNA_RULE_FILE]} {
        puts "INFO: Sourcing antenna rule file: $ANTENNA_RULE_FILE"
        source -echo $ANTENNA_RULE_FILE
    } else {
        puts "WARNING: Antenna rule file not found: $ANTENNA_RULE_FILE"
        puts "WARNING: Continuing without explicit antenna rule source."
    }
}

redirect -file ${REPORT_DIR}/51_route_setup_options.rpt {
    puts "===== route.common options ====="
    catch {
        report_app_options route.common.*
    } route_common_msg
    puts $route_common_msg

    puts "===== route.global options ====="
    catch {
        report_app_options route.global.*
    } route_global_msg
    puts $route_global_msg

    puts "===== route.track options ====="
    catch {
        report_app_options route.track.*
    } route_track_msg
    puts $route_track_msg

    puts "===== route.detail options ====="
    catch {
        report_app_options route.detail.*
    } route_detail_msg
    puts $route_detail_msg

    puts "===== SI/timing options ====="
    catch {
        report_app_options time.si_enable_analysis
    } si_msg
    puts $si_msg

    catch {
        report_app_options time.enable_ccs_rcv_cap
    } ccs_msg
    puts $ccs_msg

    catch {
        report_app_options time.delay_calc_waveform_analysis_mode
    } waveform_msg
    puts $waveform_msg
}

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

    redirect -file ${REPORT_DIR}/52_dom_security_pre_route.rpt {
        puts "===== DOM/SCA pre-route structure report ====="
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

route_auto \
    -max_detail_route_iterations 60

save_block -as ${ntl_ver}_after_route_auto
save_lib

redirect -file ${REPORT_DIR}/53_after_route_auto_check_routes.rpt {
    check_routes
}

redirect -file ${REPORT_DIR}/54_after_route_auto_qor.rpt {
    report_qor -summary
    report_utilization
}

redirect -file ${REPORT_DIR}/55_after_route_auto_timing.rpt {
    if {[sizeof_collection $slow_scen] > 0} {
        current_scenario func.slow_max
        puts "===== After route_auto setup timing: func.slow_max ====="
        report_timing \
            -delay_type max \
            -path_type full \
            -max_paths 30
    }

    if {[sizeof_collection $fast_scen] > 0} {
        current_scenario func.fast_min
        puts "===== After route_auto hold timing: func.fast_min ====="
        report_timing \
            -delay_type min \
            -path_type full \
            -max_paths 30
    }
}

route_detail \
    -incremental true \
    -max_number_iterations 50

save_block -as ${ntl_ver}_after_route_detail_incr
save_lib

redirect -file ${REPORT_DIR}/56_after_route_detail_check_routes.rpt {
    check_routes
}

compute_clock_latency

if {$USE_POST_ROUTE_CCD} {
    safe_set_app_option route_opt.flow.enable_ccd true
    safe_set_app_option route_opt.flow.enable_clock_power_recovery none
} else {
    safe_set_app_option route_opt.flow.enable_ccd false
}

if {$USE_POST_ROUTE_POWER_OPT} {
    safe_set_app_option route_opt.flow.enable_power true
} else {
    safe_set_app_option route_opt.flow.enable_power false
}

redirect -file ${REPORT_DIR}/57_route_opt_setup_options.rpt {
    puts "===== route_opt options ====="
    catch {
        report_app_options route_opt.*
    } route_opt_msg
    puts $route_opt_msg

    puts "===== timing/SI options ====="
    catch {
        report_app_options time.*
    } time_msg
    puts $time_msg
}

route_opt

save_block -as ${ntl_ver}_after_route_opt_1
save_lib

redirect -file ${REPORT_DIR}/58_after_route_opt_1_qor.rpt {
    report_qor -summary
    report_utilization
}

redirect -file ${REPORT_DIR}/59_after_route_opt_1_check_routes.rpt {
    check_routes
}

safe_set_app_option time.pba_optimization_mode path
safe_set_app_option route.detail.eco_route_use_soft_spacing_for_timing_optimization false

route_opt

save_block -as ${ntl_ver}_after_route_opt_2
save_lib

redirect -file ${REPORT_DIR}/60_after_route_opt_2_qor.rpt {
    report_qor -summary
    catch {
        report_qor -summary -pba_mode path
    } pba_qor_msg
    puts $pba_qor_msg
    report_utilization
}

redirect -file ${REPORT_DIR}/61_after_route_opt_2_check_routes.rpt {
    check_routes
}

route_detail \
    -incremental true \
    -max_number_iterations 50

redirect -file ${REPORT_DIR}/62_after_final_detail_check_routes.rpt {
    check_routes
}

catch {
    add_redundant_vias
} rvia_msg

puts "INFO/WARNING from add_redundant_vias:"
puts $rvia_msg

redirect -file ${REPORT_DIR}/63_after_redundant_vias_check_routes.rpt {
    check_routes
}

save_block -as ${ntl_ver}_after_final_detail_route
save_lib

if {$INSERT_FILLERS_AFTER_ROUTE} {

    remove_all_fillers

    legalize_placement

    catch {
        create_stdcell_fillers \
            -lib_cells $FILLER_CELLS
    } filler_msg

    puts "INFO/WARNING from final create_stdcell_fillers:"
    puts $filler_msg

    legalize_placement
}

connect_pg_net -automatic

catch {
    compile_pg -strategies {S_std_rails}
} pg_rail_msg

puts "INFO/WARNING from final compile_pg S_std_rails:"
puts $pg_rail_msg

connect_pg_net -automatic

redirect -file ${REPORT_DIR}/64_final_route_check_legality.rpt {
    check_legality
    report_utilization
}

redirect -file ${REPORT_DIR}/65_final_route_pg_connectivity.rpt {
    check_pg_connectivity
}

redirect -file ${REPORT_DIR}/66_final_route_pg_drc_ignore_std_cells.rpt {
    check_pg_drc -ignore_std_cells
}

redirect -file ${REPORT_DIR}/67_final_check_routes.rpt {
    check_routes
}

redirect -file ${REPORT_DIR}/68_final_check_lvs.rpt {
    check_lvs \
        -checks all \
        -open_reporting detailed \
        -check_child_cells true
}

redirect -file ${REPORT_DIR}/69_final_route_qor.rpt {
    report_qor -summary
    catch {
        report_qor -summary -pba_mode path
    } final_pba_qor_msg
    puts $final_pba_qor_msg
    report_utilization
}

redirect -file ${REPORT_DIR}/70_final_route_timing.rpt {
    if {[sizeof_collection $slow_scen] > 0} {
        current_scenario func.slow_max
        puts "===== Final route setup timing: func.slow_max ====="
        report_timing \
            -delay_type max \
            -path_type full \
            -max_paths 50

        puts "===== Final route setup constraints: func.slow_max ====="
        catch {
            report_constraints \
                -max_delay \
                -all_violators
        } setup_final_msg
        puts $setup_final_msg
    }

    if {[sizeof_collection $fast_scen] > 0} {
        current_scenario func.fast_min
        puts "===== Final route hold timing: func.fast_min ====="
        report_timing \
            -delay_type min \
            -path_type full \
            -max_paths 50

        puts "===== Final route hold constraints: func.fast_min ====="
        catch {
            report_constraints \
                -min_delay \
                -all_violators
        } hold_final_msg
        puts $hold_final_msg
    }
}

redirect -file ${REPORT_DIR}/71_final_route_drv.rpt {
    if {[sizeof_collection $slow_scen] > 0} {
        current_scenario func.slow_max
        puts "===== Final route DRV: func.slow_max ====="
        catch {
            report_constraints \
                -max_capacitance \
                -max_transition \
                -all_violators
        } drv_slow_final_msg
        puts $drv_slow_final_msg
    }

    if {[sizeof_collection $fast_scen] > 0} {
        current_scenario func.fast_min
        puts "===== Final route DRV: func.fast_min ====="
        catch {
            report_constraints \
                -max_capacitance \
                -max_transition \
                -all_violators
        } drv_fast_final_msg
        puts $drv_fast_final_msg
    }
}

redirect -file ${REPORT_DIR}/72a_share_balance_physical.rpt {
    puts "===== Share 0 sensitive nets ====="

    foreach pat {
        *subbytes_out_0*
        *mixcolumns_out_0*
        *round_data_out_0*
        *expanded_key_word_0*
        *masked_key_in_0*
        *state_reg_A_0*
        *state_reg_B_0*
        *round_key_reg_0*
        *sbox_buffer_0*
    } {
        set ns [get_nets -hierarchical -quiet $pat]
        if {[sizeof_collection $ns] > 0} {
            puts ""
            puts "Pattern: $pat"
            catch {report_net -physical_context $ns} msg
            puts $msg
        }
    }

    puts ""
    puts "===== Share 1 sensitive nets ====="

    foreach pat {
        *subbytes_out_1*
        *mixcolumns_out_1*
        *round_data_out_1*
        *expanded_key_word_1*
        *masked_key_in_1*
        *state_reg_A_1*
        *state_reg_B_1*
        *round_key_reg_1*
        *sbox_buffer_1*
    } {
        set ns [get_nets -hierarchical -quiet $pat]
        if {[sizeof_collection $ns] > 0} {
            puts ""
            puts "Pattern: $pat"
            catch {report_net -physical_context $ns} msg
            puts $msg
        }
    }
}

redirect -file ${REPORT_DIR}/72_final_route_noise.rpt {
    catch {
        report_noise
    } noise_msg
    puts $noise_msg
}

if {$USE_DOM_SECURITY_RULES} {
    redirect -file ${REPORT_DIR}/73_dom_security_final_route.rpt {
        puts "===== DOM/SCA final route structure report ====="
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

redirect -file ${REPORT_DIR}/74_route_stage_summary.rpt {
    puts "===== Route Stage Summary ====="
    puts "Input block        : $INPUT_BLOCK"
    puts "Output block       : $OUTPUT_BLOCK"
    puts "Post-route CCD     : $USE_POST_ROUTE_CCD"
    puts "Power optimization : $USE_POST_ROUTE_POWER_OPT"
    puts "Final fillers      : $INSERT_FILLERS_AFTER_ROUTE"
    puts ""
    puts "Main reports:"
    puts "  43_pre_route_check_design.rpt"
    puts "  44_pre_route_check_legality.rpt"
    puts "  47_pre_route_check_routes.rpt"
    puts "  53_after_route_auto_check_routes.rpt"
    puts "  56_after_route_detail_check_routes.rpt"
    puts "  61_after_route_opt_2_check_routes.rpt"
    puts "  63_after_redundant_vias_check_routes.rpt"
    puts "  64_final_route_check_legality.rpt"
    puts "  65_final_route_pg_connectivity.rpt"
    puts "  66_final_route_pg_drc_ignore_std_cells.rpt"
    puts "  67_final_check_routes.rpt"
    puts "  68_final_check_lvs.rpt"
    puts "  69_final_route_qor.rpt"
    puts "  70_final_route_timing.rpt"
    puts "  71_final_route_drv.rpt"
    puts "  73_dom_security_final_route.rpt"
}

save_block -as $OUTPUT_BLOCK
save_lib

# exit
