# ICC2 post-route debug and repair script for the AES PNR flow.
# Generates post-route DRC/timing/debug reports, optionally repairs power-rail spacing issues, performs focused ECO cleanup, and saves the debugged routed block.

source ./scripts/icc2_lib_setup.tcl

set mode    $env(MODE)
set version $env(VER)
set ntl_ver $env(DESIGN_VER)

if {[info exists env(INPUT_BLOCK)]} {
    set INPUT_BLOCK $env(INPUT_BLOCK)
} else {
    set INPUT_BLOCK ${ntl_ver}_after_route
}

set OUTPUT_BLOCK ${ntl_ver}_after_route_clean

set DEBUG_TAG post_route_drc_debug_fix
set DO_SAVE_DEBUG_BLOCK 1
set DEBUG_BLOCK ${ntl_ver}_after_route_drc_debug_readonly

if {[info exists env(DO_M1_PG_DRC_FIX)]} {
    set DO_M1_PG_DRC_FIX $env(DO_M1_PG_DRC_FIX)
} else {
    set DO_M1_PG_DRC_FIX 1
}

set DO_REDUNDANT_VIAS_AFTER_FIX 1

if {[info exists env(DO_HOLD_ECO_AFTER_FIX)]} {
    set DO_HOLD_ECO_AFTER_FIX $env(DO_HOLD_ECO_AFTER_FIX)
} else {
    set DO_HOLD_ECO_AFTER_FIX 1
}

set HOLD_ECO_OUTPUT_BLOCK $OUTPUT_BLOCK

if {[info exists env(HOLD_ECO_BASE_HOLD_UNCERTAINTY)]} {
    set HOLD_ECO_BASE_HOLD_UNCERTAINTY $env(HOLD_ECO_BASE_HOLD_UNCERTAINTY)
} else {
    set HOLD_ECO_BASE_HOLD_UNCERTAINTY 0.10
}

if {[info exists env(HOLD_ECO_GUARDBAND)]} {
    set HOLD_ECO_GUARDBAND $env(HOLD_ECO_GUARDBAND)
} else {
    set HOLD_ECO_GUARDBAND 0.02
}

if {[info exists env(HOLD_ECO_PASSES)]} {
    set HOLD_ECO_PASSES $env(HOLD_ECO_PASSES)
} else {
    set HOLD_ECO_PASSES 2
}

set SETUP_SCENARIO func.slow_max
set HOLD_SCENARIO  func.fast_min

set FOCUS_LAYER M1
set PG_NETS {VDD VSS}

set FILLER_CELLS {saed32hvt/SHFILL*}
set STD_RAIL_STRATEGY S_std_rails

set OUTPUT_DIR ./results/${ntl_ver}
set REPORT_DIR ${OUTPUT_DIR}/reports
file mkdir $OUTPUT_DIR
file mkdir $REPORT_DIR

proc safe_run {label cmd} {
    puts "INFO: $label"
    if {[catch {uplevel 1 $cmd} msg]} {
        puts "WARNING: $label failed"
        puts "WARNING: $msg"
        return 0
    } else {
        puts "INFO: $label completed"
        return 1
    }
}

proc must_run {label cmd} {
    puts "INFO: $label"
    if {[catch {uplevel 1 $cmd} msg]} {
        puts "ERROR: $label failed"
        puts "ERROR: $msg"
        error "$label failed"
    } else {
        puts "INFO: $label completed"
        return 1
    }
}

proc safe_redirect {file cmd} {
    puts "INFO: Writing report $file"
    if {[catch {uplevel 1 [list redirect -file $file $cmd]} msg]} {
        puts "WARNING: Could not write report $file"
        puts "WARNING: $msg"
        return 0
    }
    return 1
}

proc safe_set_app_option {opt val} {
    if {[catch {set_app_options -name $opt -value $val} msg]} {
        puts "WARNING: Could not set app option $opt to $val"
        puts "WARNING: $msg"
        return 0
    } else {
        puts "INFO: Set app option $opt = $val"
        return 1
    }
}

