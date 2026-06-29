# Top-level AES PNR flow launcher.
# Runs the floorplan/place, CTS, route, post-route debug, and export scripts in sequence, then exits the ICC2 session.

source ./scripts/aes_floorplan_place.tcl
source ./scripts/aes_cts.tcl
source ./scripts/aes_route.tcl
source ./scripts/aes_post_route_debug.tcl
source ./scripts/aes_export.tcl
exit
