# cvfpu FP32 FMA 协同验证项目

本项目对 OpenHW Group cvfpu 的 FP32 融合乘加 (FMA) 模块建立**双重验证闭环**。
Cosim 仿真与 Hector 形式化验证**共享统一的 DUT wrapper 和 golden model 端口命名**。

```
                        输入 (multiplier, multiplicand, addend, rounding_mode)
                                      │
              ┌───────────────────────┴───────────────────────┐
              ▼                                               ▼
┌──────────────────────────────┐         ┌──────────────────────────────┐
│  Cosim (仿真验证)              │         │  Hector (形式化验证)           │
│                               │         │                              │
│  Verilator + DPI-C (go/valid) │         │  VC Formal Hector DPV        │
│  随机/定向采样 ~5000 cases     │         │  全空间穷举 ~2^97 输入         │
│  秒级                          │         │  小时级                       │
│                               │         │                              │
│  Golden: fma_golden_dpi.cpp   │         │  Spec:   fma_spec.cpp        │
│  DUT:    fma_hector_wrap.sv   │         │  Impl:   fma_hector_wrap.sv  │
│          ← 统一复用 ──────────┼─────────┤                              │
└──────────────────────────────┘         └──────────────────────────────┘
              │                                               │
              ▼                                               ▼
     result_rtl vs result_ref                    lemma result_eq, except_eq
     exceptions_rtl vs exceptions_ref            case split: inf/NaN/norm/dnorm
```

## 项目结构

```
cosim/
├── README.md
├── Makefile                            # Cosim + CEX replay 编译与仿真
├── run_eda.sh                          # Docker 启动脚本 (EDA 工具环境)
├── .gitignore
│
├── rtl/                                # (空, DUT wrapper 统一到 hector/)
├── tb/
│   ├── tb_fma_cosim.sv                 # 随机/定向回归 testbench
│   ├── tb_fma_cex.sv                   # CEX 反例回放 testbench (文件驱动)
│   └── dpi_fma_golden.sv               # DPI-C 函数声明 (端口名对齐 Hector)
├── csrc/
│   ├── sim_main.cpp                    # Verilator 仿真入口 (回归)
│   ├── sim_main_cex.cpp                # Verilator 仿真入口 (CEX)
│   ├── fma_golden_dpi.cpp              # DPI-C golden model 实现
│   └── fma_golden_dpi.h                # DPI-C golden model 头文件
├── tests/
│   ├── directed_cases.hex              # 定向测试用例
│   ├── random_seed_list.txt            # 随机种子列表
│   └── cex_cases.hex                   # CEX 反例输入 (模板, gitignored)
├── logs/                               # 仿真产物 (gitignored)
│
├── hector/                             # Hector 形式化验证
│   ├── README.md
│   ├── run/                            # vcf 运行目录 (产物 gitignored)
│   ├── spec/fma_spec.cpp               # C++ spec (Hector API + SoftFloat)
│   ├── rtl/fma_hector_wrap.sv          # SV impl wrapper (go/valid, 与 cosim 共用)
│   ├── tcl/
│   │   ├── command_script_fma32.tcl    # 完整证明 (case split)
│   │   └── command_script_fma32_directed.tcl  # 快速冒烟 (11 cases)
│   └── scripts/
│       ├── run_hector.sh               # 启动完整证明
│       └── run_directed.sh             # 启动快速冒烟
│
├── third_party/                        # 第三方依赖 (内嵌)
│   ├── README.md
│   ├── cvfpu/                          # cvfpu RTL (Solderpad License)
│   └── softfloat/                      # SoftFloat 3e (Hector 兼容修改)
│
└── temp/                               # 项目文档
    ├── cosim_to_hector_migration_plan.md
    ├── cosim_interface_unification_plan.md
    └── hector_open_issues.md
```

## 快速开始

### 环境准备

```bash
cd cosim
# 第三方依赖已内嵌在 third_party/ 中，无需额外克隆
```

### Cosim 仿真回归

```bash
make all NUM=100         # 编译 + 小规模运行
make run NUM=10000       # 大规模回归
make wave                # 查看波形 (GTKWave)
make clean               # 清理
```

### CEX 反例回放

