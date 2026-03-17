# Environment Check
ifndef WORKAREA
  $(error ERROR: WORKAREA is not set. Please 'export WORKAREA=/path/to/project' first)
endif

DESIGN      ?= aes_operation
MODE        ?= 128
PERIOD      ?= 10.0
PERIOD_TAG   = $(subst .,p,$(PERIOD))ns
TEST_CNT    ?= 1000
TVLA_MODE   ?= DYNAMIC 

# Paths
VERIF_DIR   = $(WORKAREA)/verif
VERIF_TB    = $(VERIF_DIR)/tb/$(DESIGN)_tb.sv
SIM_DIR     = $(WORKAREA)/sim
SIMV_DIR    = $(SIM_DIR)/$(DESIGN)

SYN_DIR     = $(WORKAREA)/syn
SYN_TCL     = $(SYN_DIR)/scripts/$(DESIGN).tcl
SYN_LOG     = $(SYN_DIR)/logs/$(DESIGN).log
SYN_RES     = $(SYN_DIR)/results/$(DESIGN)_MODE${MODE}_${PERIOD_TAG}
SYN_SIM     = $(SYN_RES)/sim
SYN_NTL     = $(SYN_RES)/$(DESIGN)_MODE${MODE}_${PERIOD_TAG}_ntl.v

# Tools and Flags
VCS           = vcs
VCS_FLAGS     = -full64 -sverilog -debug_acc+all -kdb -R \
                -Mdir=$(SIM_DIR)/$(DESIGN)/csrc \
			    -o $(SIMV_DIR)/simv +vcs+fsdbon \
			    +fsdbfile+$(SIMV_DIR)/$(DESIGN).fsdb \
				-l $(SIM_DIR)/$(DESIGN)/compile.log
VCS_TIME      = -timescale=1ns/1ps
VERDI         = verdi 
VERDI_FLAGS   = -ssf $(DESIGN).fsdb -dbdir simv.daidir \
	  			-logdir ../verdi_work -rcFile ../verdi_work/novas.rc
DC_SHELL      = dc_shell 
DC_FLAGS      = -topo
VCS_SYN_FLAGS = -full64 -sverilog -debug_acc+all -kdb -R \
				$(WORKAREA)/libs/saed32nm/lib/verilog/saed32nm.v \
				$(WORKAREA)/libs/saed32nm/lib/verilog/saed32nm_hvt.v \
				$(WORKAREA)/libs/saed32nm/lib/verilog/saed32nm_lvt.v \
				$(WORKAREA)/libs/saed32nm/lib/verilog/SRAM2RW16x4.v \
                -Mdir=$(SYN_SIM)/csrc -o $(SYN_SIM)/simv \
				-sdf max:$(DESIGN)_tb.dut:$(DESIGN)_MODE${MODE}_$(PERIOD_TAG).sdf \
				-l $(SYN_SIM)/compile.log +neg_tchk
# +vcs+fsdbon \
			    +fsdbfile+$(SYN_SIM)/$(DESIGN).fsdb +sdfverbose \
# Targets
.PHONY: all rtl.sim rtl.simg rtl.verdi syn syn.sim help

all: rtl.sim syn syn.sim

rtl.sim:
	@echo "Starting Simulation for $(DESIGN) ..."
	@mkdir -p $(SIM_DIR)
	@rm -rf $(SIM_DIR)/$(DESIGN)
	@mkdir -p $(SIM_DIR)/$(DESIGN)
	@cd $(SIM_DIR) && \
	 $(VCS) $(VCS_FLAGS) $(VCS_TIME) $(ARGS) \
	 -f $(WORKAREA)/rtl/rtl_filelist.f \
	 -f $(WORKAREA)/verif/tb/tb_filelist.f \
	 +define+AES_$(MODE) +COUNT=${TEST_CNT}

rtl.verdi:
	@echo "Starting Waveform Viewer for $(DESIGN) ..."
	@cd $(SIMV_DIR) && \
	 $(VERDI) $(VERDI_FLAGS) 

syn:
	@echo "Starting Synthesis for $(DESIGN) ..."
	@mkdir -p $(SYN_DIR)/logs
	@cd $(SYN_DIR) && \
	 export mode=$(MODE) && \
	 export period=$(PERIOD) && \
	 $(DC_SHELL) $(DC_FLAGS) -f $(SYN_TCL) | tee -i $(SYN_LOG)

syn.sim:
	@echo "Starting Pre-Layout Simulation for $(DESIGN) ..."
	@rm -rf $(SYN_RES)/sim
	@mkdir -p $(SYN_RES)/sim
	@cd $(SYN_RES) && \
	 $(VCS) $(VCS_SYN_FLAGS) $(VCS_TIME) $(ARGS) \
	 ${SYN_NTL} -f $(WORKAREA)/verif/tb/tb_filelist.f \
	 +COUNT=${TEST_CNT} +DUMP_VCD \
	 +define+AES_$(MODE) +define+GLS_SIM +define+TVLA_${TVLA_MODE}

syn.verdi:
	@echo "Starting Waveform Viewer for $(DESIGN) ..."
	@cd $(SYN_SIM) && \
	 $(VERDI) $(VERDI_FLAGS)

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
	@echo "   DESIGN=X  : Override the top module name [Default: aes_operation]"
	@echo ""
	@echo " EXAMPLES:"
	@echo "   make rtl.sim MODE=256          -> Run AES-256 simulation"
	@echo "   make syn MODE=192 PERIOD=5.0   -> Synthesize AES-192 at 200MHz"
	@echo "   make rtl.verdi                 -> Open Verdi for the last sim run"
	@echo "========================================================================"
