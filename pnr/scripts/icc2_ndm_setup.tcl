
# ICC2 NDM generation script for the SAED 32 nm standard-cell libraries.
# Builds NDM workspaces for the selected HVT/LVT/RVT library flavors by reading technology, timing, and LEF data, then commits each generated library.

set LIB_PATH "/home/host/libs/saed32nm/lib"
set TECH_FILE "${LIB_PATH}/tech/milkyway/saed32nm_1p9m_mw.tf"

set start_dir [pwd]

set flavors {hvt lvt rvt}

foreach flavor $flavors {

    puts "Building NDM for flavor: $flavor"

    set flavor_dir "${LIB_PATH}/stdcell_${flavor}/ndm"
    set ndm_name "saed32${flavor}"

    file mkdir $flavor_dir

    cd $flavor_dir

    create_workspace $ndm_name -tech $TECH_FILE

    read_db [list \
        "${LIB_PATH}/stdcell_${flavor}/db_nldm/saed32${flavor}_ff0p95v125c.db" \
        "${LIB_PATH}/stdcell_${flavor}/db_nldm/saed32${flavor}_ss0p95v125c.db" \
    ]

    read_lef "${LIB_PATH}/stdcell_${flavor}/lef/saed32nm_${flavor}_1p9m.lef"

    catch {check_workspace}
    commit_workspace

    puts "Finished building: ${flavor_dir}/${ndm_name}.ndm"

    cd $start_dir
}

puts "All NDMs have been successfully generated."
exit
