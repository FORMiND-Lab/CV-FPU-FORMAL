# cvfpu FP32 / FP16 FMA 协同验证项目

本项目对 OpenHW Group cvfpu 的 FP32 和 FP16 融合乘加 (FMA) 模块建立**双重验证闭环**。
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
│  随机/定向采样 ~5000 cases     │         │  全空间穷举                    │
│  秒级                          │         │  小时级                       │
│                               │         │                              │
│  Golden: fma_dpi.cpp          │         │  Spec: fma_spec_wrap_fp*.cpp │
│  DUT:    fma_wrap_fp32   │         │  Impl: fma_wrap_fp32.sv │
│          ← 统一复用 ──────────┼─────────┤                              │
└──────────────────────────────┘         └──────────────────────────────┘
              │                                               │
              ▼                                               ▼
     result_rtl vs result_ref                    lemma result_eq, except_eq
     exceptions_rtl vs exceptions_ref            case split: inf/NaN/norm/dnorm
```

## 项目结构

```
CV-FPU-FORMAL/
├── README.md
├── Makefile                                # Cosim + CEX replay 编译与仿真
├── run_eda.sh                              # Docker 启动脚本 (EDA 工具环境)
├── start-hector-ssh.sh                     # 启动 Hector SSH 服务
├── .gitignore
│
├── rtl/                                    # DUT wrapper (Hector + Cosim 共用)
│   ├── fma_wrap_fp16.sv                    # FP16 wrapper (go/valid 接口)
│   └── fma_wrap_fp32.sv               # FP32 wrapper (go/valid 接口)
│
├── sim/
│   ├── tb/
│   │   ├── tb_fma_cosim.sv                 # 随机/定向回归 testbench
│   │   ├── tb_fma_cex.sv                   # CEX 反例回放 testbench (文件驱动)
│   │   └── fmad_dpi.sv                     # DPI-C 函数声明 (端口名对齐 Hector)
│   ├── tests/
│   │   ├── directed_cases.hex              # 定向测试用例
│   │   ├── random_seed_list.txt            # 随机种子列表
│   │   └── cex_cases.hex                   # CEX 反例输入
│   ├── logs/                               # 仿真产物 (gitignored)
│   └── csrc/
│       ├── sim_main.cpp                    # Verilator 仿真入口 (回归)
│       ├── sim_main_cex.cpp                # Verilator 仿真入口 (CEX)
│       ├── fma_dpi.cpp                     # DPI-C golden model 实现 (全 7 种运算)
│       └── fma_dpi.h                       # DPI-C golden model 头文件
│
├── formal/                                 # Hector 形式化验证
│   ├── README.md
│   ├── run/                                # vcf 运行目录 (产物 gitignored)
│   ├── spec/
│   │   ├── fma_spec_wrap_fp16.cpp          # FP16 统一 spec (全部 7 种运算)
│   │   ├── fma_spec_wrap_fp32.cpp          # FP32 统一 spec (全部 7 种运算)
│   │   └── fma_spec_wrap_fp32_fmadd.cpp    # (遗留) FP32 FMADD-only spec
│   ├── tcl/
│   │   ├── command_script_fp16_fmadd.tcl   # FP16: FMADD
│   │   ├── command_script_fp16_fmsub.tcl   # FP16: FMSUB
│   │   ├── command_script_fp16_fnmsub.tcl  # FP16: FNMSUB
│   │   ├── command_script_fp16_fnmadd.tcl  # FP16: FNMADD
│   │   ├── command_script_fp16_add.tcl     # FP16: ADD
│   │   ├── command_script_fp16_sub.tcl     # FP16: SUB
│   │   ├── command_script_fp16_mul.tcl     # FP16: MUL
│   │   ├── command_script_fp32_fmadd.tcl   # FP32: FMADD
│   │   ├── command_script_fp32_fmsub.tcl   # FP32: FMSUB
│   │   ├── command_script_fp32_fnmsub.tcl  # FP32: FNMSUB
│   │   ├── command_script_fp32_fnmadd.tcl  # FP32: FNMADD
│   │   ├── command_script_fp32_add.tcl     # FP32: ADD
│   │   ├── command_script_fp32_sub.tcl     # FP32: SUB
│   │   ├── command_script_fp32_mul.tcl     # FP32: MUL
│   │   └── command_script_fp32_directed.tcl  # FP32: 快速冒烟 (11 cases)
│   └── scripts/
│       ├── run_fp16.sh                     # FP16 操作选择验证 (7 ops)
│       ├── run_fp32.sh                     # FP32 操作选择验证 (7 ops)
│       └── run_directed.sh                 # FP32 快速冒烟
│
└── third_party/                            # 第三方依赖 (内嵌)
    ├── README.md                           # 审计说明 (修改记录)
    ├── cvfpu/                              # cvfpu RTL (Solderpad License)
    └── softfloat/                          # Berkeley SoftFloat 3e (Hector 兼容修改)
```

## 快速开始

### 环境准备

```bash
cd CV-FPU-FORMAL
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
# 使用默认文件 (sim/tests/cex_cases.hex)
make cex

# 使用自定义 CEX 文件
make cex CEX_FILE=sim/tests/my_cex.hex
```

CEX 输入文件格式 (与 `sim/tests/directed_cases.hex` 相同)：

```
# <A_hex> <B_hex> <C_hex> <RM> <OP_I> <OP_MOD>
# RM:     0=RNE, 1=RTZ, 2=RDN, 3=RUP, 4=RMM
# OP_I:   fpnew_pkg: FMADD=0, FNMSUB=1, ADD=2, MUL=3, ADDS=4
# OP_MOD: 0/1 selects variant (FMSUB, FNMADD, SUB, ...)