proc coll_size {c} {
    if {[catch {sizeof_collection $c} n]} {
        return 0
    }
    return $n
}

proc get_filler_like_cells {} {
    set filler_by_ref_hier  [get_cells -hierarchical -quiet -filter "ref_name =~ SHFILL*"]
    set filler_by_ref_flat  [get_flat_cells -quiet -filter "ref_name =~ SHFILL*"]
    set filler_by_name_hier [get_cells -hierarchical -quiet xofiller*]
    set filler_by_name_flat [get_flat_cells -quiet xofiller*]

    set all_fillers [add_to_collection $filler_by_ref_hier $filler_by_ref_flat]
    set all_fillers [add_to_collection $all_fillers $filler_by_name_hier]
    set all_fillers [add_to_collection $all_fillers $filler_by_name_flat]
    return $all_fillers
}

proc remove_all_fillers {} {
    puts "INFO: Removing standard-cell fillers."

    catch {remove_stdcell_fillers} remove_fill_msg
    puts "INFO/WARNING from remove_stdcell_fillers:"
    puts $remove_fill_msg

    set all_fillers [get_filler_like_cells]
    puts "INFO: Filler-like cells found after remove_stdcell_fillers: [coll_size $all_fillers]"

    if {[coll_size $all_fillers] > 0} {
        remove_cells $all_fillers
        puts "INFO: Removed remaining filler-like cells."
    }

    set filler_check [get_filler_like_cells]
    puts "INFO: Filler-like cells after cleanup: [coll_size $filler_check]"
}

proc setup_expected_scenarios {setup_scen hold_scen} {
    set slow_scen [get_scenarios -quiet $setup_scen]
    set fast_scen [get_scenarios -quiet $hold_scen]

    if {[sizeof_collection $slow_scen] > 0} {
        set_scenario_status $setup_scen \
            -active true \
            -setup true \
            -hold false \
            -leakage_power true \
            -dynamic_power true
    } else {
        puts "WARNING: Scenario $setup_scen not found."
    }

    if {[sizeof_collection $fast_scen] > 0} {
        set_scenario_status $hold_scen \
            -active true \
            -setup false \
            -hold true \
            -leakage_power false \
            -dynamic_power false
    } else {
        puts "WARNING: Scenario $hold_scen not found."
    }
}

proc auto_detect_drc_nets_from_check_routes {rpt_file pg_net_list} {

    set all_net_names {}
    set signal_net_names {}

    if {![file exists $rpt_file]} {
        puts "WARNING: check_routes report not found for auto-detect: $rpt_file"
        return [list $all_net_names $signal_net_names]
    }

    set fp [open $rpt_file r]
    while {[gets $fp line] >= 0} {
        if {![regexp {\(([^,()]+),([^,()]+)\)} $line -> net_a net_b]} {
            continue
        }

        foreach n [list [string trim $net_a] [string trim $net_b]] {
            if {$n eq ""} {
                continue
            }

            if {[lsearch -exact $all_net_names $n] < 0} {
                lappend all_net_names $n
            }

            if {[lsearch -exact $pg_net_list $n] < 0} {
                if {[lsearch -exact $signal_net_names $n] < 0} {
                    lappend signal_net_names $n
                }
            }
        }
    }
    close $fp

    return [list $all_net_names $signal_net_names]
}

proc get_nets_from_name_list {net_name_list} {
    set net_collection ""

    foreach n $net_name_list {
        set tmp [get_nets -hierarchical -quiet $n]
        if {[coll_size $tmp] > 0} {
            set net_collection [add_to_collection $net_collection $tmp]
        } else {
            puts "INFO: Auto-detected DRC net not found in design database: $n"
        }
    }

    return $net_collection
}

