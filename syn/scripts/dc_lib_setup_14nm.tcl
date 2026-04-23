## Set Library Base Path
set LIB_PATH "/data/synopsys/lib/saed14nm/lib"

## Load Design, Libraries
set_app_var target_library "saed14lvt_ss0p72v125c.db saed14hvt_ss0p72v125c.db saed14rvt_ss0p72v125c.db saed14slvt_ss0p72v125c.db"
set_app_var link_library "* $target_library saed14sram_ss0p72v125c.db saed14io_fc_ss0p72v125c_1p62v.db saed14pll_ss0p72v125c.db"

set_app_var search_path "$search_path . ./scripts ../rtl \
 ${LIB_PATH}/stdcell_hvt/db_nldm \
 ${LIB_PATH}/stdcell_lvt/db_nldm \
 ${LIB_PATH}/stdcell_rvt/db_nldm \
 ${LIB_PATH}/stdcell_slvt/db_nldm \
 ${LIB_PATH}/sram/logic_synth/dual \
 ${LIB_PATH}/io_std/db_nldm \
 ${LIB_PATH}/pll/logic_synth"

set MW_REFERENCE_LIB_DIRS "${LIB_PATH}/stdcell_hvt/milkyway/saed14nm_hvt_1p9m \
                           ${LIB_PATH}/stdcell_rvt/milkyway/saed14nm_rvt_1p9m \
                           ${LIB_PATH}/stdcell_lvt/milkyway/saed14nm_lvt_1p9m \
                           ${LIB_PATH}/stdcell_slvt/milkyway/saed14nm_slvt_1p9m \
                           ${LIB_PATH}/sram/milkyway/saed14_sram_1rw \
                           ${LIB_PATH}/io_std/milkyway/saed14io_std_fc"

set TECH_FILE "${LIB_PATH}/tech/milkyway/saed14nm_1p9m_mw.tf" 
set MAP_FILE  "${LIB_PATH}/tech/star_rc/saed14nm_tf_itf_tluplus.map"  
set TLUPLUS_MAX_FILE "${LIB_PATH}/tech/star_rc/max/saed14nm_1p9m_Cmax.tluplus"  
set TLUPLUS_MIN_FILE "${LIB_PATH}/tech/star_rc/min/saed14nm_1p9m_Cmin.tluplus" 

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

check_library > ./reports/dc_check_lib.rpt 

set_tlu_plus_files -max_tluplus $TLUPLUS_MAX_FILE \
      -min_tluplus $TLUPLUS_MIN_FILE \
      -tech2itf_map $MAP_FILE
check_tlu_plus_files

define_design_lib WORK -path ./work
set_app_var sh_command_log_file ./logs/command.log
