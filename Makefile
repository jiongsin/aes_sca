# ========================================================================
# AES Design Automation Environment
# ========================================================================

# Environment Check
ifndef WORKAREA
    $(error ERROR: WORKAREA is not set. Please 'export WORKAREA=/path/to/project' first)
endif

LIBV        ?= 14
VER         ?= opt
VER_CAP      = $(shell echo $(VER) | tr a-z A-Z)
MODE        ?=
DESIGN      ?= aes_operation
ifeq ($(MODE),)
    DESIGN_VER = $(DESIGN)_$(VER)_$(PERIOD_TAG)
else
    DESIGN_VER = $(DESIGN)_$(VER)_MODE$(MODE)_$(PERIOD_TAG)
endif
PERIOD      ?= 10.0
PERIOD_TAG   = $(subst .,p,$(PERIOD))ns
TEST_CNT    ?= 1000
TVLA        ?= normal 
TVLA_CAP     = $(shell echo $(TVLA) | tr a-z A-Z)

# Paths
VERIF_DIR    = $(WORKAREA)/verif
VERIF_TB     = $(VERIF_DIR)/tb/$(DESIGN)_tb.sv
SIM_DIR      = $(VERIF_DIR)/sim
SIMV_DIR     = $(SIM_DIR)/$(DESIGN_VER)

SYN_DIR      = $(WORKAREA)/syn
SYN_TCL      = $(SYN_DIR)/scripts/$(DESIGN).tcl
SYN_LOG      = $(SYN_DIR)/logs/$(DESIGN_VER).log
SYN_RES      = $(SYN_DIR)/results/$(DESIGN_VER)
ifeq ($(TVLA),static)
    SYN_SIM      = $(SYN_RES)/sim_static
    SYN_PSIM_LOG = $(SYN_DIR)/logs/tvla_static.log
else ifeq ($(TVLA),dynamic)
    SYN_SIM      = $(SYN_RES)/sim_dynamic
    SYN_PSIM_LOG = $(SYN_DIR)/logs/tvla_dynamic.log
else 
    SYN_SIM      = $(SYN_RES)/sim
    SYN_PSIM_LOG = $(SYN_DIR)/logs/$(DESIGN_VER).log
endif
SYN_PSIM_TCL = $(SYN_DIR)/scripts/$(DESIGN)_tvla.tcl
SYN_NTL      = $(SYN_RES)/$(DESIGN_VER)_ntl.v

# Tools and Flags
VCS           = vcs
VCS_FLAGS     = -full64 -sverilog -debug_acc+all -kdb -R \
                -Mdir=$(SIM_DIR)/$(DESIGN_VER)/csrc \
                -o $(SIMV_DIR)/simv +vcs+fsdbon \
                +fsdbfile+$(SIMV_DIR)/$(DESIGN_VER).fsdb \
                -l $(SIM_DIR)/$(DESIGN_VER)/compile.log
VCS_TIME      = -timescale=1ns/1ps
VERDI         = verdi 
VERDI_FLAGS   = -ssf $(DESIGN_VER).fsdb -dbdir simv.daidir \
                -logdir ../verdi_work -rcFile ../verdi_work/novas.rc
DC_SHELL      = dc_shell 
DC_FLAGS      = -topo
VCS_SYN_FLAGS = -full64 -sverilog -debug_acc+all -kdb -R \
		/data/synopsys/lib/saed32nm/lib/verilog/saed32nm_hvt.v \
                -Mdir=$(SYN_SIM)/csrc -o $(SYN_SIM)/simv +vcs+fsdbon \
                +fsdbfile+$(SYN_SIM)/$(DESIGN_VER).fsdb \
                -sdf max:$(DESIGN)_tb.dut:$(DESIGN_VER).sdf \
                -l $(SYN_SIM)/compile.log +neg_tchk
		#/home/host/libs/saed32nm/lib/verilog/saed32nm_hvt.v \
                #/home/host/libs/saed32nm/lib/verilog/saed32nm_lvt.v \
                #/home/host/libs/saed32nm/lib/verilog/saed32nm.v \
                #/home/host/libs/saed32nm/lib/verilog/SRAM2RW16x4.v \
                #/data/synopsys/lib/saed32nm/lib/verilog/saed32nm_hvt.v \
                #/data/synopsys/lib/saed32nm/lib/verilog/saed32nm_lvt.v \
                #/data/synopsys/lib/saed32nm/lib/verilog/saed32nm.v \
                #/data/synopsys/lib/saed32nm/lib/verilog/SRAM2RW16x4.v \
                #/data/synopsys/lib/saed14nm/lib/stdcell_hvt/verilog/saed14nm_hvt.v \
                #/data/synopsys/lib/saed14nm/lib/stdcell_rvt/verilog/saed14nm_rvt.v \
                #/data/synopsys/lib/saed14nm/lib/stdcell_lvt/verilog/saed14nm_lvt.v \
                #/data/synopsys/lib/saed14nm/lib/stdcell_slvt/verilog/saed14nm_slvt.v \;
PT_SHELL      = pt_shell

# Targets
.PHONY: all libv sim verdi syn syn.sim syn.verdi syn.psim syn.tvla debug help

all: sim syn syn.sim

libv:
	@cp syn/scripts/dc_lib_setup_$(LIBV)nm.tcl syn/scripts/dc_lib_setup.tcl
	@cp syn/scripts/pt_lib_setup_$(LIBV)nm.tcl syn/scripts/pt_lib_setup.tcl
	@cp pnr/scripts/icc2_lib_setup_$(LIBV)nm.tcl pnr/scripts/icc2_lib_setup.tcl

