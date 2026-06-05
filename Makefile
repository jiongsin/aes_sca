# ========================================================================
# AES Design Automation Environment
# ========================================================================

# Environment Check
ifndef WORKAREA
    $(error ERROR: WORKAREA is not set. Please 'export WORKAREA=/path/to/project' first)
endif

LIBV        ?= 32 # 14
DESIGN      ?=
DESIGN_CAP   = $(shell echo $(DESIGN) | tr a-z A-Z)
VER         ?=
VER_CAP      = $(shell echo $(VER) | tr a-z A-Z)
MODE        ?=
ifeq ($(MODE),)
    ifeq ($(VER),)
        DESIGN_VER = $(DESIGN)_$(PERIOD_TAG)
    else
        DESIGN_VER = $(DESIGN)_$(VER)_$(PERIOD_TAG)
    endif
else ifeq ($(VER),)
    DESIGN_VER = $(DESIGN)_MODE$(MODE)_$(PERIOD_TAG)
else
    DESIGN_VER = $(DESIGN)_$(VER)_MODE$(MODE)_$(PERIOD_TAG)
endif
PERIOD      ?= 10.0
PERIOD_TAG   = $(subst .,p,$(PERIOD))ns
TEST_CNT    ?= 100
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
SYN_TCL      = $(SYN_DIR)/scripts/$(DESIGN)_syn.tcl
SYN_LOG      = $(SYN_DIR)/logs/$(DESIGN_VER).log
SYN_RES      = $(SYN_DIR)/results/$(DESIGN_VER)

PNR_DIR      = $(WORKAREA)/pnr
PNR_TCL      = $(PNR_DIR)/scripts/$(DESIGN)_pnr.tcl
PNR_LOG      = $(PNR_DIR)/logs/$(DESIGN_VER)_pnr.log
PNR_RES      = $(PNR_DIR)/results/$(DESIGN_VER)

ifeq ($(TVLA),static)
    SYN_SIM      = $(SYN_RES)/sim_static
    SYN_PSIM_LOG = $(SYN_DIR)/logs/$(DESIGN_VER)_tvla_static.log
    PNR_SIM      = $(PNR_RES)/sim_static
    PNR_PSIM_LOG = $(PNR_DIR)/logs/$(DESIGN_VER)_tvla_static.log
else ifeq ($(TVLA),dynamic)
    SYN_SIM      = $(SYN_RES)/sim_dynamic
    SYN_PSIM_LOG = $(SYN_DIR)/logs/$(DESIGN_VER)_tvla_dynamic.log
    PNR_SIM      = $(PNR_RES)/sim_dynamic
    PNR_PSIM_LOG = $(PNR_DIR)/logs/$(DESIGN_VER)_tvla_dynamic.log
else 
    SYN_SIM      = $(SYN_RES)/sim
    SYN_PSIM_LOG = $(SYN_DIR)/logs/$(DESIGN_VER).log
    PNR_SIM      = $(PNR_RES)/sim
    PNR_PSIM_LOG = $(PNR_DIR)/logs/$(DESIGN_VER)_tvla.log
endif
SYN_PSIM_TCL = $(SYN_DIR)/scripts/$(DESIGN)_tvla.tcl
SYN_NTL      = $(SYN_RES)/$(DESIGN_VER)_ntl.v
PNR_PSIM_TCL = $(PNR_DIR)/scripts/$(DESIGN)_tvla.tcl
PNR_NTL      = $(PNR_RES)/$(DESIGN_VER).v

PNR_STA_TCL  = $(PNR_DIR)/scripts/$(DESIGN)_sta.tcl
PNR_STA_LOG  = $(PNR_DIR)/logs/$(DESIGN_VER)_sta.log

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
ICC2_SHELL    = icc2_shell
VCS_PNR_FLAGS = -full64 -sverilog -debug_acc+all -kdb -R \
		/data/synopsys/lib/saed32nm/lib/verilog/saed32nm_hvt.v \
                -Mdir=$(PNR_SIM)/csrc -o $(PNR_SIM)/simv +vcs+fsdbon \
                +fsdbfile+$(PNR_SIM)/$(DESIGN_VER).fsdb \
                -sdf max:$(DESIGN)_tb.dut:$(DESIGN_VER)_func_slow_max.sdf \
                -l $(PNR_SIM)/compile.log
PT_SHELL      = pt_shell

# Targets
.PHONY: all libv sim verdi syn syn.sim syn.verdi syn.psim syn.tvla syn.all syn.alp pnr pnr.sim pnr.verdi pnr.psim pnr.tvla pnr.all pnr.alp sta repeat debug help

all: sim syn syn.sim pnr pnr.alp sta

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
	 +define+$(DESIGN_CAP) +define+AES_$(MODE) +define+AES_$(VER_CAP) +COUNT=$(TEST_CNT)
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
	@cd $(SYN_DIR)/scripts && ppa_report.py

