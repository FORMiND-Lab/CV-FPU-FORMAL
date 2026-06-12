###############################################################################
# fp48/Makefile — FP48 FMA + DPI Co-Simulation (Standalone)
#
# Builds and runs the FP48 co-simulation testbench with Verilator.
# The DPI golden model is currently a STUB (returns 0); set SPEC_EN=1
# in tb/tb_fma_cosim_fp48.sv once a real FP48 golden model is ready.
#
# Usage:
#   make              # build + run (default: NUM=100 directed cases only)
#   make build        # build only
#   make run          # run only
#   make run NUM=500  # add 500 random cases after directed
#   make wave         # open VCD waveform
#   make clean        # remove build artifacts
###############################################################################

# ---- Paths (relative to this Makefile) ----
PROJ_DIR       := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
FP48_DIR       := $(PROJ_DIR)
RTL_DIR        := $(PROJ_DIR)/../../rtl/fp48
CVFPU_DIR      := $(PROJ_DIR)/../../third_party/cvfpu/src
COMMON_CELLS   := $(CVFPU_DIR)/common_cells
TB_DIR         := $(FP48_DIR)/tb
CSRC_DIR       := $(FP48_DIR)/csrc
LOG_DIR        := $(FP48_DIR)/logs
TEST_DIR       := $(FP48_DIR)/tests

# ---- Tools ----
CXX        ?= g++
VERILATOR  ?= verilator

# ---- Simulation parameters ----
SEED      ?= 1
NUM       ?= 0     # additional random cases beyond directed (0 = directed only)
TRACE     ?= 0

# ---- Verilator flags ----
VFLAGS    := --cc --build --exe --trace
VFLAGS    += -Wno-fatal -Wno-UNOPTFLAT -Wno-UNUSEDSIGNAL
VFLAGS    += -I$(CVFPU_DIR)
VFLAGS    += -I$(COMMON_CELLS)/include
VFLAGS    += -I$(COMMON_CELLS)/src
VFLAGS    += -I$(RTL_DIR)
VFLAGS    += -CFLAGS "-I$(CSRC_DIR)"

# ---- RTL source files (package must be first) ----
# NOTE: fpnew_pkg_fp48.sv replaces the standard fpnew_pkg.sv for FP48 builds
RTL_SRCS  := $(RTL_DIR)/fpnew_pkg_fp48.sv
RTL_SRCS  += $(TB_DIR)/fmad_dpi_fp48.sv
RTL_SRCS  += $(RTL_DIR)/fma_wrap_fp48.sv
RTL_SRCS  += $(CVFPU_DIR)/fpnew_classifier.sv
RTL_SRCS  += $(CVFPU_DIR)/fpnew_rounding.sv
RTL_SRCS  += $(CVFPU_DIR)/fpnew_fma.sv
RTL_SRCS  += $(COMMON_CELLS)/src/cf_math_pkg.sv
RTL_SRCS  += $(COMMON_CELLS)/src/lzc.sv

# ---- C++ / Testbench sources ----
CPP_SRCS  := $(CSRC_DIR)/fma_dpi_fp48.cpp
CPP_SRCS  += $(CSRC_DIR)/sim_main_fp48.cpp
CPP_SRCS  += $(TB_DIR)/tb_fma_cosim_fp48.sv

# ---- Top module ----
TOP_MOD   := tb_fma_cosim_fp48

# ---- Default log file ----
LOGFILE   ?= $(LOG_DIR)/run.log

# ---- Targets ----
.PHONY: all build run log wave clean

all: build run

# ---- Verilator build ----
build:
	@echo "=== Building FP48 FMA + DPI Co-Simulation ==="
	@echo "RTL: fpnew_pkg_fp48.sv (FP48: E11M36, bias=1023)"
	@echo "DUT: fma_wrap_fp48.sv"
	@echo "DPI: fma_dpi_fp48.cpp (STUB — returns NaN-boxed +0.0)"
	mkdir -p $(LOG_DIR)
	$(VERILATOR) $(VFLAGS) \
		-top $(TOP_MOD) \
		$(RTL_SRCS) \
		$(CPP_SRCS) \
		-LDFLAGS "-lstdc++ -lm" \
		-o $(TOP_MOD) \
		--Mdir $(LOG_DIR)/obj_dir

# ---- Run simulation (stdout only) ----
run: build
	@echo "=== Running FP48 Simulation (SEED=$(SEED) NUM=$(NUM) TRACE=$(TRACE)) ==="
	cd $(FP48_DIR) && $(LOG_DIR)/obj_dir/$(TOP_MOD) +SEED=$(SEED) +NUM=$(NUM) +TRACE=$(TRACE)

# ---- Run + save log to file (use TRACE=1 for full output) ----
log: build
	@echo "=== Running FP48 Simulation -> $(LOGFILE) ==="
	@mkdir -p $(LOG_DIR)
	cd $(FP48_DIR) && $(LOG_DIR)/obj_dir/$(TOP_MOD) +SEED=$(SEED) +NUM=$(NUM) +TRACE=$(TRACE) 2>&1 | tee $(LOGFILE)
	@echo "Log saved to $(LOGFILE)"

# ---- Open waveform ----
wave:
	gtkwave $(LOG_DIR)/fma_cosim_fp48.vcd &

# ---- Clean ----
clean:
	rm -rf $(LOG_DIR)/obj_dir $(LOG_DIR)/*.vcd $(LOG_DIR)/*.log
