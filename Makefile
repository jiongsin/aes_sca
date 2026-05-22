# ========================================================================
# AES Design Automation Environment
# ========================================================================

# Environment Check
ifndef WORKAREA
    $(error ERROR: WORKAREA is not set. Please 'export WORKAREA=/path/to/project' first)
endif

LIBV        ?= 32 # 14
DESIGN      ?= aes_operation
VER         ?= sca
VER_CAP      = $(shell echo $(VER) | tr a-z A-Z)
MODE        ?= 128
ifeq ($(MODE),)
    DESIGN_VER = $(DESIGN)_$(VER)_$(PERIOD_TAG)
else
    DESIGN_VER = $(DESIGN)_$(VER)_MODE$(MODE)_$(PERIOD_TAG)
endif
PERIOD      ?= 10.0
PERIOD_TAG   = $(subst .,p,$(PERIOD))ns
TEST_CNT    ?= 1000
TVLA        ?= none 
TVLA_CAP     = $(shell echo $(TVLA) | tr a-z A-Z)
N           ?= 10
CMD         ?=

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
    SYN_PSIM_LOG = $(SYN_DIR)/logs/$(DESIGN_VER)_tvla_static.log
else ifeq ($(TVLA),dynamic)
    SYN_SIM      = $(SYN_RES)/sim_dynamic
    SYN_PSIM_LOG = $(SYN_DIR)/logs/$(DESIGN_VER)_tvla_dynamic.log
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
                -l $(SYN_SIM)/compile.log
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
.PHONY: all libv sim verdi saif syn syn.sim syn.verdi syn.psim syn.tvla syn.all syn.alp repeat debug help

all: sim saif syn syn.alp

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
	 $(VCS) $(VCS_FLAGS) $(VCS_TIME) $(ARGS) +vcs+lic+wait \
	 -f $(WORKAREA)/rtl/filelist.f \
	 -f $(WORKAREA)/verif/tb/filelist.f \
	 -top $(DESIGN)_tb \
	 +define+AES_$(MODE) +define+AES_$(VER_CAP) +COUNT=$(TEST_CNT)

verdi:
	@echo "Starting Waveform Viewer for $(DESIGN_VER)..."
	@cd $(SIMV_DIR) && \
	 $(VERDI) $(VERDI_FLAGS) 

saif:
	@echo "Starting fsdb2saif Conversion for $(DESIGN_VER)..."
	@cd $(SIMV_DIR) && \
	fsdb2saif $(DESIGN_VER).fsdb -o $(DESIGN_VER).saif

syn:
	@echo "Starting Synthesis for $(DESIGN_VER)..."
	@mkdir -p $(SYN_DIR)/logs
	@cd $(SYN_DIR) && \
	 export mode=$(MODE) && \
	 export period=$(PERIOD) && \
	 export version=$(VER) && \
	 $(DC_SHELL) $(DC_FLAGS) -f $(SYN_TCL) | tee -i $(SYN_LOG)
	@cd $(SYN_DIR)/scripts && ppa_report.py

syn.sim:
	@echo "Starting Pre-Layout Simulation for $(DESIGN_VER)..."
	@rm -rf $(SYN_SIM)
	@mkdir -p $(SYN_SIM)
	@cd $(SYN_RES) && \
	 $(VCS) $(VCS_SYN_FLAGS) $(VCS_TIME) $(ARGS) +vcs+lic+wait \
	 $(SYN_NTL) -f $(WORKAREA)/verif/tb/filelist.f \
	 -top $(DESIGN)_tb +COUNT=$(TEST_CNT) \
	 +define+AES_$(MODE) +define+AES_$(VER_CAP) +define+GLS_SIM \
	 +define+TVLA_$(TVLA_CAP) +neg_tchk -negdelay 
	 # +notimingcheck +sdf_verbose +pulse_r/0 +pulse_e/0
	 # +nospecify +delay_mode_zero +xprop=tmerge
	 # +DUMP_VCD

syn.verdi:
	@echo "Starting Waveform Viewer for $(DESIGN_VER)..."
	@cd $(SYN_SIM) && \
	 $(VERDI) $(VERDI_FLAGS)

syn.psim:
	@echo "Starting Power Simulation for $(DESIGN_VER)..."
	@rm -rf $(SYN_RES)/tvla_*
	@cd $(SYN_DIR) && \
	 export DESIGN=$(DESIGN) && \
	 export DESIGN_VER=$(DESIGN_VER) && \
	 export MODE=$(MODE) && \
	 export TVLA=$(TVLA) && \
 	 export PERIOD=$(PERIOD) && \
	 $(PT_SHELL) -f $(SYN_PSIM_TCL) | tee -i $(SYN_PSIM_LOG)
	@if [ -f $(SYN_RES)/tvla_$(TVLA)/tvla_traces.out ]; then \
	 cd $(SYN_DIR) && \
	 split -n 16 -d $(SYN_RES)/tvla_$(TVLA)/tvla_traces.out $(SYN_RES)/tvla_$(TVLA)/chunk_ && \
	 rm $(SYN_RES)/tvla_$(TVLA)/tvla_traces.out; \
	 fi