syn.sim:
	@echo "Starting Pre-Layout Simulation for $(DESIGN_VER)..."
	@rm -rf $(SYN_SIM)
	@mkdir -p $(SYN_SIM)
	@cd $(SYN_RES) && \
	 $(VCS) $(VCS_SYN_FLAGS) $(VCS_TIME) $(ARGS) +vcs+lic+wait \
	 $(SYN_NTL) -f $(WORKAREA)/verif/tb/filelist.f \
	 -top $(DESIGN)_tb +COUNT=$(TEST_CNT) \
	 +define+$(DESIGN_CAP) +define+AES_$(MODE) +define+AES_$(VER_CAP) +define+GLS_SIM \
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
	@rm -rf $(SYN_RES)/tvla_$(TVLA)*
	@cd $(SYN_DIR) && \
	 export DESIGN=$(DESIGN) && \
	 export DESIGN_VER=$(DESIGN_VER) && \
	 export MODE=$(MODE) && \
	 export TVLA=$(TVLA) && \
 	 export PERIOD=$(PERIOD) && \
	 $(PT_SHELL) -f $(SYN_PSIM_TCL) | tee -i $(SYN_PSIM_LOG)

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

pnr:
	@echo "Starting Place and Route for $(DESIGN_VER)..."
	@mkdir -p $(PNR_DIR)/logs
	@cd $(PNR_DIR) && \
	 export DESIGN=$(DESIGN) && \
	 export MODE=$(MODE) && \
	 export VER=$(VER) && \
	 export DESIGN_VER=$(DESIGN_VER) && \
	 $(ICC2_SHELL) $(ARGS) -f $(PNR_TCL) | tee -i $(PNR_LOG)

pnr.sim:
	@echo "Starting Post-Layout Simulation for $(DESIGN_VER)..."
	@rm -rf $(PNR_SIM)
	@mkdir -p $(PNR_SIM)
	@cd $(PNR_RES) && \
	 $(VCS) $(VCS_PNR_FLAGS) $(VCS_TIME) $(ARGS) +vcs+lic+wait \
	 $(PNR_NTL) -f $(WORKAREA)/verif/tb/filelist.f \
	 -top $(DESIGN)_tb +COUNT=$(TEST_CNT) \
	 +define+$(DESIGN_CAP) +define+AES_$(MODE) +define+AES_$(VER_CAP) +define+GLS_SIM \
	 +define+TVLA_$(TVLA_CAP)

pnr.verdi:
	@echo "Starting Waveform Viewer for $(DESIGN_VER)..."
	@cd $(PNR_SIM) && \
	 $(VERDI) $(VERDI_FLAGS)

pnr.psim:
	@echo "Starting Power Simulation for $(DESIGN_VER)..."
	@rm -rf $(PNR_RES)/tvla_$(TVLA)*
	@cd $(PNR_DIR) && \
	 export DESIGN=$(DESIGN) && \
	 export DESIGN_VER=$(DESIGN_VER) && \
	 export MODE=$(MODE) && \
	 export TVLA=$(TVLA) && \
 	 export PERIOD=$(PERIOD) && \
	 $(PT_SHELL) -f $(PNR_PSIM_TCL) | tee -i $(PNR_PSIM_LOG)

pnr.tvla:
	@echo "Starting Leakage Assessment for $(DESIGN_VER)..."
	@export VER=$(VER) && \
	 export MODE=$(MODE) && \
	 export DESIGN_VER=$(DESIGN_VER) && \
	 cd $(PNR_DIR)/scripts && \
	 if [ -d venv ]; then source venv/bin/activate; fi && \
	 python3 $(DESIGN)_tvla.py

pnr.all:
	@echo "Starting TVLA Test with Power Simulation for $(DESIGN_VER)..."
	$(MAKE) pnr.sim pnr.psim TVLA=static
	$(MAKE) pnr.sim pnr.psim TVLA=dynamic
	$(MAKE) pnr.tvla

pnr.alp:
	@echo "Starting TVLA Test with Power Simulation in Parallel for $(DESIGN_VER)..."
	@( \
		gnome-terminal --wait --title="Static Analysis for $(DESIGN_VER)" -- bash -c "$(MAKE) pnr.sim pnr.psim TVLA=static" & \
		gnome-terminal --wait --title="Dynamic Analysis for $(DESIGN_VER)" -- bash -c "$(MAKE) pnr.sim pnr.psim TVLA=dynamic" & \
		wait \
	)
	@$(MAKE) pnr.tvla

sta:
	@echo "Starting Static Timing Analysis for $(DESIGN_VER)..."
	@mkdir -p $(PNR_DIR)/logs
	@cd $(PNR_DIR) && \
	 export DESIGN=$(DESIGN) && \
	 export MODE=$(MODE) && \
	 export VER=$(VER) && \
	 export DESIGN_VER=$(DESIGN_VER) && \
	 $(PT_SHELL) -f $(PNR_STA_TCL) | tee -i $(PNR_STA_LOG)

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
