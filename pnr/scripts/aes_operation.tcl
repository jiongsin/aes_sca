source ./scripts/icc2_lib_setup.tcl

set mode 128
set version opt
set period 10p0
set rtl_top "aes_operation_${version}"
set run_name "${rtl_top}_MODE${mode}_${period}ns"

# Load the gate level netlist and link the blocks
read_verilog ../syn/results/${run_name}/${run_name}_ntl.v
link_block
current_block

# Load technology files for parasitic extraction
read_parasitic_tech -layermap saed32nm_tf_itf_tluplus.map \
    -tlup saed32nm_1p9m_Cmax.tluplus \
    -name maxTLU

read_parasitic_tech -layermap saed32nm_tf_itf_tluplus.map \
    -tlup saed32nm_1p9m_Cmin.tluplus \
    -name minTLU

# Set the calculation rules for timing
set_parasitic_parameters -early_spec maxTLU -late_spec maxTLU
read_sdc ../syn/results/${run_name}/${run_name}.sdc

# Define how cells are placed and oriented
set_attribute [get_site_defs unit] symmetry Y
set_attribute [get_site_defs unit] is_default true

# Define which metal layers go horizontal or vertical
set_attribute [get_layers {M1 M3 M5 M7 M9}] routing_direction horizontal
set_attribute [get_layers {M2 M4 M6 M8}] routing_direction vertical

# Set the starting position for routing tracks
set_attribute [get_layers {M1}] track_offset 0.03
set_attribute [get_layers {M2}] track_offset 0.04

# Limit the layers available for general routing
set_ignored_layers -max_routing_layer M6 -min_routing_layer M1

# Set the chip shape and size
initialize_floorplan -side_ratio {1 1} -core_offset {15} -core_utilization 0.95
shape_blocks

# Configure how cells and macros are placed
set_app_options -name place.coarse.fix_hard_macros -value false
set_app_options -name plan.place.auto_create_blockages -value auto
set_app_options -name place.legalize.enable_prerouted_net_check -value true

# Place the cells and the pins
create_placement -floorplan
set_block_pin_constraints -self -allowed_layers {M3 M4 M5 M6}
place_pins -self

# Clean any old power settings
remove_pg_strategies -all
remove_pg_patterns -all

# Create the main power and ground nets
create_net -power VDD
create_net -ground VSS

# Connect the power pins of the cells to the nets
connect_pg_net -net VDD [get_pins -hierarchical */VDD]
connect_pg_net -net VSS [get_pins -hierarchical */VSS]

# Define the rules for connections between metal layers
set_pg_via_master_rule -via_array_dimension {2 1} pgvia_2x1

# Define the shapes for the power rings and meshes
create_pg_ring_pattern ring_M5_M6 -horizontal_layer M5 -vertical_layer M6 \
    -horizontal_width {3} -vertical_width {3} -horizontal_spacing {2} -vertical_spacing {2}

create_pg_mesh_pattern M2_mesh \
    -layers {{{vertical_layer : M2} {width : 0.25} {pitch : 25} {trim : true}}}

create_pg_mesh_pattern M7_M8_mesh -layers { \
    {{horizontal_layer : M7} {width : 4} {spacing : interleaving} {offset : 20} {pitch : 35} {trim : true}} \
    {{vertical_layer : M8} {width : 4} {spacing : interleaving} {offset : 20} {pitch : 35} {trim : true}} \
}

create_pg_std_cell_conn_pattern P_std_cell_rail -layers {M1}

# Map the patterns to specific areas of the chip
set_pg_strategy core_pgring -core -pattern {{name : ring_M5_M6}{nets : {VDD VSS}}{offset : {2 2}}}

set_pg_strategy S_upper_mesh -core -pattern {{name : M7_M8_mesh}{nets : {VDD VSS}}} \
    -extension {{{stop : design_boundary_and_generate_pin}}}

set_pg_strategy S_m2_straps -core -pattern {{name : M2_mesh}{nets : {VDD VSS}}} \
    -extension {{stop : design_boundary_and_generate_pin}}

set_pg_strategy S_std_rails -core -pattern {{name : P_std_cell_rail}{nets : {VDD VSS}}} \
    -extension {{{stop : core_boundary}}}

# Define how different power layers connect to each other
set_pg_strategy_via_rule R_upper_to_m2 -via_rule { \
    {{{strategies : {S_m2_straps}}{layers : {M2}}}} \
    {{{strategies : {S_upper_mesh}}{layers : {M7}}}{via_master : default}} \
}

set_pg_strategy_via_rule R_m2_to_rails -via_rule { \
    {{{strategies : {S_std_rails}}{layers : {M1}}}} \
    {{{strategies : {S_m2_straps}}{layers : {M2}}}{via_master : VIA12SQ_C}} \
}

# Run the command to build the entire power network
compile_pg -strategies {core_pgring S_upper_mesh S_m2_straps S_std_rails} \
            -via_rule {R_upper_to_m2 R_m2_to_rails}

# Fill empty spaces and ensure all cells are in legal spots
create_stdcell_fillers -lib_cells {saed32hvt/SHFILL*}
connect_pg_net -automatic
legalize_placement

# Check for any power grid errors or breaks
check_pg_connectivity
check_pg_drc
check_pg_drc -ignore_std_cells


report_qor -summary

report_ideal_network -scenarios [all_scenarios]
report_ignored_layers
report_host_options
report_design -summary
report_utilization
check_design -checks pre_placement_stage
check_design -checks physical_constraints

report_app_options place.coarse.auto_density_control
set_app_options -name place.coarse.enhanced_auto_density_control -value true
set_app_options -name place.coarse.continue_on_missing_scandef -value true
set_app_options -name opt.dft.optimize_scan_chain -value false

place_opt
route_global -effort_level low -congestion_map_only true

# exit
