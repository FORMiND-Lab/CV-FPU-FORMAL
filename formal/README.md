# Hector DPV — FP16 / FP32 FMA 形式化等价验证

> cvfpu fpnew_fma (RTL) == Berkeley SoftFloat (C)

## 快速开始

```bash
# 0. 宿主机：启动 EDA Docker 容器
./run_eda.sh

# 1. 容器内：启动 Hector SSH 服务（可指定端口，默认 2222）
./start-hector-ssh.sh
# ./start-hector-ssh.sh 2223          # 指定端口

# 2. 容器内，从项目根目录运行验证（可指定 worker 数，默认 16）
cd /home/eda

# FP16 — 单操作验证 (7 种)
./formal/scripts/run_fp16.sh fmadd    # FMADD (op_i=0, op_mod=0)
./formal/scripts/run_fp16.sh mul 8    # MUL, 8 workers

# FP32 — 单操作验证 (7 种)
./formal/scripts/run_fp32.sh fmadd    # FMADD (op_i=0, op_mod=0)
./formal/scripts/run_fp32.sh fmsub 4  # FMSUB, 4 workers

# FP32 — 快速冒烟
./formal/scripts/run_directed.sh      # 11 directed cases, 16 workers
./formal/scripts/run_directed.sh 8    # 8 workers

# 并行运行（各操作产物独立目录，互不干扰）
# ./formal/scripts/run_fp32.sh fmadd &
# ./formal/scripts/run_fp32.sh mul &
# ./formal/scripts/run_fp16.sh add &
```

脚本在 `formal/run/<精度>_<操作>/` 下自动创建独立子目录，host.qsub 和 vcf 产物各归各位，可并行运行。

## TCL 概览

### FP16（7 操作 + 1 统一 spec）

| TCL | 操作 | op_i / op_mod |
|---|---|---|
| `command_script_fp16_fmadd.tcl` | FMADD | 0 / 0 |
| `command_script_fp16_fmsub.tcl` | FMSUB | 0 / 1 |
| `command_script_fp16_fnmsub.tcl` | FNMSUB | 1 / 0 |
| `command_script_fp16_fnmadd.tcl` | FNMADD | 1 / 1 |
| `command_script_fp16_add.tcl` | ADD | 2 / 0 |
| `command_script_fp16_sub.tcl` | SUB | 2 / 1 |
| `command_script_fp16_mul.tcl` | MUL | 3 / 0 |

全部指向同一个统一 spec：`formal/spec/fma_spec_wrap_fp16.cpp`

### FP32（7 操作 + 1 统一 spec + 1 快速冒烟）

| TCL | 操作 | op_i / op_mod |
|---|---|---|
| `command_script_fp32_fmadd.tcl` | FMADD | 0 / 0 |
| `command_script_fp32_fmsub.tcl` | FMSUB | 0 / 1 |
| `command_script_fp32_fnmsub.tcl` | FNMSUB | 1 / 0 |
| `command_script_fp32_fnmadd.tcl` | FNMADD | 1 / 1 |
| `command_script_fp32_add.tcl` | ADD | 2 / 0 |
| `command_script_fp32_sub.tcl` | SUB | 2 / 1 |
| `command_script_fp32_mul.tcl` | MUL | 3 / 0 |
| `command_script_fp32_directed.tcl` | — | 快速冒烟 (11 directed cases) |

全部指向同一个统一 spec：`formal/spec/fma_spec_wrap_fp32.cpp`

> `formal/spec/fma_spec_wrap_fp32_fmadd.cpp` 为遗留的 FMADD-only spec，保留供参考。

FP16 和 FP32 各自的 7 个 TCL 结构完全相同（共享 `compile_spec`、`compile_impl`、`case_split`），仅在 `ual_main` 中约束不同的 `op_i` / `op_mod_i`（以及 MUL 额外约束 C 操作为非特殊值）。

## 目录结构

