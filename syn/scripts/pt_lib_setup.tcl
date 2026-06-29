
# PrimeTime/PrimePower library setup for the 32 nm standard-cell flow.
# Configures the standard-cell target/link libraries and search paths for timing and power analysis.

set LIB_PATH "/data/synopsys/lib/saed32nm/lib/"

set_app_var target_library "saed32hvt_ss0p95v125c.db"
set_app_var link_library "* $target_library"

set SYN_NTL [glob -nocomplain -type d ./results/*]
set_app_var search_path "$search_path . ./scripts $SYN_NTL \
 ${LIB_PATH}/stdcell_hvt/db_nldm"

set_host_options -max_cores 8