proc write_full_physical_checks {report_file} {
    safe_redirect $report_file {
        puts "===== check_legality ====="
        catch {check_legality} legality_msg
        puts $legality_msg

        puts ""
        puts "===== check_routes ====="
        catch {check_routes} routes_msg
        puts $routes_msg

        puts ""
        puts "===== check_lvs ====="
        catch {
            check_lvs \
                -checks all \
                -open_reporting detailed \
                -check_child_cells true
        } lvs_msg
        puts $lvs_msg

        puts ""
        puts "===== check_pg_connectivity ====="
        catch {check_pg_connectivity} pg_conn_msg
        puts $pg_conn_msg

        puts ""
        puts "===== check_pg_drc full ====="
        catch {check_pg_drc} pgfull_msg
        puts $pgfull_msg

        puts ""
        puts "===== check_pg_drc -ignore_std_cells ====="
        catch {check_pg_drc -ignore_std_cells} pgignore_msg
        puts $pgignore_msg
    }
}

puts "INFO: Opening routed block for DRC debug/fix: $INPUT_BLOCK"
must_run "Opening input block $INPUT_BLOCK" {
    open_block $INPUT_BLOCK
    current_block
}

setup_expected_scenarios $SETUP_SCENARIO $HOLD_SCENARIO

safe_redirect ${REPORT_DIR}/74_post_route_drc_debug_context.rpt {
    puts "===== Debug/fix context ====="
    puts "Input block           : $INPUT_BLOCK"
    puts "Debug block           : $DEBUG_BLOCK"
    puts "Final output block    : $OUTPUT_BLOCK"
    puts "Design version        : $ntl_ver"
    puts "Mode                  : $mode"
    puts "Version               : $version"
    puts "DO_M1_PG_DRC_FIX      : $DO_M1_PG_DRC_FIX"
    puts "DO_HOLD_ECO_AFTER_FIX : $DO_HOLD_ECO_AFTER_FIX"
    puts "Hold ECO output block : $HOLD_ECO_OUTPUT_BLOCK"
    puts "Focus layer           : $FOCUS_LAYER"
    puts "Focus PG nets         : $PG_NETS"
    puts "Filler cells          : $FILLER_CELLS"
    puts "Std-cell rail strategy: $STD_RAIL_STRATEGY"
    puts ""
    puts "===== current block ====="
    current_block
    puts ""
    puts "===== design summary ====="
    report_design -summary
    puts ""
    puts "===== utilization ====="
    report_utilization
    puts ""
    puts "===== scenarios ====="
    report_scenarios
    puts ""
    puts "===== ignored layers ====="
    catch {report_ignored_layers} ignored_msg
    puts $ignored_msg
}

safe_redirect ${REPORT_DIR}/75_post_route_check_legality.rpt {
    puts "===== check_legality ====="
    check_legality
    puts ""
    puts "===== utilization ====="
    report_utilization
}

safe_redirect ${REPORT_DIR}/76_post_route_check_routes_full.rpt {
    puts "===== check_routes full ====="
    check_routes
}

safe_redirect ${REPORT_DIR}/77_post_route_check_lvs.rpt {
    puts "===== check_lvs all detailed ====="
    catch {
        check_lvs \
            -checks all \
            -open_reporting detailed \
            -check_child_cells true
    } lvs_msg
    puts $lvs_msg
}

safe_redirect ${REPORT_DIR}/78_post_route_pg_checks.rpt {
    puts "===== check_pg_connectivity ====="
    catch {check_pg_connectivity} pg_conn_msg
    puts $pg_conn_msg

    puts ""
    puts "===== check_pg_drc ====="
    catch {check_pg_drc} pg_drc_msg
    puts $pg_drc_msg

    puts ""
    puts "===== check_pg_drc -ignore_std_cells ====="
    catch {check_pg_drc -ignore_std_cells} pg_drc_ign_msg
    puts $pg_drc_ign_msg
}

safe_redirect ${REPORT_DIR}/79_post_route_route_app_options.rpt {
    puts "===== route.common ====="
    catch {report_app_options route.common.*} msg_common
    puts $msg_common

    puts "===== route.global ====="
    catch {report_app_options route.global.*} msg_global
    puts $msg_global

    puts "===== route.track ====="
    catch {report_app_options route.track.*} msg_track
    puts $msg_track

    puts "===== route.detail ====="
    catch {report_app_options route.detail.*} msg_detail
    puts $msg_detail

    puts "===== route_opt ====="
    catch {report_app_options route_opt.*} msg_ropt
    puts $msg_ropt
}