```
formal/
├── README.md
├── run/                                    # vcf 运行目录（每操作独立子目录）
├── spec/
│   ├── fma_spec_wrap_fp16.cpp              # FP16 统一 spec (全部 7 种运算)
│   ├── fma_spec_wrap_fp32.cpp              # FP32 统一 spec (全部 7 种运算)
│   └── fma_spec_wrap_fp32_fmadd.cpp        # (遗留) FP32 FMADD-only spec
├── tcl/
│   ├── command_script_fp16_fmadd.tcl       # FP16: FMADD
│   ├── command_script_fp16_fmsub.tcl       # FP16: FMSUB
│   ├── command_script_fp16_fnmsub.tcl      # FP16: FNMSUB
│   ├── command_script_fp16_fnmadd.tcl      # FP16: FNMADD
│   ├── command_script_fp16_add.tcl         # FP16: ADD
│   ├── command_script_fp16_sub.tcl         # FP16: SUB
│   ├── command_script_fp16_mul.tcl         # FP16: MUL
│   ├── command_script_fp32_fmadd.tcl       # FP32: FMADD
│   ├── command_script_fp32_fmsub.tcl       # FP32: FMSUB
│   ├── command_script_fp32_fnmsub.tcl      # FP32: FNMSUB
│   ├── command_script_fp32_fnmadd.tcl      # FP32: FNMADD
│   ├── command_script_fp32_add.tcl         # FP32: ADD
│   ├── command_script_fp32_sub.tcl         # FP32: SUB
│   ├── command_script_fp32_mul.tcl         # FP32: MUL
│   └── command_script_fp32_directed.tcl   # FP32: 快速冒烟 (11 cases)
└── scripts/
    ├── run_fp16.sh                         # FP16 操作选择验证 (7 ops)
    ├── run_fp32.sh                         # FP32 操作选择验证 (7 ops)
    └── run_directed.sh                     # FP32 快速冒烟
```

> RTL wrapper 文件统一放在 `rtl/` 下（`fma_wrap_fp16.sv`、`fma_wrap_fp32.sv`），Hector TCL 通过 `../../rtl/` 引用。

## 架构

```
┌──────────────────────────────────┐     ┌──────────────────────────────────┐
│  Specification (C++)              │ ==? │  Implementation (SV)              │
│                                   │     │                                   │
│  FP16: fma_spec_wrap_fp16.cpp    │     │  FP16: fma_wrap_fp16.sv           │
│    └─ SoftFloat f16_mulAdd/add/  │     │    └─ fpnew_fma (FP16)            │
│       sub/mul + op_i/op_mod 选择  │     │                                   │
│                                   │     │  FP32: fma_wrap_fp32.sv     │
│  FP32: fma_spec_wrap_fp32.cpp    │     │    └─ fpnew_fma (FP32)            │
│    └─ SoftFloat f32_mulAdd/add/  │     │                                   │
│       sub/mul + op_i/op_mod 选择  │     │  统一接口: go/valid 握手           │
│                                   │     │                                   │
│  5 种 RISC-V 舍入模式             │     │                                   │
│  7 种运算 (FMADD/FMSUB/.../MUL)  │     │  7 种运算 (fpnew_pkg encoding)    │
└──────────────────────────────────┘     └──────────────────────────────────┘
              │                                         │
              └──────────── map_by_name ────────────────┘
              ┌────────────────────────────────────────┐
              │  lemma: result_eq, except_eq            │
              └────────────────────────────────────────┘
```

## 验证流程

| 步骤 | 命令 | 说明 |
|------|------|------|
| 1 | `make` | 编译 spec (cppan) + impl (vcs) + compose |
| 2 | `run_main` | 完整证明：case split → parallel solve |

每个操作独立的 TCL 脚本通过 `vcf -f <tcl> -fmode DPV` 一键运行，或进入 vcf 交互模式手动执行 `make` 和 `run_main`。

## Case Split 策略

FP16 和 FP32 TCL 使用相同的 case split 框架，按 IEEE 754 浮点分类划分：

