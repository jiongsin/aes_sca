# =====================================================
# Environment Check
# =====================================================
ifndef WORKAREA
  $(error ERROR: WORKAREA is not set. Please 'export WORKAREA=/path/to/project' first)
endif

DESIGN_TOP  ?= aes_operation
MODE        ?= 128
PERIOD      ?= 10.0

# =====================================================
# Paths
# =====================================================
RTL_DIR     = $(WORKAREA)/rtl
RTL_FILES   = $(RTL_DIR)/filelist.f

VERIF_DIR   = $(WORKAREA)/verif
VERIF_TB    = $(VERIF_DIR)/tb/$(DESIGN_TOP)_tb.sv
SIM_DIR     = $(WORKAREA)/sim
SIMV_DIR    = $(SIM_DIR)/$(DESIGN_TOP)

SYN_DIR     = $(WORKAREA)/syn
SYN_TCL     = $(SYN_DIR)/scripts/$(DESIGN_TOP).tcl
SYN_LOG     = $(SYN_DIR)/logs/$(DESIGN_TOP).log

# =====================================================
# Tools and Flags
# =====================================================
VCS         = vcs
VCS_FLAGS   = -full64 -sverilog -debug_acc+all -kdb \
              -R -Mdir=$(SIM_DIR)/$(DESIGN_TOP)/csrc \
			  -o $(SIMV_DIR)/simv +vcs+fsdbon \
			  +fsdbfile+$(SIMV_DIR)/$(DESIGN_TOP).fsdb
VCS_TIME    = -timescale=1ns/1ps
VERDI       = verdi 
VERDI_FLAGS = -ssf
DC_SHELL    = dc_shell 
DC_FLAGS    = -topo

# =====================================================
# Targets
# =====================================================
.PHONY: all rtl.sim rtl.verdi syn help

all: rtl.sim rtl.verdi syn

rtl.sim:
	@echo "Starting Simulation for $(DESIGN_TOP) ..."
	@mkdir -p $(SIM_DIR)
	@mkdir -p $(SIM_DIR)/$(DESIGN_TOP)
	@cd $(SIM_DIR) && \
	 $(VCS) $(VCS_FLAGS) $(VCS_TIME) \
	 -f $(RTL_FILES) $(VERIF_TB) \
	 +define+AES_$(MODE) \
	 -l $(SIM_DIR)/$(DESIGN_TOP)/compile.log

rtl.verdi:
	@echo "Starting Waveform Viewer for $(DESIGN_TOP) ..."
	@cd $(SIMV_DIR) && \
	 $(VERDI) -ssf $(DESIGN_TOP).fsdb \
	  -dbdir simv.daidir \
	  -logdir ../verdi_work \
	  -rcFile ../verdi_work/novas.rc 

syn:
	@echo "Starting Synthesis for $(DESIGN_TOP) ..."
	@mkdir -p $(SYN_DIR)/logs
	@cd $(SYN_DIR) && \
	 export mode=$(MODE) && \
	 export period=$(PERIOD) && \
	 $(DC_SHELL) $(DC_FLAGS) -f $(SYN_TCL) | tee -i $(SYN_LOG)

help:
	@echo "========================================================================"
	@echo "   AES Design Automation Environment - Help Menu"
	@echo "========================================================================"
	@echo " Usage: make [target] [VARIABLES]"
	@echo ""
	@echo " TARGETS:"
	@echo "   rtl.sim       : Compile and run simulation (generates FSDB)"
	@echo "   rtl.verdi     : Open Verdi GUI to view waveforms"
	@echo "   syn           : Run Design Compiler synthesis"
	@echo "   all           : Run rtl.sim rtl.verdi syn"
	@echo ""
	@echo " VARIABLES:"
	@echo "   MODE=128      : Set AES mode (Options: 128, 192, 256) [Default: 128]"
	@echo "   PERIOD=10.0   : Set clock period for synthesis [Default: 10.0]"
	@echo "   DESIGN_TOP=X  : Override the top module name [Default: aes_operation]"
	@echo ""
	@echo " EXAMPLES:"
	@echo "   make rtl.sim MODE=256          -> Run AES-256 simulation"
	@echo "   make syn MODE=192 PERIOD=5.0   -> Synthesize AES-192 at 200MHz"
	@echo "   make rtl.verdi                 -> Open Verdi for the last sim run"
	@echo "========================================================================"
