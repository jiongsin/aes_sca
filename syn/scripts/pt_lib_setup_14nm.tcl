## Set Library Base Path
set LIB_PATH "/data/synopsys/lib/saed14nm/lib"

## Load Design, Libraries
set_app_var target_library "saed14lvt_ss0p72v125c.db saed14hvt_ss0p72v125c.db saed14rvt_ss0p72v125c.db saed14slvt_ss0p72v125c.db"
set_app_var link_library "* $target_library saed14sram_ss0p72v125c.db saed14io_fc_ss0p72v125c_1p62v.db saed14pll_ss0p72v125c.db"

set SYN_NTL [glob -nocomplain -type d ./results/*]
set_app_var search_path "$search_path . ./scripts $SYN_NTL \
    ${LIB_PATH}/stdcell_hvt/db_nldm \
    ${LIB_PATH}/stdcell_lvt/db_nldm \
    ${LIB_PATH}/stdcell_rvt/db_nldm \
    ${LIB_PATH}/stdcell_slvt/db_nldm \
    ${LIB_PATH}/sram/logic_synth/dual \
    ${LIB_PATH}/io_std/db_nldm \
    ${LIB_PATH}/pll/logic_synth"
