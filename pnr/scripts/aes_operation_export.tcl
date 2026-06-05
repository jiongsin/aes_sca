############################################################
# ICC2 PrimeTime Handoff Export Only Script
# DOM-based Masked AES Accelerator
#
# Purpose:
#   Run in icc2_shell.
#   Export only design handoff files needed by PrimeTime.
#   This script does NOT generate or run any PrimeTime Tcl script.
#   This script does NOT generate a MANIFEST file.
############################################################

source ./scripts/icc2_lib_setup.tcl

set mode    $env(MODE)
set version $env(VER)
set ntl_ver $env(DESIGN_VER)

############################################################
# 0. User switches
############################################################

if {[info exists env(INPUT_BLOCK)]} {
    set INPUT_BLOCK $env(INPUT_BLOCK)
} else {
    set INPUT_BLOCK ${ntl_ver}_after_route
}

set SETUP_SCENARIO func.slow_max
set HOLD_SCENARIO  func.fast_min

set WRITE_SPEF 1
set WRITE_SDF  1
set WRITE_DEF  1
set WRITE_UPF  0
set WRITE_ADV_TECH_RULES 1
set WRITE_FLOORPLAN 1

set COMPRESS_SPEF 0

############################################################
# 1. Directory setup
############################################################

set OUTPUT_DIR ./results/${ntl_ver}
set REPORT_DIR ${OUTPUT_DIR}/reports_export

file mkdir $OUTPUT_DIR
file mkdir $REPORT_DIR

############################################################
# 2. Helper procedures
############################################################

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

proc scenario_exists {scen} {
    set c [get_scenarios -quiet $scen]
    if {[sizeof_collection $c] > 0} {
        return 1
    }
    return 0
}

proc file_exists_check {label file required} {
    if {[file exists $file]} {
        puts "INFO: Found $label: $file"
        return 1
    }

    if {$required} {
        puts "ERROR: Missing required $label: $file"
        error "Missing required $label: $file"
    } else {
        puts "WARNING: Missing optional $label: $file"
        return 0
    }
}

############################################################
# 3. Open final ICC2 block
############################################################

puts "INFO: Opening input block for PrimeTime handoff export: $INPUT_BLOCK"

must_run "Opening ICC2 input block $INPUT_BLOCK" {
    open_block $INPUT_BLOCK
    current_block
}

safe_redirect ${REPORT_DIR}/01_icc2_export_design_summary.rpt {
    puts "===== current block ====="
    current_block

    puts ""
    puts "===== design summary ====="
    report_design -summary

    puts ""
    puts "===== scenarios ====="
    report_scenarios

    puts ""
    puts "===== clocks ====="
    if {[catch {report_clocks} rc_msg]} {
        puts "WARNING: report_clocks failed"
        puts $rc_msg
    }
}

############################################################
# 4. Scenario setup
############################################################

set export_scenarios {}

if {[scenario_exists $SETUP_SCENARIO]} {
    lappend export_scenarios $SETUP_SCENARIO

    must_run "Setting setup scenario status for $SETUP_SCENARIO" {
        set_scenario_status $SETUP_SCENARIO \
            -active true \
            -setup true \
            -hold false \
            -leakage_power true \
            -dynamic_power true
    }
} else {
    puts "WARNING: Setup scenario $SETUP_SCENARIO not found."
}

if {[scenario_exists $HOLD_SCENARIO]} {
    lappend export_scenarios $HOLD_SCENARIO

    must_run "Setting hold scenario status for $HOLD_SCENARIO" {
        set_scenario_status $HOLD_SCENARIO \
            -active true \
            -setup false \
            -hold true \
            -leakage_power false \
            -dynamic_power false
    }
} else {
    puts "WARNING: Hold scenario $HOLD_SCENARIO not found."
}

if {[llength $export_scenarios] == 0} {
    puts "WARNING: No expected scenarios found. Falling back to all scenarios."

    foreach_in_collection s [get_scenarios -quiet *] {
        lappend export_scenarios [get_object_name $s]
    }
}

if {[llength $export_scenarios] == 0} {
    puts "ERROR: No scenarios available for export."
    error "No scenarios available for export."
}

safe_redirect ${REPORT_DIR}/02_icc2_export_scenarios.rpt {
    puts "PrimeTime handoff export scenarios: $export_scenarios"
    puts ""
    report_scenarios
}

