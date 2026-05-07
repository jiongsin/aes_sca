# ========================================================================
# AES Design Automation Environment
# ========================================================================

# Environment Check
ifndef WORKAREA
    $(error ERROR: WORKAREA is not set. Please 'export WORKAREA=/path/to/project' first)
endif

LIBV        ?= 32
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
		/data/synopsys/lib/saed$(LIBV)nm/lib/verilog/saed$(LIBV)nm_hvt.v \
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
.PHONY: all libv sim verdi sim.verdi syn syn.sim syn.verdi syn.sim.verdi syn.psim syn.sim.psim syn.tvla syn.all repeat debug help

all: sim syn.all

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

sim.verdi:
	$(MAKE) sim
	$(MAKE) verdi

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
	 $(VCS) $(VCS_SYN_FLAGS) $(VCS_TIME) $(ARGS) \
	 $(SYN_NTL) -f $(WORKAREA)/verif/tb/filelist.f \
	 -top $(DESIGN)_tb +COUNT=$(TEST_CNT) \
	 +define+AES_$(MODE) +define+AES_$(VER_CAP) +define+GLS_SIM \
	 +define+TVLA_$(TVLA_CAP) +notimingchecks +xprop=tmerge
	 # +DUMP_VCD

syn.verdi:
	@echo "Starting Waveform Viewer for $(DESIGN_VER)..."
	@cd $(SYN_SIM) && \
	 $(VERDI) $(VERDI_FLAGS)

syn.sim.verdi:
	@echo "Starting Pre-Layout Simulation with Waveform Viewer for $(DESIGN_VER)..."
	$(MAKE) syn.sim
	$(MAKE) syn.verdi

syn.psim:
	@echo "Starting Power Simulation for $(DESIGN_VER)..."
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

syn.sim.psim:
	@echo "Starting Pre-Layout Simulation with Power Simulation for $(DESIGN_VER)..."
	$(MAKE) syn.sim
	$(MAKE) syn.psim

syn.tvla:
	@echo "Starting Leakage Assessment for $(DESIGN_VER)..."
	@export DESIGN_VER=$(DESIGN_VER) && \
	 cd $(SYN_DIR)/scripts && \
	 if [ -d venv ]; then source venv/bin/activate; fi && \
	 python3 $(DESIGN)_tvla.py

syn.sim.psim.tvla:
	@echo "Starting TVLA Test with Power Simulation for $(DESIGN_VER)..."
	$(MAKE) syn.sim.psim TVLA=static
	$(MAKE) syn.sim.psim TVLA=dynamic
	$(MAKE) syn.tvla

syn.all: 
	@echo "Starting TVLA Test from Synthesis for $(DESIGN_VER)..."
	$(MAKE) syn
	$(MAKE) syn.sim.psim.tvla

repeat:
	@for i in $$(seq 1 $(N)); do \
		echo "Run $$i"; \
		$(MAKE) $(CMD); \
	done

debug:
	@echo "========================================================"
	@echo " Makefile Variable Debug"
	@echo "========================================================"
	@echo " DESIGN:       $(DESIGN)"
	@echo " VERSION:      $(VER) ($(VER_CAP))"
	@echo " MODE:         $(MODE)"
	@echo " PERIOD:       $(PERIOD) ($(PERIOD_TAG))"
	@echo " TEST COUNT:   $(TEST_CNT)"
	@echo " TECHNOLOGY:   $(LIBV)nm"
	@echo " TVLA MODE:    $(TVLA) ($(TVLA_CAP))"
	@echo ""
	@echo " DIRECTORIES:"
	@echo " WORKAREA:     $(WORKAREA)"
	@echo " SIMV DIR:     $(SIMV_DIR)"
	@echo " SYN RESULTS:  $(SYN_RES)"
	@echo " SYN SIM DIR:  $(SYN_SIM)"
	@echo ""
	@echo " DERIVED PATHS:"
	@echo " DESIGN VER:   $(DESIGN_VER)"
	@echo " SYN LOG:      $(SYN_LOG)"
	@echo " PSIM LOG:     $(SYN_PSIM_LOG)"
	@echo "========================================================"

help:
	@echo "========================================================================"
	@echo " AES Design Automation Environment Help"
	@echo "========================================================================"
	@echo " USAGE: make [target] [VARIABLES]"
	@echo ""
	@echo " SETUP"
	@echo "  libv           : Copy library setup files (LIBV=14 or 32)"
	@echo ""
	@echo " RTL FLOW"
	@echo "  sim            : Run RTL simulation"
	@echo "  verdi          : Open Verdi for RTL"
	@echo "  sim.verdi      : Run simulation then open Verdi"
	@echo ""
	@echo " SYNTHESIS FLOW"
	@echo "  syn            : Run Design Compiler synthesis"
	@echo "  syn.sim        : Run Gate Level Simulation"
	@echo "  syn.verdi      : Open Verdi for Gate Level"
	@echo "  syn.sim.verdi  : Run GLS then open Verdi"
	@echo ""
	@echo " POWER AND TVLA"
	@echo "  syn.psim       : Run PrimeTime PX power analysis"
	@echo "  syn.sim.psim   : Run GLS then power analysis"
	@echo "  syn.tvla       : Run Python Leakage Assessment"
	@echo "  syn.all        : Run full flow (Syn, Static, Dynamic, TVLA)"
	@echo ""
	@echo " TOOLS"
	@echo "  debug          : Print current variables"
	@echo "  help           : Show this menu"
	@echo ""
	@echo " VARIABLES"
	@echo "  MODE=128|192|256   : AES key size"
	@echo "  PERIOD=value       : Clock period in ns"
	@echo "  LIBV=14|32         : Tech node"
	@echo "  TVLA=static|dynamic: Power analysis type"
	@echo "========================================================================"
