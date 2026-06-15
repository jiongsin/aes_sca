# --- 1. Setup Common Paths ---
set LIB_PATH "/home/host/libs/saed32nm/lib"
set TECH_FILE "${LIB_PATH}/tech/milkyway/saed32nm_1p9m_mw.tf"

# Store the starting directory so we can come back to it
set start_dir [pwd]

# --- 2. Define the Library Flavors ---
set flavors {hvt lvt rvt}

# --- 3. Loop to build each NDM ---
foreach flavor $flavors {

    puts "Building NDM for flavor: $flavor"
    
    set flavor_dir "${LIB_PATH}/stdcell_${flavor}/ndm"
    set ndm_name "saed32${flavor}"
    
    # 1. Create the directory if it does not exist
    file mkdir $flavor_dir
    
    # 2. Go into that directory
    cd $flavor_dir
    
    # 3. Create the workspace using just the simple name
    # This avoids the LMUI-007 Invalid library name error
    create_workspace $ndm_name -tech $TECH_FILE
    
    # 4. Read timing data (.db)
    read_db [list \
        "${LIB_PATH}/stdcell_${flavor}/db_nldm/saed32${flavor}_ff0p95v125c.db" \
        "${LIB_PATH}/stdcell_${flavor}/db_nldm/saed32${flavor}_ss0p95v125c.db" \
    ]
    
    # 5. Read physical data (.lef)
    read_lef "${LIB_PATH}/stdcell_${flavor}/lef/saed32nm_${flavor}_1p9m.lef"
    
    # 6. Check and Save
    catch {check_workspace}
    commit_workspace
    
    puts "Finished building: ${flavor_dir}/${ndm_name}.ndm"
    
    # Return to the starting directory before the next loop iteration
    cd $start_dir
}

puts "All NDMs have been successfully generated."
exit
