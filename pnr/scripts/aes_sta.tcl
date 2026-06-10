
############################################################
# PrimeTime STA Script
# DOM-based Masked AES Accelerator
#
# Run:
#   pt_shell -f scripts/aes_sta.tcl | tee -i logs/aes_sta.log
############################################################

############################################################
# 0. User variables
############################################################

set DESIGN     $env(DESIGN)
set MODE       $env(MODE)
set VER        $env(VER)
set DESIGN_VER $env(DESIGN_VER)
set FIFO_DEPTH 8
set BURST_CNT_W 32

if {$DESIGN eq "aes_ahb_lite_dma"} {
    set TOP_MODULE ${DESIGN}_${VER}_MODE${MODE}_FIFO_DEPTH${FIFO_DEPTH}_BURST_CNT_W${BURST_CNT_W}
} else {
    set TOP_MODULE ${DESIGN}_${VER}_MODE${MODE}
}

set HANDOFF_DIR ./results/${DESIGN_VER}
set REPORT_DIR  ${HANDOFF_DIR}/reports_sta
set SESSION_DIR ${HANDOFF_DIR}/pt_session

file mkdir $REPORT_DIR
file mkdir $SESSION_DIR

set SETUP_SCENARIO func.slow_max
set HOLD_SCENARIO  func.fast_min

set scenarios [list $SETUP_SCENARIO $HOLD_SCENARIO]

############################################################
# Power reporting control
#
# Default:
#   Report power for both SS/setup and FF/hold scenarios.
#
# Optional activity input:
#   export POWER_ACTIVITY_FILE=/path/to/activity.saif
# or scenario-specific:
#   export POWER_ACTIVITY_FUNC_SLOW_MAX=/path/to/slow.saif
#   export POWER_ACTIVITY_FUNC_FAST_MIN=/path/to/fast.saif
#
# Supported activity readers are tried safely, so the STA flow
# still completes if activity annotation is not available.
############################################################

set RUN_POWER_REPORTS 1
set POWER_SCENARIOS [list $SETUP_SCENARIO $HOLD_SCENARIO]
set POWER_SIGNIFICANT_DIGITS 3

############################################################
# Timing report control
#
# Main detailed timing reports are NOT filtered by slack, so
# they are generated even when there are no violations.
# Separate *_violators.rpt files keep the violation-only view.
############################################################

set TIMING_MAX_PATHS 200
set TIMING_NWORST 10
set TIMING_SIGNIFICANT_DIGITS 4
# Use a very large slack threshold for top-path reports to override
# any PrimeTime/site default that may otherwise inject -slack_lesser_than 0.0.
set TIMING_TOP_PATH_SLACK_LIMIT 999999.0

############################################################
# 1. Helper procedures
############################################################

proc safe_run {label cmd} {
    puts "INFO: $label"
    if {[catch {uplevel 1 $cmd} msg]} {
        puts "WARNING: $label failed"
        puts "WARNING: $msg"
        return 0
    }
    puts "INFO: $label completed"
    return 1
}

proc must_run {label cmd} {
    puts "INFO: $label"
    if {[catch {uplevel 1 $cmd} msg]} {
        puts "ERROR: $label failed"
        puts "ERROR: $msg"
        error "$label failed"
    }
    puts "INFO: $label completed"
    return 1
}

proc rpt {file cmd} {
    puts "INFO: Writing $file"
    puts "INFO: BEGIN_RPT $file"

    if {[catch {uplevel 1 [list redirect -file $file $cmd]} msg]} {
        puts "WARNING: Could not write $file"
        puts "WARNING: $msg"
        puts "INFO: END_RPT_FAIL $file"
        return 0
    }

    puts "INFO: END_RPT_PASS $file"
    return 1
}

proc clean_scen {scen} {
    return [string map {. _ / _ : _} $scen]
}

proc scenario_in_list {scen scen_list} {
    if {[lsearch -exact $scen_list $scen] >= 0} {
        return 1
    }
    return 0
}

