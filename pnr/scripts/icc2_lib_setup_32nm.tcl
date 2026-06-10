set LIB_PATH "/data/synopsys/lib/saed32nm/lib/"
# /home/host/libs/saed32nm/lib"

lappend search_path . "${LIB_PATH}/tech/milkyway" "${LIB_PATH}/tech/star_rc" 

if {![file isdirectory MYLIB ]} {
    create_lib MYLIB \
        -technology ${LIB_PATH}/tech/milkyway/saed32nm_1p9m_mw.tf \
        -ref_libs [list \
            "/home/user16/stdcell_hvt_ndm/ndm/saed32hvt.ndm" \
        ]
}

open_lib MYLIB
set_host_option -max 8
