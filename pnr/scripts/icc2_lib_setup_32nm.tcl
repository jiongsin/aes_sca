set LIB_PATH "/home/host/libs/saed32nm/lib"
lappend search_path . "${LIB_PATH}/tech/milkyway" "${LIB_PATH}/tech/star_rc" 

if {![file isdirectory MYLIB ]} {
    create_lib MYLIB \
        -technology ${LIB_PATH}/tech/milkyway/saed32nm_1p9m_mw.tf \
        -ref_libs [list \
            "${LIB_PATH}/stdcell_hvt/ndm/saed32hvt.ndm" \
            "${LIB_PATH}/stdcell_lvt/ndm/saed32lvt.ndm" \
            "${LIB_PATH}/stdcell_rvt/ndm/saed32rvt.ndm" \
        ]
}

open_lib MYLIB
set_host_option -max 8
