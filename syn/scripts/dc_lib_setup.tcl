# Design Compiler library setup for the 32 nm standard-cell flow.
# Defines target/link libraries and search paths required by the synthesis scripts.

set LIB_PATH "/data/synopsys/lib/saed32nm/lib/"
# /home/host/libs/saed32nm/lib"

set_app_var target_library "saed32hvt_ss0p95v125c.db"
set_app_var link_library "* $target_library"
set_app_var search_path "$search_path . ./scripts ../rtl \
 ${LIB_PATH}/stdcell_hvt/db_nldm"

set MW_REFERENCE_LIB_DIRS "${LIB_PATH}/stdcell_hvt/milkyway/saed32nm_hvt_1p9m"

set TECH_FILE "${LIB_PATH}/tech/milkyway/saed32nm_1p9m_mw.tf"
set MAP_FILE  "${LIB_PATH}/tech/star_rc/saed32nm_tf_itf_tluplus.map"
set TLUPLUS_MAX_FILE "${LIB_PATH}/tech/star_rc/saed32nm_1p9m_Cmax.tluplus"
set TLUPLUS_MIN_FILE "${LIB_PATH}/tech/star_rc/saed32nm_1p9m_Cmin.tluplus"

set mw_reference_library ${MW_REFERENCE_LIB_DIRS}
set mw_design_library MYLIB

if {![file isdirectory $mw_design_library ]} {
   create_mw_lib -technology $TECH_FILE \
     -mw_reference_library $mw_reference_library \
      $mw_design_library
    } else {
      set_mw_lib_reference $mw_design_library -mw_reference_library $mw_reference_library
    }
open_mw_lib $mw_design_library

check_library > ./logs/dc_check_lib.rpt

set_tlu_plus_files -max_tluplus $TLUPLUS_MAX_FILE \
      -min_tluplus $TLUPLUS_MIN_FILE \
      -tech2itf_map $MAP_FILE
check_tlu_plus_files

define_design_lib WORK -path ./work
set_app_var sh_command_log_file ./logs/command.log

