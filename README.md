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

第一阶段只验证 **FP32 fused multiply-add (FMADD / FMSUB)**。

## 项目结构

```
test_cv_fpv/
├── cvfpu/                        # cvfpu RTL 源码
│   ├── src/                      # （fpnew_fma, fpnew_pkg, ...）
│   ├── tb/
│   ├── docs/
│   └── ...
├── cosim/                        # ★ 本协同验证项目
│   ├── Makefile
│   ├── README.md
│   ├── rtl/
│   │   └── fma_dut_wrapper.sv    # 包装 fpnew_fma，固定 FP32
│   ├── tb/
│   │   ├── tb_fma_cosim.sv       # SystemVerilog testbench
│   │   └── dpi_softfloat.sv      # DPI-C 函数声明
│   ├── csrc/
│   │   ├── softfloat_dpi.cpp     # DPI-C 实现（调 SoftFloat）
│   │   └── softfloat_dpi.h       # DPI-C 头文件
│   ├── tests/
│   │   ├── directed_cases.hex    # 定向测试用例
│   │   └── random_seed_list.txt  # 随机测试种子列表
│   └── logs/                     # 仿真日志和波形
└── temp/                         # 临时文档
```

## 快速开始

```bash
# 1. 拉取 SoftFloat 依赖（如尚未 clone）
git clone https://github.com/ucb-bar/berkeley-softfloat-3 ../berkeley-softfloat-3

# 2. 编译 SoftFloat
make softfloat

# 3. 编译 DUT + testbench
make build

# 4. 运行仿真
make run
make run SEED=1 NUM=10000

# 5. 查看波形
make wave

# 6. 清理
make clean
```

## 验证层次

| 层级 | 内容 | 用例数 |
|------|------|--------|
| Sanity | 普通数值的基本运算 | ~10 |
| Corner | ±0, ±∞, NaN, sNaN, subnormal, overflow, underflow | ~50 |
| Random | 随机 32-bit pattern | 1000+ |

## 依赖

- Verilator (>= 4.0)
- GCC / Clang (C++11)
- GNU Make
- GTKWave (可选，用于波形查看)