############################################################
# 5. Final checks before export
############################################################

safe_redirect ${REPORT_DIR}/03_icc2_pre_export_physical_checks.rpt {
    puts "===== check_legality ====="
    if {[catch {check_legality} check_legality_msg]} {
        puts "WARNING: check_legality failed"
        puts $check_legality_msg
    }

    puts ""
    puts "===== check_routes ====="
    if {[catch {check_routes} check_routes_msg]} {
        puts "WARNING: check_routes failed"
        puts $check_routes_msg
    }

    puts ""
    puts "===== check_lvs ====="
    if {[catch {check_lvs} check_lvs_msg]} {
        puts "WARNING: check_lvs failed"
        puts $check_lvs_msg
    }

    puts ""
    puts "===== check_pg_connectivity ====="
    if {[catch {check_pg_connectivity} pg_conn_msg]} {
        puts "WARNING: check_pg_connectivity failed"
        puts $pg_conn_msg
    }

    puts ""
    puts "===== check_pg_drc -ignore_std_cells ====="
    if {[catch {check_pg_drc -ignore_std_cells} pg_drc_msg]} {
        puts "WARNING: check_pg_drc failed"
        puts $pg_drc_msg
    }
}

safe_redirect ${REPORT_DIR}/04_icc2_pre_export_timing_drv.rpt {
    foreach scen $export_scenarios {
        current_scenario $scen

        puts ""
        puts "============================================================"
        puts "Scenario: $scen"
        puts "============================================================"

        puts ""
        puts "===== report_timing max ====="
        if {[catch {report_timing -delay_type max -path_type full -max_paths 20} rtmax_msg]} {
            puts "WARNING: report_timing max failed for $scen"
            puts $rtmax_msg
        }

        puts ""
        puts "===== report_timing min ====="
        if {[catch {report_timing -delay_type min -path_type full -max_paths 20} rtmin_msg]} {
            puts "WARNING: report_timing min failed for $scen"
            puts $rtmin_msg
        }

        puts ""
        puts "===== DRV constraints ====="
        if {[catch {report_constraints -max_capacitance -max_transition -all_violators} drv_msg]} {
            puts "WARNING: report_constraints DRV failed for $scen"
            puts $drv_msg
        }
    }
}

############################################################
# 6. Save ICC2 handoff checkpoint
############################################################

must_run "Saving ICC2 export checkpoint" {
    save_block -as ${ntl_ver}_export
    save_lib
}

############################################################
# 7. Export gate-level Verilog netlist
############################################################

set VERILOG_FILE ${OUTPUT_DIR}/${ntl_ver}.v

must_run "Writing PrimeTime Verilog netlist" {
    write_verilog $VERILOG_FILE
}

############################################################
# 8. Export UPF if enabled and available
############################################################

if {$WRITE_UPF} {
    set UPF_FILE ${OUTPUT_DIR}/${ntl_ver}.upf

    safe_run "Writing UPF" {
        save_upf $UPF_FILE
    }
}

############################################################
# 9. Export SDC per scenario
############################################################

array unset sdc_file

foreach scen $export_scenarios {
    current_scenario $scen

    set clean_scen [string map {. _ / _ : _} $scen]
    set sdc_file($scen) ${OUTPUT_DIR}/${ntl_ver}_${clean_scen}.sdc

    must_run "Writing SDC for $scen" {
        write_sdc -output $sdc_file($scen)
    }
}

############################################################
# 10. Export SPEF parasitics per scenario
############################################################

array unset spef_file
array unset spef_files