sim:
	@echo "Starting Simulation for $(DESIGN_VER)..."
	@mkdir -p $(SIM_DIR)
	@rm -rf $(SIM_DIR)/$(DESIGN_VER)
	@mkdir -p $(SIM_DIR)/$(DESIGN_VER)
	@cd $(SIM_DIR) && \
	 $(VCS) $(VCS_FLAGS) $(VCS_TIME) $(ARGS) \
	 -f $(WORKAREA)/rtl/filelist.f \
	 -f $(WORKAREA)/verif/tb/filelist.f \
	 -top $(DESIGN)_tb \
	 +define+AES_$(MODE) +define+AES_$(VER_CAP) +COUNT=$(TEST_CNT)
	@cd $(SIMV_DIR) && \
	fsdb2saif $(DESIGN_VER).fsdb -o $(DESIGN_VER).saif

verdi:
	@echo "Starting Waveform Viewer for $(DESIGN_VER)..."
	@cd $(SIMV_DIR) && \
	 $(VERDI) $(VERDI_FLAGS) 

syn:
	@echo "Starting Synthesis for $(DESIGN_VER)..."
	@mkdir -p $(SYN_DIR)/logs
	@cd $(SYN_DIR) && \
	 export mode=$(MODE) && \
	 export period=$(PERIOD) && \
	 export version=$(VER) && \
	 $(DC_SHELL) $(DC_FLAGS) -f $(SYN_TCL) | tee -i $(SYN_LOG)

syn.sim:
	@echo "Starting Pre Layout Simulation for $(DESIGN_VER)..."
	@rm -rf $(SYN_SIM)
	@mkdir -p $(SYN_SIM)
	@cd $(SYN_RES) && \
	 $(VCS) $(VCS_SYN_FLAGS) $(VCS_TIME) $(ARGS) \
	 $(SYN_NTL) -f $(WORKAREA)/verif/tb/filelist.f \
	 -top $(DESIGN)_tb +COUNT=$(TEST_CNT) \
	 +define+AES_$(MODE) +define+AES_$(VER_CAP) +define+GLS_SIM \
	 +define+TVLA_$(TVLA_CAP)
	 # +DUMP_VCD

syn.verdi:
	@echo "Starting Waveform Viewer for $(DESIGN_VER)..."
	@cd $(SYN_SIM) && \
	 $(VERDI) $(VERDI_FLAGS)

syn.psim:
	@echo "Starting Power Simulation for $(DESIGN_VER)..."
	@cd $(SYN_DIR) && \
	 export DESIGN=$(DESIGN) && \
	 export DESIGN_VER=$(DESIGN_VER) && \
	 export MODE=$(MODE) && \
	 export TVLA=$(TVLA) && \
 	 export PERIOD=$(PERIOD) && \
	 $(PT_SHELL) -f $(SYN_PSIM_TCL) | tee -i $(SYN_PSIM_LOG)

syn.tvla: 
	@echo "Starting Leakage Assessment for $(DESIGN_VER)..."
	$(MAKE) syn.sim TVLA=static
	$(MAKE) syn.psim TVLA=static
	$(MAKE) syn.sim TVLA=dynamic
	$(MAKE) syn.psim TVLA=dynamic

debug:
	@echo "--------------------------------------------------------"
	@echo " Makefile Variable Debug"
	@echo "--------------------------------------------------------"
	@echo "VER:          $(VER)"
	@echo "VER_CAP:      $(VER_CAP)"
	@echo "DESIGN:       $(DESIGN)"
	@echo "DESIGN_VER:   $(DESIGN_VER)"
	@echo "MODE:         $(MODE)"
	@echo "PERIOD:       $(PERIOD) ($(PERIOD_TAG))"
	@echo "TEST_CNT:     $(TEST_CNT)"
	@echo "TVLA:         $(TVLA)"
	@echo ""
	@echo "VERIF_DIR:    $(VERIF_DIR)"
	@echo "VERIF_TB:     $(VERIF_TB)"
	@echo "SIM_DIR:      $(SIM_DIR)"
	@echo "SIMV_DIR:     $(SIMV_DIR)"
	@echo ""
	@echo "SYN_DIR:      $(SYN_DIR)"
	@echo "SYN_TCL:      $(SYN_TCL)"
	@echo "SYN_LOG:      $(SYN_LOG)"
	@echo "SYN_RES:      $(SYN_RES)"
	@echo "SYN_SIM:      $(SYN_SIM)"
	@echo "SYN_PSIM_TCL: $(SYN_PSIM_TCL)"
	@echo "SYN_PSIM_LOG: $(SYN_PSIM_LOG)"
	@echo "SYN_NTL:      $(SYN_NTL)"
	@echo "--------------------------------------------------------"

help:
	@echo "========================================================================"
	@echo "   AES Design Automation Environment - Help Menu"
	@echo "========================================================================"
	@echo " Usage: make [target] [VARIABLES]"
	@echo ""
	@echo " TARGETS:"
	@echo "   sim           : Compile and run simulation (generates FSDB)"
	@echo "   verdi         : Open Verdi GUI to view waveforms"
	@echo "   syn           : Run Design Compiler synthesis"
	@echo "   all           : Run sim verdi syn"
	@echo ""
	@echo " VARIABLES:"
	@echo "   MODE=128      : Set AES mode (Options: 128, 192, 256) [Default: 128]"
	@echo "   PERIOD=10.0   : Set clock period for synthesis [Default: 10.0]"
	@echo "   DESIGN=X  : Override the top module name [Default: aes_operation]"
	@echo ""
	@echo " EXAMPLES:"
	@echo "   make sim MODE=256              -> Run AES-256 simulation"
	@echo "   make syn MODE=192 PERIOD=5.0   -> Synthesize AES-192 at 200MHz"
	@echo "   make verdi                     -> Open Verdi for the last sim run"
	@echo "========================================================================"