| Case | 描述 | 枚举策略 |
|------|------|----------|
| `A_inf_NaN` | A 操作数为 Inf/NaN | 穷举 B, C |
| `B_inf_NaN` | B 操作数为 Inf/NaN | 穷举 A, C |
| `C_inf_NaN` | C 操作数为 Inf/NaN | 穷举 A, B |
| `norm_norm_norm` | 三者均为 normal | 穷举 |
| `A_dnorm` | A 为 subnormal | leading1 枚举尾数 |
| `B_dnorm` | B 为 subnormal | leading1 枚举尾数 |
| `C_dnorm` | C 为 subnormal | leading1 枚举尾数 |
| `AB_dnorm` | A, B 均为 subnormal | — |
| `BC_dnorm` | B, C 均为 subnormal | leading1 枚举尾数 |
| `AC_dnorm` | A, C 均为 subnormal | leading1 枚举尾数 |
| `ABC_dnorm` | 三者均为 subnormal | leading1 枚举尾数 |

FP32 使用 `[30:23]` (8-bit 指数) 和 `[22:0]` (23-bit 尾数)，Inf/NaN 检查为 `8'hff`，subnormal 检查为 `8'h00`。

## 配置

### 组合逻辑 vs 流水线

修改 `rtl/fma_wrap_fp32.sv`（或 `fma_wrap_fp16.sv`）：

```systemverilog
parameter int unsigned NUM_PIPE_REGS = 0   // 当前：组合逻辑
parameter int unsigned NUM_PIPE_REGS = 1   // 1 级流水线
```

然后在 TCL 的 `ual_main` 中调整 phase：

```tcl
# NUM_PIPE_REGS=0: impl 比 spec 晚 1 拍
lemma result_eq = spec.result(1) == impl.result(2)

# NUM_PIPE_REGS=1: impl 晚 2 拍
lemma result_eq = spec.result(1) == impl.result(3)
```

### 舍入模式

| 编码 | 名称 | 说明 |
|------|------|------|
| 000 | RNE | Round to Nearest, ties to Even |
| 001 | RTZ | Round towards Zero |
| 010 | RDN | Round Down (towards −∞) |
| 011 | RUP | Round Up (towards +∞) |
| 100 | RMM | Round to Nearest, ties to Max Magnitude |

## 与 cosim 仿真的关系

| 维度 | cosim (Verilator) | Hector directed | Hector full |
|------|-------------------|-----------------|-------------|
| 验证方式 | 随机采样 (N=5000) | 11 个 fixed cases | 全空间穷举 |
| 耗时 | 秒级 | 秒~分钟 | 小时级 |
| 覆盖度 | 统计采样 | 基本场景 | 100% 数学证明 |
| 用途 | 快速回归、debug | 流程冒烟 | 签核级完备证明 |
| FP32 运算 | 全 5 种 (DPI) | 11 cases (FMADD) | 全 7 种 (Hector) |
| FP16 运算 | — | — | 全 7 种 (Hector) |

## 已知问题

1. **HDPS 子证明**：fpnew_fma 内部乘法器和前导零单元的 cutpoint 信号名需确定
2. **NaN payload**：RISC-V canonical NaN vs IEEE 754 NaN payload 差异
3. **时序延迟**：fpnew_fma 确切的 latency cycle 数需验证
4. **MUL 操作 C 约束**：`f32_mul` / `f16_mul` 忽略 C 操作数，但 `fpnew_fma` 在 MUL 模式下可能通过 C 传播 NaN。MUL TCL 在 `ual_main` 中约束 C 为非特殊值 (`spec.addend(1)[30:23] != 8'hff`)

## 参考

- [第三方依赖说明](../third_party/README.md)
- [cvfpu (OpenHW Group)](https://github.com/openhwgroup/cvfpu)
- [Berkeley SoftFloat](https://github.com/ucb-bar/berkeley-softfloat-3)