if {$WRITE_SPEF} {
    foreach scen $export_scenarios {
        current_scenario $scen

        set clean_scen [string map {. _ / _ : _} $scen]

        if {$COMPRESS_SPEF} {
            set spef_prefix ${OUTPUT_DIR}/${ntl_ver}_${clean_scen}.spef.gz
        } else {
            set spef_prefix ${OUTPUT_DIR}/${ntl_ver}_${clean_scen}.spef
        }

        set spef_file($scen) $spef_prefix

        puts "INFO: Writing SPEF for $scen"
        puts "INFO: SPEF prefix: $spef_prefix"

        if {$COMPRESS_SPEF} {
            if {[catch {
                write_parasitics -format spef -compress -output $spef_prefix
            } spef_msg]} {
                puts "WARNING: write_parasitics -output compressed form failed for $scen"
                puts "WARNING: $spef_msg"

                if {[catch {
                    write_parasitics -format spef -compress $spef_prefix
                } spef_msg2]} {
                    puts "ERROR: Could not write compressed SPEF for $scen"
                    puts "ERROR: $spef_msg2"
                    error "SPEF export failed for $scen"
                }
            }
        } else {
            if {[catch {
                write_parasitics -format spef -output $spef_prefix
            } spef_msg]} {
                puts "WARNING: write_parasitics -output form failed for $scen"
                puts "WARNING: $spef_msg"

                if {[catch {
                    write_parasitics -format spef $spef_prefix
                } spef_msg2]} {
                    puts "ERROR: Could not write SPEF for $scen"
                    puts "ERROR: $spef_msg2"
                    error "SPEF export failed for $scen"
                }
            }
        }

        set generated_spefs [glob -nocomplain ${spef_prefix}*]

        if {[llength $generated_spefs] == 0} {
            puts "ERROR: SPEF command completed but no SPEF files were created with prefix:"
            puts "ERROR:   $spef_prefix"
            error "Missing SPEF after export for $scen"
        }

        set spef_files($scen) $generated_spefs

        puts "INFO: SPEF files created for $scen:"
        foreach f $generated_spefs {
            puts "INFO:   $f"
        }
    }
}

############################################################
# 11. Export optional SDF per scenario
############################################################

array unset sdf_file

if {$WRITE_SDF} {
    foreach scen $export_scenarios {
        current_scenario $scen

        set clean_scen [string map {. _ / _ : _} $scen]
        set sdf_file($scen) ${OUTPUT_DIR}/${ntl_ver}_${clean_scen}.sdf

        safe_run "Writing SDF for $scen" {
            write_sdf $sdf_file($scen)
        }
    }
}

############################################################
# 12. Export DEF / floorplan physical context
############################################################

if {$WRITE_DEF} {
    set DEF_FILE ${OUTPUT_DIR}/${ntl_ver}.def

    must_run "Writing DEF physical context" {
        write_def $DEF_FILE
    }
}

if {$WRITE_FLOORPLAN} {
    set FP_FILE ${OUTPUT_DIR}/${ntl_ver}.fp

    safe_run "Writing ICC2 floorplan file" {
        write_floorplan -force -output $FP_FILE
    }
}

############################################################
# 13. Export advanced technology / standard-cell spacing rules
############################################################

