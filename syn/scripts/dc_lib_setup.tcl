##Load Design, Libraries
set_app_var target_library "saed32lvt_ss0p95v125c.db saed32hvt_ss0p95v125c.db saed32rvt_ss0p95v125c.db"
set_app_var link_library "* $target_library saed32sram_ss0p95v125c.db"
set_app_var search_path "$search_path . ./scripts ../rtl \
 ../libs/saed32nm/lib/stdcell_hvt/db_nldm \
 ../libs/saed32nm/lib/stdcell_lvt/db_nldm \
 ../libs/saed32nm/lib/stdcell_rvt/db_nldm \
 ../libs/saed32nm/lib/sram/db_nldm"

set MW_REFERENCE_LIB_DIRS "../libs/saed32nm/lib/stdcell_hvt/milkyway/saed32nm_hvt_1p9m \
                           ../libs/saed32nm/lib/stdcell_rvt/milkyway/saed32nm_rvt_1p9m \
			   ../libs/saed32nm/lib/stdcell_lvt/milkyway/saed32nm_lvt_1p9m \
			   ../libs/saed32nm/lib/sram/milkyway/SRAM32NM"
set TECH_FILE "../libs/saed32nm/lib/tech/milkyway/saed32nm_1p9m_mw.tf" 
set MAP_FILE  "../libs/saed32nm/lib/tech/star_rc/saed32nm_tf_itf_tluplus.map"  
set TLUPLUS_MAX_FILE "../libs/saed32nm/lib/tech/star_rc/saed32nm_1p9m_Cmax.tluplus"  
set TLUPLUS_MIN_FILE "../libs/saed32nm/lib/tech/star_rc/saed32nm_1p9m_Cmin.tluplus" 

set mw_reference_library ${MW_REFERENCE_LIB_DIRS}
set mw_design_library MYLIB

if {![file isdirectory $mw_design_library ]} {
   create_mw_lib   -technology $TECH_FILE \
     -mw_reference_library $mw_reference_library \
      $mw_design_library
    } else {
      set_mw_lib_reference $mw_design_library -mw_reference_library $mw_reference_library
    }
open_mw_lib     $mw_design_library

check_library > ./reports/dc_check_lib.rpt 

set_tlu_plus_files -max_tluplus $TLUPLUS_MAX_FILE \
      -min_tluplus $TLUPLUS_MIN_FILE \
      -tech2itf_map $MAP_FILE
check_tlu_plus_files
