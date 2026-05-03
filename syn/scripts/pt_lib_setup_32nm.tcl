## Set Library Base Path
#set LIB_PATH "/home/host/libs/saed32nm/lib"

##Load Design, Libraries
#set_app_var target_library "saed32lvt_ss0p95v125c.db saed32hvt_ss0p95v125c.db saed32rvt_ss0p95v125c.db"
#set_app_var link_library "* $target_library saed32sram_ss0p95v125c.db"

#set SYN_NTL [glob -nocomplain -type d ./results/*]
#set_app_var search_path "$search_path . ./scripts $SYN_NTL \
 ${LIB_PATH}/stdcell_hvt/db_nldm \
 ${LIB_PATH}/stdcell_lvt/db_nldm \
 ${LIB_PATH}/stdcell_rvt/db_nldm \
 ${LIB_PATH}/sram/db_nldm"

## Set Library Base Path
set LIB_PATH "/data/synopsys/lib/saed32nm/lib/"

##Load Design, Libraries
set_app_var target_library "saed32hvt_ss0p95v125c.db"
set_app_var link_library "* $target_library"

set SYN_NTL [glob -nocomplain -type d ./results/*]
set_app_var search_path "$search_path . ./scripts $SYN_NTL \
 ${LIB_PATH}/stdcell_hvt/db_nldm"