01010298 408008e6 81e21720 4 0 0
```

### Hector 形式化验证

```bash
# 0. 宿主机：启动 EDA Docker 容器
./run_eda.sh

# 1. 容器内：启动 Hector SSH 服务（可指定端口，默认 2222）
./start-hector-ssh.sh
# ./start-hector-ssh.sh 2223     # 指定端口

# 2. 容器内，从项目根目录运行验证
cd /home/eda

# FP16 — 单操作验证（可指定 worker 数，默认 16）
./formal/scripts/run_fp16.sh fmadd       # FMADD, 16 workers
./formal/scripts/run_fp16.sh mul 8       # MUL, 8 workers
# ... 全部 7 种操作: fmadd, fmsub, fnmsub, fnmadd, add, sub, mul

# FP32 — 单操作验证 (全 7 种)
./formal/scripts/run_fp32.sh fmadd       # FMADD, 16 workers
./formal/scripts/run_fp32.sh fmsub 8     # FMSUB, 8 workers
# ... 全部 7 种操作: fmadd, fmsub, fnmsub, fnmadd, add, sub, mul

# FP32 — 快速冒烟 (秒级)
./formal/scripts/run_directed.sh         # 16 workers
./formal/scripts/run_directed.sh 4       # 4 workers

# 并行运行示例（各操作产物在 formal/run/ 下独立子目录）
# ./formal/scripts/run_fp32.sh fmadd &
# ./formal/scripts/run_fp32.sh mul &
# ./formal/scripts/run_fp16.sh add &
# vcf> run
```

详见 [formal/README.md](formal/README.md)。

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
| op_i / op_mod | fpnew_pkg encoding | fpnew_pkg encoding | fpnew_pkg encoding (直通) |
| handshake | go/valid | — | go/valid |
| FP16 wrapper | `fma_wrap_fp16.sv` | — | `fma_wrap_fp16.sv` |
| FP32 wrapper | `fma_wrap_fp32.sv` | — | `fma_wrap_fp32.sv` |

> Hector spec 因依赖 Hector::API 无法在 Verilator DPI 中复用，
> 故用 `sim/csrc/fma_dpi.cpp` (端口名对齐、纯 DPI-C) 替代。

## 验证层次

| 层级 | 内容 | Cosim | Hector |
|------|------|-------|--------|
| Sanity | 手工用例 (1.0×2.0+3.0 等) | ✅ directed_cases.hex | ✅ directed TCL |
| Random | 随机 (正常浮点范围) | ✅ 5000+ cases | — |
| CEX Replay | 形式化反例回放验证 | ✅ make cex | — |
| Formal FP32 | FP32 全空间穷举等价证明 (全 7 种运算) | — | ✅ 搭建完成 |
| Formal FP16 | FP16 全空间穷举 (FMA/ADD/SUB/MUL) | — | ✅ 7 种运算全覆盖 |
| Corner | ±0, ±∞, NaN, sNaN, subnormal | ⏳ | ✅ case split 已覆盖 |
| Full Ops | FMSUB / FNMADD / FNMSUB (FP32 + FP16) | ⏳ | ✅ 14 TCL 全覆盖 |

## 操作编码

| op_i | op_mod | 操作 | SoftFloat 调用 |
|------|--------|------|---------------|
| 0 (FMADD) | 0 | FMADD | `f32_mulAdd(A, B, C)` |
| 0 (FMADD) | 1 | FMSUB | `f32_mulAdd(A, B, neg(C))` |
| 1 (FNMSUB) | 0 | FNMSUB | `f32_mulAdd(neg(A), B, C)` |
| 1 (FNMSUB) | 1 | FNMADD | `f32_mulAdd(neg(A), B, neg(C))` |
| 2 (ADD) | 0 | ADD | `f32_add(B, C)` |
| 2 (ADD) | 1 | SUB | `f32_sub(B, C)` |
| 3 (MUL) | x | MUL | `f32_mul(A, B)` |

## 核心模型

| 角色 | Cosim | Hector FP16 | Hector FP32 |
|------|-------|-------------|-------------|
| RTL (DUT) | `rtl/fma_wrap_fp32.sv` → `fpnew_fma` | `rtl/fma_wrap_fp16.sv` → `fpnew_fma` | `rtl/fma_wrap_fp32.sv` → `fpnew_fma` |
| Golden | `sim/csrc/fma_dpi.cpp` → SoftFloat (全 7 种运算) | `formal/spec/fma_spec_wrap_fp16.cpp` → SoftFloat (全 7 种运算) | `formal/spec/fma_spec_wrap_fp32.cpp` → SoftFloat (全 7 种运算) |
| 接口 | go/valid 脉冲 | go/valid 脉冲 | go/valid 脉冲 |
| 比较 | SV FSM 逐 case 断言 | TCL lemma 形式化断言 | TCL lemma 形式化断言 |

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
- [Hector 形式化验证说明](formal/README.md)
- [cvfpu (OpenHW Group)](https://github.com/openhwgroup/cvfpu)
- [Berkeley SoftFloat](https://github.com/ucb-bar/berkeley-softfloat-3)