set pg_nets [get_nets -quiet $PG_NETS]

safe_redirect ${REPORT_DIR}/80_post_route_pg_net_detail.rpt {
    puts "===== VDD/VSS net report ====="
    if {[sizeof_collection $pg_nets] > 0} {
        report_net $pg_nets
    } else {
        puts "No VDD/VSS nets found."
    }

    puts ""
    puts "===== VDD/VSS routing shapes if supported ====="
    foreach n $PG_NETS {
        set nn [get_nets -quiet $n]
        puts "--- Net $n ---"
        if {[sizeof_collection $nn] > 0} {
            catch {report_net -physical $nn} phys_msg
            puts $phys_msg
        } else {
            puts "Net $n not found."
        }
    }
}

set auto_drc_parse_result [auto_detect_drc_nets_from_check_routes     ${REPORT_DIR}/76_post_route_check_routes_full.rpt     $PG_NETS]

set auto_drc_all_net_names    [lindex $auto_drc_parse_result 0]
set auto_drc_signal_net_names [lindex $auto_drc_parse_result 1]
set suspect_nets [get_nets_from_name_list $auto_drc_signal_net_names]

safe_redirect ${REPORT_DIR}/81_post_route_suspect_signal_net_detail.rpt {
    puts "===== Auto-detected nets from check_routes DRC report ====="
    puts "Parsed report          : ${REPORT_DIR}/76_post_route_check_routes_full.rpt"
    puts "PG nets excluded       : $PG_NETS"
    puts "All DRC net names      : $auto_drc_all_net_names"
    puts "Signal suspect names   : $auto_drc_signal_net_names"
    puts "Matched signal net cnt : [coll_size $suspect_nets]"

    if {[coll_size $suspect_nets] > 0} {
        puts ""
        puts "===== Logical net report ====="
        report_net $suspect_nets

        puts ""
        puts "===== Physical net report if supported ====="
        catch {report_net -physical $suspect_nets} phys_sig_msg
        puts $phys_sig_msg
    } else {
        puts "No non-PG suspect nets were detected from check_routes, or detected names did not match current design nets."
    }
}

set all_fillers [get_filler_like_cells]

safe_redirect ${REPORT_DIR}/82_post_route_filler_and_cell_rail_debug.rpt {
    set filler_by_ref_hier  [get_cells -hierarchical -quiet -filter "ref_name =~ SHFILL*"]
    set filler_by_ref_flat  [get_flat_cells -quiet -filter "ref_name =~ SHFILL*"]
    set filler_by_name_hier [get_cells -hierarchical -quiet xofiller*]
    set filler_by_name_flat [get_flat_cells -quiet xofiller*]
    set all_fillers_local [get_filler_like_cells]

    puts "===== Filler diagnosis ====="
    puts "SHFILL hierarchical cells : [sizeof_collection $filler_by_ref_hier]"
    puts "SHFILL flat cells         : [sizeof_collection $filler_by_ref_flat]"
    puts "xofiller hierarchical     : [sizeof_collection $filler_by_name_hier]"
    puts "xofiller flat             : [sizeof_collection $filler_by_name_flat]"
    puts "Total filler-like cells   : [coll_size $all_fillers_local]"

    if {[coll_size $all_fillers_local] > 0} {
        puts ""
        puts "===== Filler-like cells ====="
        report_cell $all_fillers_local
    }

    puts ""
    puts "===== Standard-cell rail strategy objects if supported ====="
    catch {report_pg_strategy S_std_rails} rpgs_msg
    puts $rpgs_msg

    puts ""
    puts "===== PG patterns if supported ====="
    catch {report_pg_patterns} rpgp_msg
    puts $rpgp_msg
}