```bash
# 使用默认文件 (tests/cex_cases.hex)
make cex

# 使用自定义 CEX 文件
make cex CEX_FILE=tests/my_cex.hex
```

CEX 输入文件格式 (与 `tests/directed_cases.hex` 相同)：

```
# <A_hex> <B_hex> <C_hex> <RM> <OP_I> <OP_MOD>
# RM:     0=RNE, 1=RTZ, 2=RDN, 3=RUP, 4=RMM
# OP_I:   fpnew_pkg: FMADD=0, FNMSUB=1, ADD=2, MUL=3, ADDS=4
# OP_MOD: 0/1 selects variant (FMSUB, FNMADD, SUB, ...)

01010298 408008e6 81e21720 4 0 0
```

### Hector 形式化验证

```bash
# Docker 环境 (宿主机)
./run_eda.sh

# 容器内 — 快速冒烟 (秒级)
cd /home/eda
./hector/scripts/run_directed.sh
# vcf> make
# vcf> run

# 容器内 — 完整证明 (小时级)
./hector/scripts/run_hector.sh
# vcf> make
# vcf> run_main
```

详见 [hector/README.md](hector/README.md)。

## 统一接口

Cosim 仿真与 Hector 形式化验证**共享同一套接口命名和 DUT wrapper**：

| 信号 | Cosim Golden (DPI) | Hector Spec (C++) | Hector Impl (SV) |
|------|-------------------|--------------------|-------------------|
| operand A | `multiplier` | `multiplier` | `multiplier` |
| operand B | `multiplicand` | `multiplicand` | `multiplicand` |
| operand C | `addend` | `addend` | `addend` |
| rounding | `rounding_mode` | `rounding_mode` | `rounding_mode` |
| result | `result` | `result` | `result` |
| flags | `exceptions` | `exceptions` | `exceptions` |
| op_i / op_mod | fpnew_pkg encoding | — | fpnew_pkg encoding (直通) |
| handshake | go/valid | — | go/valid |
| DUT wrapper | `fma_hector_wrap.sv` | — | `fma_hector_wrap.sv` |

> 仅 `hector/spec/fma_spec.cpp` 因依赖 Hector::API 无法在 Verilator DPI 中复用，
> 故用 `csrc/fma_golden_dpi.cpp` (端口名对齐、纯 DPI-C) 替代。

## 验证层次

| 层级 | 内容 | Cosim | Hector |
|------|------|-------|--------|
| Sanity | 手工用例 (1.0×2.0+3.0 等) | ✅ directed_cases.hex | ✅ directed TCL |
| Random | 随机 32-bit (正常浮点范围) | ✅ 5000+ cases | — |
| CEX Replay | 形式化反例回放验证 | ✅ make cex | — |
| Formal | 全空间穷举等价证明 | — | 🔄 搭建中 |
| Corner | ±0, ±∞, NaN, sNaN, subnormal | ⏳ | 🔄 case split 已覆盖 |
| Full Ops | FMSUB / FNMADD / FNMSUB | ⏳ | ⏳ |

## 核心模型

| 角色 | Cosim | Hector |
|------|-------|--------|
| RTL (DUT) | `hector/rtl/fma_hector_wrap.sv` → `fpnew_fma` | `hector/rtl/fma_hector_wrap.sv` → `fpnew_fma` |
| Golden | `csrc/fma_golden_dpi.cpp` → SoftFloat `f32_mulAdd` | `hector/spec/fma_spec.cpp` → SoftFloat `f32_mulAdd` |
| 接口 | go/valid 脉冲 | go/valid 脉冲 |
| 比较 | SV FSM 逐 case 断言 | TCL lemma 形式化断言 |

## 依赖

| 工具 | 用途 | 版本 |
|------|------|------|
| Verilator | cosim 仿真 | >= 5.0 |
| GCC / Clang | C++ 编译 | C++11 |
| VC Formal (vcf/svi) | Hector 形式化验证 | W-2024.09-SP1 |
| Berkeley SoftFloat | Golden reference | 3e |
| GTKWave | 波形查看 (可选) | — |

## 参考
- [第三方依赖说明](third_party/README.md)
- [cvfpu (OpenHW Group)](https://github.com/openhwgroup/cvfpu)
- [Berkeley SoftFloat](https://github.com/ucb-bar/berkeley-softfloat-3)
