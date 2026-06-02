###############################################################################
# cvfpu FMA + SoftFloat Co-Simulation Makefile
# 工具链: Verilator + GCC
###############################################################################

# ---- 项目路径 ----
PROJ_DIR  := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
RTL_DIR   := $(PROJ_DIR)/rtl
TB_DIR    := $(PROJ_DIR)/tb
CSRC_DIR  := $(PROJ_DIR)/csrc
LOG_DIR   := $(PROJ_DIR)/logs
TEST_DIR  := $(PROJ_DIR)/tests

# ---- 依赖路径 ----
# cvfpu RTL 在 ../cvfpu/src/
CVFPU_DIR  := $(PROJ_DIR)/../cvfpu
SOFTFLOAT_DIR := $(PROJ_DIR)/../berkeley-softfloat-3

# ---- 工具 ----
CXX       ?= g++
VERILATOR ?= verilator

# ---- SoftFloat 编译选项 ----
SOFTFLOAT_BUILD_DIR := $(SOFTFLOAT_DIR)/build/Linux-x86_64-GCC
SOFTFLOAT_LIB       := $(SOFTFLOAT_BUILD_DIR)/softfloat.a
SOFTFLOAT_INC       := $(SOFTFLOAT_DIR)/source/include

# ---- 仿真参数 ----
SEED      ?= 1
NUM       ?= 1000
TRACE     ?= 0

# ---- Verilator 编译选项 ----
VFLAGS    := --cc --build --exe --trace
VFLAGS    += -Wno-fatal -Wno-UNOPTFLAT -Wno-UNUSEDSIGNAL
VFLAGS    += -I$(CVFPU_DIR)/src
VFLAGS    += -I$(CVFPU_DIR)/src/common_cells/include
VFLAGS    += -I$(CVFPU_DIR)/src/common_cells/src
VFLAGS    += -I$(CVFPU_DIR)/src/fpu_div_sqrt_mvp/hdl
VFLAGS    += -CFLAGS "-I$(SOFTFLOAT_INC) -I$(CSRC_DIR)"

# ---- RTL 源文件（包定义必须最先） ----
RTL_SRCS  := $(CVFPU_DIR)/src/fpnew_pkg.sv
RTL_SRCS  += $(TB_DIR)/dpi_softfloat.sv
RTL_SRCS  += $(RTL_DIR)/fma_dut_wrapper.sv
RTL_SRCS  += $(CVFPU_DIR)/src/fpnew_classifier.sv
RTL_SRCS  += $(CVFPU_DIR)/src/fpnew_rounding.sv
RTL_SRCS  += $(CVFPU_DIR)/src/fpnew_fma.sv
RTL_SRCS  += $(CVFPU_DIR)/src/common_cells/src/cf_math_pkg.sv
RTL_SRCS  += $(CVFPU_DIR)/src/common_cells/src/lzc.sv
RTL_SRCS  += $(CVFPU_DIR)/src/common_cells/src/rr_arb_tree.sv

# ---- C++ / Testbench 源文件 ----
CPP_SRCS  := $(CSRC_DIR)/softfloat_dpi.cpp
CPP_SRCS  += $(CSRC_DIR)/sim_main.cpp
CPP_SRCS  += $(TB_DIR)/tb_fma_cosim.sv

# ---- Top module ----
TOP_MOD   := tb_fma_cosim

# ---- 目标 ----
.PHONY: all softfloat build run wave clean

all: softfloat build run

# ---- 编译 SoftFloat 静态库 ----
softfloat:
	@echo "=== Building SoftFloat ==="
	$(MAKE) -C $(SOFTFLOAT_BUILD_DIR) -j4

# ---- Verilator 编译 ----
build: softfloat
	@echo "=== Building DUT + Testbench ==="
	mkdir -p $(LOG_DIR)
	$(VERILATOR) $(VFLAGS) \
		-top $(TOP_MOD) \
		$(RTL_SRCS) \
		$(CPP_SRCS) \
		$(SOFTFLOAT_LIB) \
		-LDFLAGS "-lstdc++ -lm" \
		-o $(TOP_MOD) \
		--Mdir $(LOG_DIR)/obj_dir

# ---- 运行仿真 ----
run: build
	@echo "=== Running Simulation (SEED=$(SEED) NUM=$(NUM)) ==="
	$(LOG_DIR)/obj_dir/$(TOP_MOD) +SEED=$(SEED) +NUM=$(NUM) +TRACE=$(TRACE)

# ---- 打开波形 ----
wave:
	gtkwave $(LOG_DIR)/fma_cosim.vcd &

# ---- 清理 ----
clean:
	rm -rf $(LOG_DIR)/obj_dir $(LOG_DIR)/*.vcd $(LOG_DIR)/*.log