proc get_power_activity_file {scen} {
    set clean [string toupper [string map {. _ / _ : _} $scen]]
    set scen_env POWER_ACTIVITY_$clean

    if {[info exists ::env($scen_env)] && $::env($scen_env) ne ""} {
        return $::env($scen_env)
    }

    if {[info exists ::env(POWER_ACTIVITY_FILE)] && $::env(POWER_ACTIVITY_FILE) ne ""} {
        return $::env(POWER_ACTIVITY_FILE)
    }

    return ""
}

proc annotate_power_activity {activity_file top_module} {
    if {$activity_file eq ""} {
        puts "INFO: No POWER_ACTIVITY_FILE or scenario-specific POWER_ACTIVITY_* set."
        puts "INFO: Power reports will use tool/default switching activity, if available."
        return 1
    }

    if {![file exists $activity_file]} {
        puts "WARNING: Power activity file does not exist: $activity_file"
        return 0
    }

    set ext [string tolower [file extension $activity_file]]

    if {$ext eq ".saif"} {
        if {[llength [info commands read_saif]] > 0} {
            if {[catch {read_saif $activity_file -instance_name $top_module} msg]} {
                puts "WARNING: read_saif with -instance_name failed."
                puts "WARNING: $msg"
                if {[catch {read_saif $activity_file} msg2]} {
                    puts "WARNING: read_saif failed."
                    puts "WARNING: $msg2"
                    return 0
                }
            }
            puts "INFO: Annotated SAIF activity: $activity_file"
            return 1
        }

        puts "WARNING: read_saif command not available in this PrimeTime session."
        return 0
    }

    if {$ext eq ".vcd"} {
        if {[llength [info commands read_vcd]] > 0} {
            if {[catch {read_vcd $activity_file -strip_path $top_module} msg]} {
                puts "WARNING: read_vcd with -strip_path failed."
                puts "WARNING: $msg"
                if {[catch {read_vcd $activity_file} msg2]} {
                    puts "WARNING: read_vcd failed."
                    puts "WARNING: $msg2"
                    return 0
                }
            }
            puts "INFO: Annotated VCD activity: $activity_file"
            return 1
        }

        puts "WARNING: read_vcd command not available in this PrimeTime session."
        return 0
    }

    puts "WARNING: Unsupported power activity file extension: $ext"
    puts "WARNING: Expected .saif or .vcd"
    return 0
}

proc require_file {label file} {
    if {![file exists $file]} {
        puts "ERROR: Missing $label: $file"
        error "Missing $label"
    }
    puts "INFO: Found $label: $file"
}

############################################################
# 2. PrimeTime library setup
############################################################

source ./scripts/pt_lib_setup.tcl

############################################################
# 3. Locate ICC2 handoff files
############################################################

set NETLIST ${HANDOFF_DIR}/${DESIGN_VER}.v
require_file "Verilog netlist" $NETLIST

array unset SDC_FILE
array unset SPEF_FILE

foreach scen $scenarios {
    set clean [clean_scen $scen]

    ########################################################
    # SDC
    ########################################################

    set SDC_FILE($scen) ${HANDOFF_DIR}/${DESIGN_VER}_${clean}.sdc
    require_file "SDC for $scen" $SDC_FILE($scen)

    ########################################################
    # SPEF
    #
    # ICC2 generated:
    #   *.spef.maxTLU_125.spef      real max SPEF
    #   *.spef.minTLU_125.spef      real min SPEF
    #   *.spef.spef_scenario        metadata, NOT real SPEF
    #
    # Do NOT use glob ${DESIGN_VER}_${clean}.spef*
    ########################################################

    if {$scen eq $SETUP_SCENARIO} {
        set SPEF_FILE($scen) ${HANDOFF_DIR}/${DESIGN_VER}_${clean}.spef.maxTLU_125.spef
    } elseif {$scen eq $HOLD_SCENARIO} {
        set SPEF_FILE($scen) ${HANDOFF_DIR}/${DESIGN_VER}_${clean}.spef.minTLU_125.spef
    } else {
        error "ERROR: Unknown scenario $scen. Cannot select SPEF corner."
    }

    require_file "SPEF for $scen" $SPEF_FILE($scen)

    puts "INFO: Scenario $scen"
    puts "INFO:   SDC  = $SDC_FILE($scen)"
    puts "INFO:   SPEF = $SPEF_FILE($scen)"
}

