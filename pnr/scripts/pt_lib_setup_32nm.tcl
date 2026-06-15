set LIB_PATH "/data/synopsys/lib/saed32nm/lib/"

##Load Design, Libraries
set_app_var target_library "saed32hvt_ss0p95v125c.db saed32hvt_ff0p95v125c.db"
set_app_var link_library "* $target_library"

set PNR_NTL [glob -nocomplain -type d ./results/*]
set_app_var search_path "$search_path . ./scripts $PNR_NTL \
 ${LIB_PATH}/stdcell_hvt/db_nldm"

set_app_var timing_save_pin_arrival_and_slack true
set_app_var report_default_significant_digits 4

set_host_options -max_cores 8