if {$WRITE_ADV_TECH_RULES} {
    set ADV_TECH_BASENAME ${ntl_ver}_lib_spacing_rules.tcl
    set ADV_TECH_FILE     ${OUTPUT_DIR}/${ADV_TECH_BASENAME}
    set ADV_TECH_FOUND    ""

    safe_run "Exporting advanced technology spacing rules" {
        export_advanced_technology_rules $ADV_TECH_FILE
    }

    set found_adv_files [glob -nocomplain \
        ${OUTPUT_DIR}/*spacing* \
        ${OUTPUT_DIR}/*rules* \
        ./*spacing* \
        ./*rules* \
    ]

    if {[llength $found_adv_files] > 0} {
        set ADV_TECH_FOUND [lindex $found_adv_files 0]
        puts "INFO: Found possible advanced technology rules file: $ADV_TECH_FOUND"
    } else {
        puts "INFO: No advanced technology rules file found."
        puts "INFO: Continuing because this file is optional for PrimeTime handoff."
    }
}

############################################################
# 14. Final file existence checks
############################################################

file_exists_check "Verilog netlist" $VERILOG_FILE 1

foreach scen $export_scenarios {
    if {[info exists sdc_file($scen)]} {
        file_exists_check "SDC for $scen" $sdc_file($scen) 1
    }

    if {$WRITE_SPEF} {
        if {[info exists spef_files($scen)]} {
            foreach f $spef_files($scen) {
                file_exists_check "SPEF for $scen" $f 1
            }
        } elseif {[info exists spef_file($scen)]} {
            set found_spefs [glob -nocomplain $spef_file($scen)*]

            if {[llength $found_spefs] == 0} {
                puts "ERROR: Missing required SPEF for $scen with prefix:"
                puts "ERROR:   $spef_file($scen)"
                error "Missing required SPEF for $scen"
            }

            foreach f $found_spefs {
                file_exists_check "SPEF for $scen" $f 1
            }

            set spef_files($scen) $found_spefs
        } else {
            puts "ERROR: SPEF variable not defined for $scen"
            error "SPEF variable not defined for $scen"
        }
    }

    if {$WRITE_SDF && [info exists sdf_file($scen)]} {
        file_exists_check "SDF for $scen" $sdf_file($scen) 0
    }
}

if {$WRITE_UPF && [info exists UPF_FILE]} {
    file_exists_check "UPF" $UPF_FILE 0
}

if {$WRITE_DEF && [info exists DEF_FILE]} {
    file_exists_check "DEF" $DEF_FILE 1
}

if {$WRITE_FLOORPLAN && [info exists FP_FILE]} {
    file_exists_check "ICC2 floorplan" $FP_FILE 0
}

if {$WRITE_ADV_TECH_RULES} {
    if {[info exists ADV_TECH_FOUND] && $ADV_TECH_FOUND ne ""} {
        file_exists_check "advanced technology rules" $ADV_TECH_FOUND 0
    } else {
        puts "INFO: Advanced technology rules file not found; optional check skipped."
    }
}

############################################################
# 15. Final summary report
############################################################

safe_redirect ${REPORT_DIR}/05_icc2_export_summary.rpt {
    puts "===== ICC2 PrimeTime handoff export complete ====="
    puts "Design      : $ntl_ver"
    puts "Input block : $INPUT_BLOCK"
    puts "Output dir  : $OUTPUT_DIR"
    puts "Scenarios   : $export_scenarios"
    puts ""

    puts "Main output files:"
    puts "  Verilog    : $VERILOG_FILE"

    if {[info exists UPF_FILE]} {
        puts "  UPF        : $UPF_FILE"
    }

    foreach scen $export_scenarios {
        if {[info exists sdc_file($scen)]} {
            puts "  SDC $scen : $sdc_file($scen)"
        } else {
            puts "  SDC $scen : NOT FOUND"
        }

        if {$WRITE_SPEF} {
            if {[info exists spef_files($scen)]} {
                foreach f $spef_files($scen) {
                    puts "  SPEF $scen: $f"
                }
            } elseif {[info exists spef_file($scen)]} {
                set found_spefs [glob -nocomplain $spef_file($scen)*]

                if {[llength $found_spefs] > 0} {
                    foreach f $found_spefs {
                        puts "  SPEF $scen: $f"
                    }
                } else {
                    puts "  SPEF $scen: NOT FOUND"
                }
            } else {
                puts "  SPEF $scen: NOT FOUND"
            }
        }

        if {$WRITE_SDF} {
            if {[info exists sdf_file($scen)]} {
                puts "  SDF $scen : $sdf_file($scen)"
            } else {
                puts "  SDF $scen : NOT FOUND"
            }
        }
    }

    if {$WRITE_DEF} {
        if {[info exists DEF_FILE]} {
            puts "  DEF        : $DEF_FILE"
        } else {
            puts "  DEF        : NOT FOUND"
        }
    }

    if {$WRITE_FLOORPLAN} {
        if {[info exists FP_FILE]} {
            puts "  Floorplan  : $FP_FILE"
        } else {
            puts "  Floorplan  : NOT FOUND"
        }
    }

    if {$WRITE_ADV_TECH_RULES} {
        if {[info exists ADV_TECH_FOUND] && $ADV_TECH_FOUND ne ""} {
            puts "  Adv rules  : $ADV_TECH_FOUND"
        } else {
            puts "  Adv rules  : OPTIONAL / NOT FOUND"
        }
    }

    puts "  ICC2 block : ${ntl_ver}_export"

    puts ""
    puts "PrimeTime corner mapping hint:"
    puts "  slow/max scenario should read the maxTLU SPEF file."
    puts "  fast/min scenario should read the minTLU SPEF file."
}

puts ""
puts "============================================================"
puts "ICC2 PrimeTime handoff export completed."
puts "Output directory: $OUTPUT_DIR"
puts "Reports         : $REPORT_DIR"
puts "============================================================"

############################################################
# End of ICC2 PrimeTime handoff export only script
############################################################

exit