############################################################
# 4. Read and link design
############################################################

must_run "Reading Verilog" {
    read_verilog $NETLIST
}

must_run "Linking design" {
    link_design $TOP_MODULE
}

must_run "Setting current design" {
    current_design $TOP_MODULE
}

safe_run "Enable PrimeTime power analysis app options" {
    catch {set_app_var power_enable_analysis true}
    catch {set power_enable_analysis true}
}

rpt ${REPORT_DIR}/design_link.rpt {
    puts "===== Current design ====="
    current_design

    puts ""
    puts "===== Designs ====="
    get_designs *

    puts ""
    puts "===== Libraries ====="
    printvar search_path
    printvar target_library
    printvar link_library

    puts ""
    puts "===== Design summary ====="
    report_design
}

############################################################
# 5. Run setup and hold scenarios serially
############################################################

foreach scen $scenarios {
    set clean [clean_scen $scen]
    set SCEN_RPT_DIR ${REPORT_DIR}/${clean}
    file mkdir $SCEN_RPT_DIR

    puts ""
    puts "============================================================"
    puts "INFO: Running PrimeTime scenario: $scen"
    puts "============================================================"

    ########################################################
    # Reset previous scenario constraints and annotations
    ########################################################

    safe_run "Reset design before $scen" {
        reset_design
    }

    ########################################################
    # Read constraints and parasitics
    ########################################################

    must_run "Read SDC for $scen" {
        read_sdc -echo $SDC_FILE($scen)
    }

    safe_run "Remove old parasitics before $scen" {
        if {[llength [info commands remove_annotated_parasitics]] > 0} {
            remove_annotated_parasitics
        } else {
            puts "INFO: remove_annotated_parasitics not available; skipping."
        }
    }

    must_run "Read SPEF for $scen" {
        puts "INFO: Reading SPEF file: $SPEF_FILE($scen)"
        read_parasitics -format SPEF $SPEF_FILE($scen)
    }

    ########################################################
    # Constraint checks before timing update
    ########################################################

    rpt ${SCEN_RPT_DIR}/check_timing_verbose.rpt {
        check_timing -verbose
    }

    rpt ${SCEN_RPT_DIR}/report_clocks.rpt {
        report_clock -skew -attribute
    }

    rpt ${SCEN_RPT_DIR}/report_ports.rpt {
        report_port -verbose
    }

    rpt ${SCEN_RPT_DIR}/report_exceptions_ignored.rpt {
        report_exceptions -ignored
    }

    rpt ${SCEN_RPT_DIR}/report_case_analysis.rpt {
        report_case_analysis
    }

    ########################################################
    # Timing update
    ########################################################

    must_run "Update timing for $scen" {
        update_timing -full
    }

    ########################################################
    # Power analysis and reports
    ########################################################

    if {$RUN_POWER_REPORTS && [scenario_in_list $scen $POWER_SCENARIOS]} {
        set ACTIVITY_FILE [get_power_activity_file $scen]

        safe_run "Annotate power switching activity for $scen" {
            annotate_power_activity $ACTIVITY_FILE $TOP_MODULE
        }

        safe_run "Update power for $scen" {
            if {[llength [info commands update_power]] > 0} {
                update_power
            } else {
                puts "INFO: update_power not available; report_power will trigger/default power update if supported."
            }
        }

        rpt ${SCEN_RPT_DIR}/report_power.rpt {
            puts "===== Power scenario ====="
            puts "Scenario      : $scen"
            puts "SDC           : $SDC_FILE($scen)"
            puts "SPEF          : $SPEF_FILE($scen)"
            puts "Activity file : $ACTIVITY_FILE"
            puts ""

            if {[catch {report_power -significant_digits $POWER_SIGNIFICANT_DIGITS} power_msg]} {
                puts "WARNING: report_power failed for $scen"
                puts $power_msg
            }
        }

        rpt ${SCEN_RPT_DIR}/report_power_hierarchy.rpt {
            puts "===== Hierarchical power scenario ====="
            puts "Scenario      : $scen"
            puts "SDC           : $SDC_FILE($scen)"
            puts "SPEF          : $SPEF_FILE($scen)"
            puts "Activity file : $ACTIVITY_FILE"
            puts ""

            if {[catch {report_power -hierarchy -significant_digits $POWER_SIGNIFICANT_DIGITS} hier_power_msg]} {
                puts "WARNING: report_power -hierarchy failed for $scen"
                puts $hier_power_msg

                puts ""
                puts "===== Retry with report_power -hier ====="
                catch {report_power -hier -significant_digits $POWER_SIGNIFICANT_DIGITS}
            }
        }

        rpt ${SCEN_RPT_DIR}/report_switching_activity.rpt {
            puts "===== Switching activity scenario ====="
            puts "Scenario      : $scen"
            puts "Activity file : $ACTIVITY_FILE"
            puts ""

            if {[catch {report_switching_activity} sw_msg]} {
                puts "WARNING: report_switching_activity failed for $scen"
                puts $sw_msg
            }

            puts ""
            puts "===== Not annotated switching activity, if supported ====="
            catch {report_switching_activity -list_not_annotated}
        }
    } else {
        puts "INFO: Power reports disabled or skipped for scenario $scen"
    }

    ########################################################
    # Parasitic annotation check
    ########################################################

    rpt ${SCEN_RPT_DIR}/report_annotated_parasitics.rpt {
        report_annotated_parasitics -check \
            -internal_nets \
            -boundary_nets \
            -driverless_nets \
            -loadless_nets \
            -pin_to_pin_nets

        puts ""
        puts "===== Not annotated nets, limited to 50 ====="
        report_annotated_parasitics -check \
            -list_not_annotated \
            -max_nets 50
    }

    ########################################################
    # Analysis coverage
    ########################################################

    rpt ${SCEN_RPT_DIR}/report_analysis_coverage.rpt {
        report_analysis_coverage

        puts ""
        puts "===== Untested all checks ====="
        catch {report_analysis_coverage -status_details untested}

        puts ""
        puts "===== Untested setup checks ====="
        catch {report_analysis_coverage -status_details untested -check setup}

        puts ""
        puts "===== Untested hold checks ====="
        catch {report_analysis_coverage -status_details untested -check hold}

        puts ""
        puts "===== Untested min pulse width checks ====="
        catch {report_analysis_coverage -status_details untested -check min_pulse_width}

        puts ""
        puts "===== Untested clock gating setup checks ====="
        catch {report_analysis_coverage -status_details untested -check clock_gating_setup}

        puts ""
        puts "===== Untested clock gating hold checks ====="
        catch {report_analysis_coverage -status_details untested -check clock_gating_hold}
    }

    ########################################################
    # Summary timing reports
    ########################################################

    rpt ${SCEN_RPT_DIR}/report_global_timing.rpt {
        report_global_timing
    }

    rpt ${SCEN_RPT_DIR}/report_qor.rpt {
        report_qor
    }

    rpt ${SCEN_RPT_DIR}/report_constraints.rpt {
        report_constraints -all_violators

        puts ""
        puts "===== Max capacitance ====="
        catch {report_constraints -max_capacitance -all_violators}

        puts ""
        puts "===== Max transition ====="
        catch {report_constraints -max_transition -all_violators}

        puts ""
        puts "===== Min pulse width ====="
        catch {report_constraints -min_pulse_width -all_violators}
    }

    ########################################################
    # Detailed setup/hold timing reports
    #
    # Important:
    #   The top-path reports below intentionally do NOT use
    #   -slack_lesser_than 0.0. They therefore print the worst
    #   setup/hold paths even when timing is clean.
    #
    #   The *_violators.rpt reports keep the violation-only view.
    ########################################################

    if {$scen eq $SETUP_SCENARIO} {
        ####################################################
        # Setup / max-delay reports for slow_max corner
        ####################################################

        rpt ${SCEN_RPT_DIR}/timing_setup_max_top_paths.rpt {
            puts "===== Detailed setup timing: worst max-delay paths ====="
            puts "Scenario      : $scen"
            puts "SDC           : $SDC_FILE($scen)"
            puts "SPEF          : $SPEF_FILE($scen)"
            puts "Slack filter  : < $TIMING_TOP_PATH_SLACK_LIMIT (effectively none)"
            puts "Max paths     : $TIMING_MAX_PATHS"
            puts "N-worst       : $TIMING_NWORST"
            puts ""

            report_timing \
                -delay_type max \
                -path_type full_clock_expanded \
                -input_pins \
                -nets \
                -capacitance \
                -transition \
                -max_paths $TIMING_MAX_PATHS \
                -nworst $TIMING_NWORST \
                -slack_lesser_than $TIMING_TOP_PATH_SLACK_LIMIT \
                -significant_digits $TIMING_SIGNIFICANT_DIGITS \
                -nosplit
        }

        rpt ${SCEN_RPT_DIR}/timing_setup_max_by_group.rpt {
            puts "===== Detailed setup timing by path group ====="
            puts "Scenario     : $scen"
            puts "Slack filter : < $TIMING_TOP_PATH_SLACK_LIMIT (effectively none)"
            puts ""

            if {[catch {set path_groups [get_path_groups *]} pg_msg]} {
                puts "WARNING: get_path_groups failed"
                puts $pg_msg
            } else {
                foreach_in_collection pg $path_groups {
                    set pg_name [get_object_name $pg]
                    puts ""
                    puts "============================================================"
                    puts "SETUP PATH GROUP: $pg_name"
                    puts "============================================================"

                    if {[catch {
                        report_timing \
                            -delay_type max \
                            -group $pg_name \
                            -path_type full_clock_expanded \
                            -input_pins \
                            -nets \
                            -capacitance \
                            -transition \
                            -max_paths $TIMING_NWORST \
                            -nworst $TIMING_NWORST \
                            -slack_lesser_than $TIMING_TOP_PATH_SLACK_LIMIT \
                            -significant_digits $TIMING_SIGNIFICANT_DIGITS \
                            -nosplit
                    } rpt_msg]} {
                        puts "WARNING: setup report_timing failed for group $pg_name"
                        puts $rpt_msg
                    }
                }
            }
        }

        rpt ${SCEN_RPT_DIR}/timing_setup_max_violators.rpt {
            puts "===== Setup timing violators only ====="
            puts "Scenario     : $scen"
            puts "Slack filter : slack < 0.0"
            puts ""

            report_timing \
                -delay_type max \
                -path_type full_clock_expanded \
                -input_pins \
                -nets \
                -capacitance \
                -transition \
                -max_paths $TIMING_MAX_PATHS \
                -nworst $TIMING_NWORST \
                -slack_lesser_than 0.0 \
                -significant_digits $TIMING_SIGNIFICANT_DIGITS \
                -nosplit
        }

        rpt ${SCEN_RPT_DIR}/timing_setup_max_pba_top_paths.rpt {
            puts "===== PBA setup timing: worst max-delay paths ====="
            puts "Scenario     : $scen"
            puts "Slack filter : < $TIMING_TOP_PATH_SLACK_LIMIT (effectively none)"
            puts ""

            if {[catch {
                report_timing \
                    -pba_mode path \
                    -delay_type max \
                    -path_type full_clock_expanded \
                    -input_pins \
                    -nets \
                    -capacitance \
                    -transition \
                    -max_paths $TIMING_MAX_PATHS \
                    -nworst $TIMING_NWORST \
                    -slack_lesser_than $TIMING_TOP_PATH_SLACK_LIMIT \
                    -significant_digits $TIMING_SIGNIFICANT_DIGITS \
                    -nosplit
            } pba_msg]} {
                puts "WARNING: setup PBA report_timing failed"
                puts $pba_msg
            }
        }

        rpt ${SCEN_RPT_DIR}/timing_setup_max_pba_violators.rpt {
            puts "===== PBA setup timing violators only ====="
            puts "Scenario     : $scen"
            puts "Slack filter : slack < 0.0"
            puts ""

            if {[catch {
                report_timing \
                    -pba_mode path \
                    -delay_type max \
                    -path_type full_clock_expanded \
                    -input_pins \
                    -nets \
                    -capacitance \
                    -transition \
                    -max_paths $TIMING_MAX_PATHS \
                    -nworst $TIMING_NWORST \
                    -slack_lesser_than 0.0 \
                    -significant_digits $TIMING_SIGNIFICANT_DIGITS \
                    -nosplit
            } pba_vio_msg]} {
                puts "WARNING: setup PBA violator report_timing failed"
                puts $pba_vio_msg
            }
        }
    }

    if {$scen eq $HOLD_SCENARIO} {
        ####################################################
        # Hold / min-delay reports for fast_min corner
        ####################################################

        rpt ${SCEN_RPT_DIR}/timing_hold_min_top_paths.rpt {
            puts "===== Detailed hold timing: worst min-delay paths ====="
            puts "Scenario      : $scen"
            puts "SDC           : $SDC_FILE($scen)"
            puts "SPEF          : $SPEF_FILE($scen)"
            puts "Slack filter  : < $TIMING_TOP_PATH_SLACK_LIMIT (effectively none)"
            puts "Max paths     : $TIMING_MAX_PATHS"
            puts "N-worst       : $TIMING_NWORST"
            puts ""

            report_timing \
                -delay_type min \
                -path_type full_clock_expanded \
                -input_pins \
                -nets \
                -capacitance \
                -transition \
                -max_paths $TIMING_MAX_PATHS \
                -nworst $TIMING_NWORST \
                -slack_lesser_than $TIMING_TOP_PATH_SLACK_LIMIT \
                -significant_digits $TIMING_SIGNIFICANT_DIGITS \
                -nosplit
        }

        rpt ${SCEN_RPT_DIR}/timing_hold_min_by_group.rpt {
            puts "===== Detailed hold timing by path group ====="
            puts "Scenario     : $scen"
            puts "Slack filter : < $TIMING_TOP_PATH_SLACK_LIMIT (effectively none)"
            puts ""

            if {[catch {set path_groups [get_path_groups *]} pg_msg]} {
                puts "WARNING: get_path_groups failed"
                puts $pg_msg
            } else {
                foreach_in_collection pg $path_groups {
                    set pg_name [get_object_name $pg]
                    puts ""
                    puts "============================================================"
                    puts "HOLD PATH GROUP: $pg_name"
                    puts "============================================================"

                    if {[catch {
                        report_timing \
                            -delay_type min \
                            -group $pg_name \
                            -path_type full_clock_expanded \
                            -input_pins \
                            -nets \
                            -capacitance \
                            -transition \
                            -max_paths $TIMING_NWORST \
                            -nworst $TIMING_NWORST \
                            -slack_lesser_than $TIMING_TOP_PATH_SLACK_LIMIT \
                            -significant_digits $TIMING_SIGNIFICANT_DIGITS \
                            -nosplit
                    } rpt_msg]} {
                        puts "WARNING: hold report_timing failed for group $pg_name"
                        puts $rpt_msg
                    }
                }
            }
        }

        rpt ${SCEN_RPT_DIR}/timing_hold_min_violators.rpt {
            puts "===== Hold timing violators only ====="
            puts "Scenario     : $scen"
            puts "Slack filter : slack < 0.0"
            puts ""

            report_timing \
                -delay_type min \
                -path_type full_clock_expanded \
                -input_pins \
                -nets \
                -capacitance \
                -transition \
                -max_paths $TIMING_MAX_PATHS \
                -nworst $TIMING_NWORST \
                -slack_lesser_than 0.0 \
                -significant_digits $TIMING_SIGNIFICANT_DIGITS \
                -nosplit
        }

        rpt ${SCEN_RPT_DIR}/timing_hold_min_pba_top_paths.rpt {
            puts "===== PBA hold timing: worst min-delay paths ====="
            puts "Scenario     : $scen"
            puts "Slack filter : < $TIMING_TOP_PATH_SLACK_LIMIT (effectively none)"
            puts ""

            if {[catch {
                report_timing \
                    -pba_mode path \
                    -delay_type min \
                    -path_type full_clock_expanded \
                    -input_pins \
                    -nets \
                    -capacitance \
                    -transition \
                    -max_paths $TIMING_MAX_PATHS \
                    -nworst $TIMING_NWORST \
                    -slack_lesser_than $TIMING_TOP_PATH_SLACK_LIMIT \
                    -significant_digits $TIMING_SIGNIFICANT_DIGITS \
                    -nosplit
            } pba_msg]} {
                puts "WARNING: hold PBA report_timing failed"
                puts $pba_msg
            }
        }

        rpt ${SCEN_RPT_DIR}/timing_hold_min_pba_violators.rpt {
            puts "===== PBA hold timing violators only ====="
            puts "Scenario     : $scen"
            puts "Slack filter : slack < 0.0"
            puts ""

            if {[catch {
                report_timing \
                    -pba_mode path \
                    -delay_type min \
                    -path_type full_clock_expanded \
                    -input_pins \
                    -nets \
                    -capacitance \
                    -transition \
                    -max_paths $TIMING_MAX_PATHS \
                    -nworst $TIMING_NWORST \
                    -slack_lesser_than 0.0 \
                    -significant_digits $TIMING_SIGNIFICANT_DIGITS \
                    -nosplit
            } pba_vio_msg]} {
                puts "WARNING: hold PBA violator report_timing failed"
                puts $pba_vio_msg
            }
        }
    }

    ########################################################
    # Optional debug reports
    ########################################################

    rpt ${SCEN_RPT_DIR}/report_disable_timing.rpt {
        catch {report_disable_timing}
    }

    rpt ${SCEN_RPT_DIR}/report_global_slack.rpt {
        catch {report_global_slack}
    }

    rpt ${SCEN_RPT_DIR}/report_message_info.rpt {
        print_message_info
    }
}

############################################################
# 6. Save PrimeTime session
############################################################

safe_run "Removing old PrimeTime session directory" {
    if {[file exists $SESSION_DIR]} {
        file delete -force $SESSION_DIR
    }
}

safe_run "Saving PrimeTime session" {
    save_session $SESSION_DIR
}

############################################################
# 7. Final summary and quit
############################################################

rpt ${REPORT_DIR}/pt_run_summary.rpt {
    puts "===== PrimeTime STA completed ====="
    puts "Design      : $DESIGN"
    puts "Top module  : $TOP_MODULE"
    puts "Handoff dir : $HANDOFF_DIR"
    puts "Report dir  : $REPORT_DIR"
    puts "Session dir : $SESSION_DIR"
    puts "Scenarios   : $scenarios"
    puts "Power rpt   : $RUN_POWER_REPORTS"
    puts "Power scen  : $POWER_SCENARIOS"

    puts ""
    print_message_info
}

print_message_info
quit

