###############################################################################
# cvfpu FMA + SoftFloat Co-Simulation Makefile
# 工具链: Verilator + GCC
# 所有第三方依赖已内置到 third_party/ 目录
# SoftFloat 从源码编译（非预编译 .a）
###############################################################################

# ---- 项目路径 ----
PROJ_DIR      := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
RTL_DIR       := $(PROJ_DIR)/rtl
TB_DIR        := $(PROJ_DIR)/sim/tb
CSRC_DIR      := $(PROJ_DIR)/sim/csrc
LOG_DIR       := $(PROJ_DIR)/sim/logs
TEST_DIR      := $(PROJ_DIR)/sim/tests
FORMAL_DIR    := $(PROJ_DIR)/formal
THIRD_PARTY   := $(PROJ_DIR)/third_party

# ---- 第三方依赖路径 ----
CVFPU_DIR           := $(THIRD_PARTY)/cvfpu
COMMON_CELLS        := $(CVFPU_DIR)/common_cells
SOFTFLOAT_DIR       := $(THIRD_PARTY)/softfloat
SOFTFLOAT_INC       := $(SOFTFLOAT_DIR)/include
SOFTFLOAT_SRC       := $(SOFTFLOAT_DIR)/source
SOFTFLOAT_RISCV     := $(SOFTFLOAT_SRC)/RISCV
SOFTFLOAT_BUILD_DIR := $(SOFTFLOAT_DIR)/build
SOFTFLOAT_LIB       := $(SOFTFLOAT_BUILD_DIR)/libsoftfloat.a

# ---- 工具 ----
CC         ?= gcc
CXX        ?= g++
VERILATOR  ?= verilator

# ---- 仿真参数 ----
SEED      ?= 1
NUM       ?= 1000
TRACE     ?= 0

# ---- SoftFloat 源文件 (仅 FP32 FMA 需要的) ----
SOFTFLOAT_COMMON_SRCS := \
	$(SOFTFLOAT_SRC)/f32_mulAdd.c \
	$(SOFTFLOAT_SRC)/s_mulAddF32.c \
	$(SOFTFLOAT_SRC)/s_roundPackToF32.c \
	$(SOFTFLOAT_SRC)/s_normRoundPackToF32.c \
	$(SOFTFLOAT_SRC)/s_normSubnormalF32Sig.c \
	$(SOFTFLOAT_SRC)/s_shortShiftRightJam64.c \
	$(SOFTFLOAT_SRC)/s_shiftRightJam32.c \
	$(SOFTFLOAT_SRC)/s_shiftRightJam64.c \
	$(SOFTFLOAT_SRC)/s_countLeadingZeros64.c \
	$(SOFTFLOAT_SRC)/s_countLeadingZeros32.c \
	$(SOFTFLOAT_SRC)/s_countLeadingZeros8.c \
	$(SOFTFLOAT_SRC)/softfloat_state.c

SOFTFLOAT_RISCV_SRCS := \
	$(SOFTFLOAT_RISCV)/s_propagateNaNF32UI.c \
	$(SOFTFLOAT_RISCV)/softfloat_raiseFlags.c

SOFTFLOAT_SRCS := $(SOFTFLOAT_COMMON_SRCS) $(SOFTFLOAT_RISCV_SRCS)
SOFTFLOAT_OBJS := $(patsubst $(SOFTFLOAT_DIR)/%.c,$(SOFTFLOAT_BUILD_DIR)/%.o,$(SOFTFLOAT_SRCS))

# ---- SoftFloat 编译选项 ----
SOFTFLOAT_CFLAGS := -O2 -DSOFTFLOAT_FAST_INT64
SOFTFLOAT_CFLAGS += -I$(SOFTFLOAT_INC)
SOFTFLOAT_CFLAGS += -I$(SOFTFLOAT_RISCV)   # platform.h + specialize.h

# ---- Verilator 编译选项 ----
VFLAGS    := --cc --build --exe --trace
VFLAGS    += -Wno-fatal -Wno-UNOPTFLAT -Wno-UNUSEDSIGNAL
VFLAGS    += -I$(CVFPU_DIR)
VFLAGS    += -I$(COMMON_CELLS)/include
VFLAGS    += -I$(COMMON_CELLS)/src
VFLAGS    += -I$(RTL_DIR)
VFLAGS    += -CFLAGS "-I$(SOFTFLOAT_INC) -I$(CSRC_DIR)"