safe_redirect ${REPORT_DIR}/83_post_route_drc_browser_marker_attempt.rpt {
    puts "===== DRC marker / error browser commands ====="
    puts "These commands are optional and may depend on ICC2 version/license."

    catch {open_drc_error_data} open_drc_msg
    puts "open_drc_error_data: $open_drc_msg"

    catch {report_drc_error_data} rpt_drc_msg
    puts "report_drc_error_data: $rpt_drc_msg"

    catch {gui_start} gui_msg
    puts "gui_start: $gui_msg"
}

safe_redirect ${REPORT_DIR}/84_post_route_baseline_full_physical_checks.rpt {
    puts "===== Baseline summary before optional fix ====="
    puts "Input block: $INPUT_BLOCK"
    puts ""
    puts "===== check_legality ====="
    catch {check_legality} msg1
    puts $msg1
    puts ""
    puts "===== check_routes ====="
    catch {check_routes} msg2
    puts $msg2
    puts ""
    puts "===== check_pg_drc full ====="
    catch {check_pg_drc} msg3
    puts $msg3
    puts ""
    puts "===== check_pg_drc -ignore_std_cells ====="
    catch {check_pg_drc -ignore_std_cells} msg4
    puts $msg4
}

if {$DO_SAVE_DEBUG_BLOCK} {
    safe_run "Saving read-only debug checkpoint $DEBUG_BLOCK" {
        save_block -as $DEBUG_BLOCK
        save_lib
    }
}

