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
SIMV        = $(SIM_DIR)/simv

SYN_DIR     = $(WORKAREA)/syn
SYN_TCL     = $(SYN_DIR)/scripts/$(DESIGN_TOP).tcl
SYN_LOG     = $(SYN_DIR)/logs/$(DESIGN_TOP).log

# =====================================================
# Tools and Flags
# =====================================================
VCS         = vcs
VCS_FLAGS   = -full64 -sverilog -debug_acc+all -kdb -R 
VCS_TIME    = -timescale=1ns/1ps
VERDI       = verdi 
VERDI_FLAGS = -ssf
DC_SHELL    = dc_shell 
DC_FLAGS    = -topo

# =====================================================
# Targets
# =====================================================
.PHONY: all rtl.sim syn clean

all: rtl.sim syn

rtl.sim:
	@echo "Starting Simulation for $(DESIGN_TOP) ..."
	@mkdir -p $(SIM_DIR)
	@mkdir -p $(SIM_DIR)/$(DESIGN_TOP)
	@cd $(SIM_DIR) && \
	 $(VCS) $(VCS_FLAGS) $(VCS_TIME) \
	 -f $(RTL_FILES) $(VERIF_TB) \
	 +define+AES_$(MODE) -o $(SIMV)
	@cd $(SIM_DIR) && ./simv -gui

syn:
	@echo "Starting Synthesis for $(DESIGN_TOP) ..."
	@mkdir -p $(SYN_DIR)/logs
	@cd $(SYN_DIR) && \
	 export mode=$(MODE) && \
	 export period=$(PERIOD) && \
	 $(DC_SHELL) $(DC_FLAGS) -f $(SYN_TCL) | tee -i $(SYN_LOG)

clean:
	rm -rf csrc simv* ucli.key vc_hdrs.h DVEfiles
	rm -rf results/*
	rm -rf $(LOG_DIR)/*
	@echo "Cleanup complete."

# Help command
help:
	@echo "Usage:"
	@echo "  make synth          Run DC Synthesis (default MODE=1)"
	@echo "  make synth MODE=2   Run DC Synthesis with MODE=2"
	@echo "  make sim            Run VCS Simulation"
	@echo "  make all            Run Synthesis and then Simulation"
	@echo "  make clean          Remove logs and temporary tool files"
