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

set TOP_MODULE ${DESIGN}_${VER}_MODE${MODE}

set HANDOFF_DIR ./results/${DESIGN_VER}
set REPORT_DIR  ${HANDOFF_DIR}/reports_sta
set SESSION_DIR ${HANDOFF_DIR}/pt_session

file mkdir $REPORT_DIR
file mkdir $SESSION_DIR

set SETUP_SCENARIO func.slow_max
set HOLD_SCENARIO  func.fast_min

set scenarios [list $SETUP_SCENARIO $HOLD_SCENARIO]

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
    # Detailed setup timing reports
    ########################################################

    rpt ${SCEN_RPT_DIR}/timing_setup_max.rpt {
        report_timing \
            -delay_type max \
            -path_type full_clock_expanded \
            -input_pins \
            -nets \
            -capacitance \
            -transition \
            -max_paths 50 \
            -slack_lesser_than 0.0
    }

    ########################################################
    # Detailed hold timing reports
    ########################################################

    rpt ${SCEN_RPT_DIR}/timing_hold_min.rpt {
        report_timing \
            -delay_type min \
            -path_type full_clock_expanded \
            -input_pins \
            -nets \
            -capacitance \
            -transition \
            -max_paths 50 \
            -slack_lesser_than 0.0
    }

    ########################################################
    # Optional PBA reports
    ########################################################

    rpt ${SCEN_RPT_DIR}/timing_setup_max_pba.rpt {
        catch {
            report_timing \
                -pba_mode path \
                -delay_type max \
                -path_type full_clock_expanded \
                -input_pins \
                -nets \
                -capacitance \
                -transition \
                -max_paths 50 \
                -slack_lesser_than 0.0
        }
    }

    rpt ${SCEN_RPT_DIR}/timing_hold_min_pba.rpt {
        catch {
            report_timing \
                -pba_mode path \
                -delay_type min \
                -path_type full_clock_expanded \
                -input_pins \
                -nets \
                -capacitance \
                -transition \
                -max_paths 50 \
                -slack_lesser_than 0.0
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

    puts ""
    print_message_info
}

print_message_info
quit