# ---- RTL 源文件（包定义必须最先） ----
RTL_SRCS  := $(CVFPU_DIR)/fpnew_pkg.sv
RTL_SRCS  += $(TB_DIR)/fmad_dpi.sv
RTL_SRCS  += $(RTL_DIR)/fma_wrap_fp32.sv
RTL_SRCS  += $(CVFPU_DIR)/fpnew_classifier.sv
RTL_SRCS  += $(CVFPU_DIR)/fpnew_rounding.sv
RTL_SRCS  += $(CVFPU_DIR)/fpnew_fma.sv
RTL_SRCS  += $(COMMON_CELLS)/src/cf_math_pkg.sv
RTL_SRCS  += $(COMMON_CELLS)/src/lzc.sv
RTL_SRCS  += $(COMMON_CELLS)/src/rr_arb_tree.sv

# ---- C++ / Testbench 源文件 ----
CPP_SRCS  := $(CSRC_DIR)/fma_dpi.cpp
CPP_SRCS  += $(CSRC_DIR)/sim_main.cpp
CPP_SRCS  += $(TB_DIR)/tb_fma_cosim.sv

# ---- Top module ----
TOP_MOD   := tb_fma_cosim
CEX_TOP_MOD := tb_fma_cex

# ---- CEX 参数 (可通过命令行覆盖) ----
CEX_FILE ?= $(TEST_DIR)/cex_cases.hex
CEX_ARGS := +CEX_FILE=$(CEX_FILE)

# ---- 目标 ----
.PHONY: all softfloat build run cex wave clean clean_formal clean_all

all: softfloat build run

# ---- 从源码编译 SoftFloat ----
softfloat: $(SOFTFLOAT_LIB)

$(SOFTFLOAT_LIB): $(SOFTFLOAT_OBJS)
	@echo "=== Archiving SoftFloat objects ==="
	@mkdir -p $(SOFTFLOAT_BUILD_DIR)
	ar rcs $@ $^

$(SOFTFLOAT_BUILD_DIR)/source/%.o: $(SOFTFLOAT_SRC)/%.c
	@mkdir -p $(dir $@)
	$(CC) -c $(SOFTFLOAT_CFLAGS) -o $@ $<

$(SOFTFLOAT_BUILD_DIR)/source/RISCV/%.o: $(SOFTFLOAT_RISCV)/%.c
	@mkdir -p $(dir $@)
	$(CC) -c $(SOFTFLOAT_CFLAGS) -o $@ $<

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

# ---- CEX replay (file-driven, multi-case) ----
# Usage:
#   make cex                                          # default: tests/cex_cases.hex
#   make cex CEX_FILE=tests/my_cases.hex              # custom file
cex: softfloat
	@echo "=== Building CEX Replay Testbench ==="
	mkdir -p $(LOG_DIR)
	$(VERILATOR) $(VFLAGS) \
		-top $(CEX_TOP_MOD) \
		$(RTL_SRCS) \
		$(CSRC_DIR)/fma_dpi.cpp \
		$(CSRC_DIR)/sim_main_cex.cpp \
		$(TB_DIR)/tb_fma_cex.sv \
		$(SOFTFLOAT_LIB) \
		-LDFLAGS "-lstdc++ -lm" \
		-o $(CEX_TOP_MOD) \
		--Mdir $(LOG_DIR)/obj_dir_cex
	@echo "=== Running CEX Replay ==="
	$(LOG_DIR)/obj_dir_cex/$(CEX_TOP_MOD) $(CEX_ARGS)

# ---- 清理 ----
clean:
	rm -rf $(LOG_DIR)/obj_dir $(LOG_DIR)/obj_dir_cex $(LOG_DIR)/*.vcd $(LOG_DIR)/*.log
	rm -rf $(SOFTFLOAT_BUILD_DIR)

clean_formal:
	rm -rf $(FORMAL_DIR)/run/fp16_* $(FORMAL_DIR)/run/fp32_* $(FORMAL_DIR)/run/fp32_directed

clean_all: clean clean_formal
