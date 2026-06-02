# cvfpu FMA + SoftFloat Co-Simulation 样例项目

## 项目目标

本样例项目建立了一个最小可运行的协同验证环境：

```
随机/定向测试输入 a, b, c, rounding mode
        │
        ├── cvfpu fpnew_fma RTL
        │       输出 result_rtl + status_rtl
        │
        └── SoftFloat golden model
                输出 result_ref + fflags_ref

比较：
result_rtl == result_ref
status_rtl == fflags_ref
```

第一阶段只验证 **FP32 fused multiply-add (FMADD)**。

## 仿真架构

```
sim_main.cpp (C++)                 tb_fma_cosim.sv (SystemVerilog)
     │                                        │
     ├─ 驱动 clk, rst_n ──────────────────────┤
     │                                        │
     │                        ┌─ always @* ──────────────────────┐
     │                        │  生成测试向量 + 调用 DPI SoftFloat │
     │                        │  得到 golden result / fflags      │
     │                        └──────────────────────────────────┘
     │                                        │
     │                        ┌─ always_ff FSM ──────────────────┐
     │                        │  ST_SETUP → ST_CHECK → next case │
     │                        │  驱动 DUT valid/operands         │
     │                        │  比较 RTL output vs golden       │
     │                        └──────────────────────────────────┘
     │                                        │
     └─ eval() 每半周期 ───────────────────────┘
```

- 仿真方式：Verilator cycle-based，C++ 驱动时钟，无 `--timing` 依赖
- DPI 调用：组合逻辑 `always @*` 中调用 SoftFloat `f32_mulAdd`
- 比较策略：逐 case 同步比较 result 和 fflags

## 项目结构

```
test_cv_fpv/
├── cvfpu/                        # cvfpu RTL 源码
│   ├── src/                      # （fpnew_fma, fpnew_pkg, ...）
│   └── ...
├── berkeley-softfloat-3/         # Berkeley SoftFloat 参考模型
├── cosim/                        # ★ 本协同验证项目
│   ├── Makefile                  # 编译脚本 (softfloat / build / run / wave / clean)
│   ├── README.md
│   ├── .gitignore
│   ├── rtl/
│   │   └── fma_dut_wrapper.sv    # 包装 fpnew_fma，固定 FP32
│   ├── tb/
│   │   ├── tb_fma_cosim.sv       # Testbench (FSM + always @* 组合 DPI)
│   │   └── dpi_softfloat.sv      # DPI-C 函数声明 (package)
│   ├── csrc/
│   │   ├── sim_main.cpp          # Verilator 仿真入口 (C++ main, 驱动时钟)
│   │   ├── softfloat_dpi.cpp     # DPI-C 实现 (调 SoftFloat f32_mulAdd)
│   │   └── softfloat_dpi.h       # DPI-C 头文件
│   └── logs/                     # 构建产物 + 波形
└── temp/                         # 临时文档
```

## 快速开始

```bash
# 0. 进入项目目录
cd cosim

# 1. 拉取依赖
git clone https://github.com/openhwgroup/cvfpu ../cvfpu
git -C ../cvfpu submodule update --init --recursive
git clone https://github.com/ucb-bar/berkeley-softfloat-3 ../berkeley-softfloat-3

# 2. 一键编译 + 运行
make all NUM=100

# 3. 大规模回归
make run NUM=10000

# 4. 查看波形
make wave

# 5. 清理
make clean
```

## 验证层次

| 层级 | 内容 | 状态 |
|------|------|------|
| Sanity | 4 个手工用例 (1.0×2.0+3.0 等) | ✅ 已实现 |
| Random | 随机 32-bit pattern (约束在正常浮点范围) | ✅ 已实现 |
| Corner | ±0, ±∞, NaN, sNaN, subnormal, overflow, underflow | ⏳ 待实现 |
| Full Ops | FMSUB / FNMADD / FNMSUB | ⏳ 待实现 |

## 验证结果

```
$ make run NUM=5000
============================================================
 cvfpu FMA + SoftFloat Co-Simulation Testbench
 SEED=1, NUM=5000
============================================================
 PASS: 5004, FAIL: 0, TOTAL: 5004
============================================================
ALL TESTS PASSED
```

## 依赖

- Verilator (>= 5.0)
- GCC / Clang (C++11)
- GNU Make
- Berkeley SoftFloat 3e (放置于 `../berkeley-softfloat-3/`)
- GTKWave (可选，用于波形查看)