if {$DO_M1_PG_DRC_FIX} {
    puts "============================================================"
    puts "INFO: DO_M1_PG_DRC_FIX=1"
    puts "INFO: Starting M1 PG/std-cell rail spacing repair."
    puts "============================================================"

    safe_redirect ${REPORT_DIR}/85_post_route_before_fix_check_routes.rpt {
        check_routes
    }

    safe_redirect ${REPORT_DIR}/86_post_route_before_fix_pg_drc.rpt {
        puts "===== check_pg_drc full ====="
        catch {check_pg_drc} pgfull_msg
        puts $pgfull_msg
        puts ""
        puts "===== check_pg_drc -ignore_std_cells ====="
        catch {check_pg_drc -ignore_std_cells} pgignore_msg
        puts $pgignore_msg
    }

    remove_all_fillers

    safe_run "Legalize placement after filler removal" {
        legalize_placement
    }

    safe_run "Create standard-cell fillers" {
        create_stdcell_fillers -lib_cells $FILLER_CELLS
    }

    safe_run "Legalize placement after filler insertion" {
        legalize_placement
    }

    safe_run "Connect PG nets after filler insertion" {
        connect_pg_net -automatic
    }

    safe_run "Compile std-cell PG rails using $STD_RAIL_STRATEGY" {
        compile_pg -strategies [list $STD_RAIL_STRATEGY]
    }

    safe_run "Reconnect PG nets after std-cell rail compile" {
        connect_pg_net -automatic
    }

    safe_redirect ${REPORT_DIR}/87_post_route_after_filler_rail_before_reroute.rpt {
        puts "===== check_legality ====="
        catch {check_legality} legality_msg
        puts $legality_msg
        puts ""
        puts "===== check_pg_connectivity ====="
        catch {check_pg_connectivity} pg_conn_msg
        puts $pg_conn_msg
        puts ""
        puts "===== check_pg_drc full ====="
        catch {check_pg_drc} pgfull_msg
        puts $pgfull_msg
        puts ""
        puts "===== check_routes before reroute ====="
        catch {check_routes} routes_msg
        puts $routes_msg
    }

    safe_set_app_option route.common.eco_route_fix_existing_drc true
    safe_set_app_option route.common.eco_fix_drc_in_changed_area_only false
    safe_set_app_option route.detail.drc_convergence_effort_level high
    safe_set_app_option route.detail.optimize_wire_via_effort_level high
    safe_set_app_option route.detail.eco_route_use_soft_spacing_for_timing_optimization false
    safe_set_app_option route.common.post_detail_route_redundant_via_insertion off

    must_run "Run rail-aware incremental detail route" {
        route_detail \
            -incremental true \
            -max_number_iterations 100
    }

    safe_redirect ${REPORT_DIR}/88_post_route_after_reroute_check_routes.rpt {
        check_routes
    }

    safe_redirect ${REPORT_DIR}/89_post_route_after_reroute_pg_drc.rpt {
        puts "===== check_pg_drc full ====="
        catch {check_pg_drc} pgfull_msg
        puts $pgfull_msg
        puts ""
        puts "===== check_pg_drc -ignore_std_cells ====="
        catch {check_pg_drc -ignore_std_cells} pgignore_msg
        puts $pgignore_msg
    }

    if {$DO_REDUNDANT_VIAS_AFTER_FIX} {
        safe_run "Add redundant vias after DRC cleanup" {
            add_redundant_vias
        }

        safe_redirect ${REPORT_DIR}/90_post_route_after_redundant_vias_check_routes.rpt {
            check_routes
        }
    }

    write_full_physical_checks ${REPORT_DIR}/91_post_route_final_physical_checks.rpt

    safe_redirect ${REPORT_DIR}/92_post_route_final_qor_timing_drv.rpt {
        report_qor -summary
        report_utilization
        foreach_in_collection s [get_scenarios -quiet *] {
            set scen [get_object_name $s]
            current_scenario $scen
            puts ""
            puts "============================================================"
            puts "Scenario: $scen"
            puts "============================================================"
            catch {report_timing -delay_type max -path_type full -max_paths 10} rtmax_msg
            puts $rtmax_msg
            catch {report_timing -delay_type min -path_type full -max_paths 10} rtmin_msg
            puts $rtmin_msg
            catch {report_constraints -max_capacitance -max_transition -all_violators} drv_msg
            puts $drv_msg
        }
    }

    if {$DO_HOLD_ECO_AFTER_FIX} {
        puts "============================================================"
        puts "INFO: DO_HOLD_ECO_AFTER_FIX=1"
        puts "INFO: Running conservative hold-only ECO cleanup."
        puts "============================================================"

        setup_expected_scenarios $SETUP_SCENARIO $HOLD_SCENARIO

        if {[sizeof_collection [get_scenarios -quiet $HOLD_SCENARIO]] > 0} {
            current_scenario $HOLD_SCENARIO
        }

        set HOLD_ECO_TARGET_HOLD_UNCERTAINTY [expr {$HOLD_ECO_BASE_HOLD_UNCERTAINTY + $HOLD_ECO_GUARDBAND}]

        safe_run "Temporarily apply hold ECO guardband" {
            current_scenario $HOLD_SCENARIO
            set_clock_uncertainty -hold $HOLD_ECO_TARGET_HOLD_UNCERTAINTY [get_clocks clk]
        }

        safe_run "Apply set_fix_hold on clk" {
            current_scenario $HOLD_SCENARIO
            set_fix_hold [get_clocks clk]
        }

        safe_set_app_option route_opt.flow.enable_ccd false
        safe_set_app_option route_opt.flow.enable_power false
        safe_set_app_option opt.common.hold_effort high
        safe_set_app_option time.pba_optimization_mode path
        safe_set_app_option route.common.eco_route_fix_existing_drc true
        safe_set_app_option route.common.eco_fix_drc_in_changed_area_only false
        safe_set_app_option route.detail.eco_route_use_soft_spacing_for_timing_optimization false
        safe_set_app_option route.detail.drc_convergence_effort_level high
        safe_set_app_option route.detail.optimize_wire_via_effort_level high

        safe_redirect ${REPORT_DIR}/94_post_route_pre_hold_eco_timing.rpt {
            if {[sizeof_collection [get_scenarios -quiet $HOLD_SCENARIO]] > 0} {
                current_scenario $HOLD_SCENARIO
                puts "===== Pre-hold-ECO min timing: $HOLD_SCENARIO ====="
                catch {
                    report_timing \
                        -delay_type min \
                        -path_type full \
                        -pba_mode path \
                        -max_paths 20
                } pre_hold_rt_msg
                puts $pre_hold_rt_msg

                puts ""
                puts "===== Pre-hold-ECO min constraints: $HOLD_SCENARIO ====="
                catch {
                    report_constraints \
                        -min_delay \
                        -all_violators
                } pre_hold_con_msg
                puts $pre_hold_con_msg
            } else {
                puts "WARNING: Hold scenario $HOLD_SCENARIO not found."
            }
        }

        set hold_pass 1
        while {$hold_pass <= $HOLD_ECO_PASSES} {
            safe_run "Run route_opt hold ECO pass $hold_pass" {
                current_scenario $HOLD_SCENARIO
                route_opt
            }

            safe_run "Run incremental detail route after hold ECO pass $hold_pass" {
                route_detail \
                    -incremental true \
                    -max_number_iterations 60
            }

            safe_redirect ${REPORT_DIR}/94a_post_route_hold_eco_pass_${hold_pass}_timing.rpt {
                if {[sizeof_collection [get_scenarios -quiet $HOLD_SCENARIO]] > 0} {
                    current_scenario $HOLD_SCENARIO
                    puts "===== Hold-ECO pass $hold_pass min timing with temporary guardband: $HOLD_SCENARIO ====="
                    catch {
                        report_timing \
                            -delay_type min \
                            -path_type full \
                            -pba_mode path \
                            -max_paths 20
                    } pass_hold_rt_msg
                    puts $pass_hold_rt_msg

                    puts ""
                    puts "===== Hold-ECO pass $hold_pass min constraints with temporary guardband: $HOLD_SCENARIO ====="
                    catch {
                        report_constraints \
                            -min_delay \
                            -all_violators
                    } pass_hold_con_msg
                    puts $pass_hold_con_msg
                }
            }

            incr hold_pass
        }

        safe_run "Restore original hold uncertainty after ECO" {
            current_scenario $HOLD_SCENARIO
            set_clock_uncertainty -hold $HOLD_ECO_BASE_HOLD_UNCERTAINTY [get_clocks clk]
        }

        catch {update_timing} update_timing_msg
        puts "INFO/WARNING from update_timing after hold uncertainty restore:"
        puts $update_timing_msg

        safe_redirect ${REPORT_DIR}/95_post_route_post_hold_eco_timing.rpt {
            if {[sizeof_collection [get_scenarios -quiet $HOLD_SCENARIO]] > 0} {
                current_scenario $HOLD_SCENARIO
                puts "===== Post-hold-ECO min timing after restoring original hold uncertainty: $HOLD_SCENARIO ====="
                catch {
                    report_timing \
                        -delay_type min \
                        -path_type full \
                        -pba_mode path \
                        -max_paths 20
                } post_hold_rt_msg
                puts $post_hold_rt_msg

                puts ""
                puts "===== Post-hold-ECO min constraints after restoring original hold uncertainty: $HOLD_SCENARIO ====="
                catch {
                    report_constraints \
                        -min_delay \
                        -all_violators
                } post_hold_con_msg
                puts $post_hold_con_msg
            } else {
                puts "WARNING: Hold scenario $HOLD_SCENARIO not found."
            }
        }

        safe_redirect ${REPORT_DIR}/96_post_route_post_hold_eco_check_routes.rpt {
            check_routes
        }

        safe_redirect ${REPORT_DIR}/97_post_route_post_hold_eco_check_legality.rpt {
            check_legality
            report_utilization
        }

        safe_redirect ${REPORT_DIR}/98_post_route_post_hold_eco_physical_checks.rpt {
            puts "===== check_lvs ====="
            catch {
                check_lvs \
                    -checks all \
                    -open_reporting detailed \
                    -check_child_cells true
            } hold_lvs_msg
            puts $hold_lvs_msg

            puts ""
            puts "===== check_pg_connectivity ====="
            catch {check_pg_connectivity} hold_pg_conn_msg
            puts $hold_pg_conn_msg

            puts ""
            puts "===== check_pg_drc -ignore_std_cells ====="
            catch {check_pg_drc -ignore_std_cells} hold_pg_drc_msg
            puts $hold_pg_drc_msg
        }

        must_run "Saving final clean output block $HOLD_ECO_OUTPUT_BLOCK" {
            save_block -as $HOLD_ECO_OUTPUT_BLOCK
            save_lib
        }
    } else {
        puts "============================================================"
        puts "INFO: DO_HOLD_ECO_AFTER_FIX=0"
        puts "INFO: Skipping hold-only ECO cleanup."
        puts "============================================================"

        must_run "Saving final clean output block $OUTPUT_BLOCK" {
            save_block -as $OUTPUT_BLOCK
            save_lib
        }
    }
} else {
    puts "============================================================"
    puts "INFO: DO_M1_PG_DRC_FIX=0"
    puts "INFO: Debug reports generated only. No design repair was run."
    puts "INFO: To enable repair, set env DO_M1_PG_DRC_FIX=1 or edit this script."
    puts "============================================================"
}