syn.tvla:
	@echo "Starting Leakage Assessment for $(DESIGN_VER)..."
	@export VER=$(VER) && \
	 export MODE=$(MODE) && \
	 export DESIGN_VER=$(DESIGN_VER) && \
	 cd $(SYN_DIR)/scripts && \
	 if [ -d venv ]; then source venv/bin/activate; fi && \
	 python3 $(DESIGN)_tvla.py

syn.all:
	@echo "Starting TVLA Test with Power Simulation for $(DESIGN_VER)..."
	$(MAKE) syn.sim syn.psim TVLA=static
	$(MAKE) syn.sim syn.psim TVLA=dynamic
	$(MAKE) syn.tvla

syn.alp:
	@echo "Starting TVLA Test with Power Simulation in Parallel for $(DESIGN_VER)..."
	@( \
		gnome-terminal --wait --title="Static Analysis for $(DESIGN_VER)" -- bash -c "$(MAKE) syn.sim syn.psim TVLA=static" & \
		gnome-terminal --wait --title="Dynamic Analysis for $(DESIGN_VER)" -- bash -c "$(MAKE) syn.sim syn.psim TVLA=dynamic" & \
		wait \
	)
	@$(MAKE) syn.tvla

repeat:
	@for i in $$(seq 1 $(N)); do \
		echo "Run $$i"; \
		$(MAKE) $(CMD); \
	done

debug:
	@echo "========================================================"
	@echo " Environment Status"
	@echo "========================================================"
	@echo " WORKAREA:     $(WORKAREA)"
	@echo " DESIGN:       $(DESIGN)"
	@echo " VERSION:      $(VER) ($(VER_CAP))"
	@echo " MODE:         $(MODE)"
	@echo " PERIOD:       $(PERIOD) ($(PERIOD_TAG))"
	@echo " TECHNOLOGY:   $(LIBV)nm"
	@echo ""
	@echo " Formatted Strings"
	@echo " DESIGN_VER:   $(DESIGN_VER)"
	@echo " TVLA_MODE:    $(TVLA) ($(TVLA_CAP))"
	@echo " TEST COUNT:   $(TEST_CNT)"
	@echo ""
	@echo " Active Paths"
	@echo " SIMV DIR:     $(SIMV_DIR)"
	@echo " SYN RESULTS:  $(SYN_RES)"
	@echo " SYN SIM DIR:  $(SYN_SIM)"
	@echo " SYN LOG:      $(SYN_LOG)"
	@echo " PSIM LOG:     $(SYN_PSIM_LOG)"
	@echo "========================================================"

help:
	@echo "========================================================================"
	@echo " AES Design Automation Environment Help"
	@echo "========================================================================"
	@echo " Usage: make [target] [VARIABLES]"
	@echo ""
	@echo " Setup"
	@echo "  libv           : Copy library setup files"
	@echo ""
	@echo " RTL Simulation"
	@echo "  sim            : Run RTL simulation"
	@echo "  verdi          : Open Verdi for waveforms"
	@echo ""
	@echo " Synthesis Flow"
	@echo "  syn            : Run Design Compiler synthesis"
	@echo "  syn.sim        : Run Gate Level Simulation"
	@echo "  syn.verdi      : Open Verdi for Gate Level"
	@echo ""
	@echo " Power and Leakage Analysis"
	@echo "  syn.psim       : Run PrimeTime PX power analysis"
	@echo "  syn.sim.psim   : Run GLS then power analysis"
	@echo "  syn.tvla       : Run Python Leakage Assessment"
	@echo "  syn.sim.psim.tvla : Run static and dynamic TVLA tests"
	@echo "  syn.all        : Run full flow from synthesis to TVLA"
	@echo ""
	@echo " Management"
	@echo "  debug          : Print all environment variables"
	@echo "  help           : Show this menu"
	@echo ""
	@echo " Configuration Variables"
	@echo "  LIBV           : Set tech node like 32 (default) or 14"
	@echo "  DESIGN         : Set design like aes_operation (default)"
	@echo "  VER            : Set version of design like opt (default)"
	@echo "  MODE           : Set AES key size like 128 (default), 192 or 256"
	@echo "  PERIOD         : Set clock period in nanoseconds like 10.0 (default)"
	@echo "  TEST_CNT       : Set number of encryption like 1000 (default)"
	@echo "  TVLA           : Set power mode to none (default), static or dynamic"
	@echo "  N              : Set number of commands to be repeated like 10 (default)"
	@echo "  CMD            : Set commands to be repeated like \"sim DESIGN=aes_operation VER=opt MODE=128\""
	@echo " Frequent Command "
	@echo "========================================================================"