safe_redirect ${REPORT_DIR}/93_post_route_drc_debug_fix_summary.rpt {
    puts "===== Post-route DRC debug/fix summary ====="
    puts "Input block           : $INPUT_BLOCK"
    puts "Debug block           : $DEBUG_BLOCK"
    puts "Repair enabled        : $DO_M1_PG_DRC_FIX"
    puts "Final output block    : $OUTPUT_BLOCK"
    puts "Hold ECO enabled      : $DO_HOLD_ECO_AFTER_FIX"
    puts "Hold ECO output block : $HOLD_ECO_OUTPUT_BLOCK"
    puts "Hold ECO base hold uncertainty : $HOLD_ECO_BASE_HOLD_UNCERTAINTY ns"
    puts "Hold ECO guardband            : $HOLD_ECO_GUARDBAND ns"
    puts "Hold ECO passes               : $HOLD_ECO_PASSES"
    puts "Reports               : $REPORT_DIR"
    puts ""
    puts "Read these debug reports first:"
    puts "  76_post_route_check_routes_full.rpt"
    puts "  78_post_route_pg_checks.rpt"
    puts "  80_post_route_pg_net_detail.rpt"
    puts "  81_post_route_suspect_signal_net_detail.rpt"
    puts "  82_post_route_filler_and_cell_rail_debug.rpt"
    puts "  84_post_route_baseline_full_physical_checks.rpt"
    puts ""
    puts "If repair was enabled, read these fix reports next:"
    puts "  87_post_route_after_filler_rail_before_reroute.rpt"
    puts "  88_post_route_after_reroute_check_routes.rpt"
    puts "  89_post_route_after_reroute_pg_drc.rpt"
    puts "  91_post_route_final_physical_checks.rpt"
    puts "  92_post_route_final_qor_timing_drv.rpt"
    puts ""
    puts "If hold ECO was enabled, read these hold reports:"
    puts "  94_post_route_pre_hold_eco_timing.rpt"
    puts "  95_post_route_post_hold_eco_timing.rpt"
    puts "  96_post_route_post_hold_eco_check_routes.rpt"
    puts "  97_post_route_post_hold_eco_check_legality.rpt"
    puts "  98_post_route_post_hold_eco_physical_checks.rpt"
    puts ""
    puts "Interpretation guide:"
    puts "  - Clean check_legality + M1-M1 Diff net spacing in check_routes means"
    puts "    routing/PG-shape spacing, not placement legalization."
    puts "  - If check_pg_drc full has errors but check_pg_drc -ignore_std_cells is clean,"
    puts "    the issue is tied to std-cell/filler rails."
    puts "  - The repair sequence rebuilds fillers/std-cell rails before final route_detail,"
    puts "    so detail route can move signal wires away from M1 PG rail shapes."
}

puts "============================================================"
puts "Post-route DRC debug/fix script completed."
puts "Reports: $REPORT_DIR"
puts "Repair enabled: $DO_M1_PG_DRC_FIX"
if {$DO_M1_PG_DRC_FIX} {
    if {$DO_HOLD_ECO_AFTER_FIX} {
        puts "Output block: $HOLD_ECO_OUTPUT_BLOCK"
    } else {
        puts "Output block: $OUTPUT_BLOCK"
    }
} else {
    puts "No repair was run. Set DO_M1_PG_DRC_FIX=1 to run repair."
}
puts "============================================================"

# exit
