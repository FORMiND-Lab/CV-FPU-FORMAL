# Hector DPV — FP16 / FP32 FMA 形式化等价验证

> cvfpu fpnew_fma (RTL) == Berkeley SoftFloat (C)

## 快速开始

```bash
# 0. 宿主机：启动 EDA Docker 容器
./run_eda.sh

# 1. 容器内：启动 Hector SSH 服务 + 配置并行求解节点
./start-hector-ssh.sh
./setup-hector-qsub.sh 16

# 2. 容器内，从项目根目录运行验证

# FP16 — 单操作验证
cd /home/eda
./formal/scripts/run_fp16.sh fmadd    # FMADD (op_i=0, op_mod=0)
./formal/scripts/run_fp16.sh mul      # MUL
./formal/scripts/run_fp16.sh sub      # SUB

# FP32 — 完整证明
./formal/scripts/run_directed.sh      # 快速冒烟: 11 directed cases
./formal/scripts/run_fp32_fmadd.sh        # 完整证明: 全空间穷举
```

脚本自动 `cd formal/run/` 后调用 `vcf`，产物留在 `formal/run/` 中。

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

全部指向同一个合并 spec：`formal/spec/fma_spec_wrap_fp16.cpp`

### FP32（统一 TCL）

| TCL | 说明 |
|---|---|
| `command_script_fp32_fmadd.tcl` | 完整证明 (case split) |
| `command_script_fma32_directed.tcl` | 快速冒烟 (directed cases) |
| `command_script_fma32_enu.tcl` | 枚举策略 |
| `command_script_fma32_hdps_full.tcl` | HDPS 完整流程 |
| `command_script_fma32_hdps_mul.tcl` | HDPS 乘法器专用 |

## 目录结构

```
formal/
├── README.md
├── run/                                    # vcf 运行目录（所有产物在这里）
├── spec/
│   ├── fma_spec_wrap_fp16.cpp              # FP16 合并 spec (全部 7 种运算)
│   └── fma_spec_wrap_fp32_fmadd.cpp         # FP32 spec (SoftFloat golden)
├── tcl/
│   ├── command_script_fp16_fmadd.tcl       # FP16: FMADD
│   ├── command_script_fp16_fmsub.tcl       # FP16: FMSUB
│   ├── command_script_fp16_fnmsub.tcl      # FP16: FNMSUB
│   ├── command_script_fp16_fnmadd.tcl      # FP16: FNMADD
│   ├── command_script_fp16_add.tcl         # FP16: ADD
│   ├── command_script_fp16_sub.tcl         # FP16: SUB
│   ├── command_script_fp16_mul.tcl         # FP16: MUL
│   ├── command_script_fp32_fmadd.tcl       # FP32: 完整证明
│   ├── command_script_fma32_directed.tcl   # FP32: 快速冒烟
│   ├── command_script_fma32_enu.tcl        # FP32: 枚举
│   ├── command_script_fma32_hdps_full.tcl  # FP32: HDPS 完整
│   └── command_script_fma32_hdps_mul.tcl   # FP32: HDPS 乘法器
└── scripts/
    ├── run_fp16.sh                         # FP16 操作选择验证
    ├── run_fp32_fmadd.sh                       # FP32 完整证明
    └── run_directed.sh                     # FP32 快速冒烟
```

> RTL wrapper 文件统一放在 `cosim/rtl/` 下（`fma_wrap_fp16.sv`、`fma_wrap_fmad_fp32.sv`），Hector TCL 通过 `../../rtl/` 引用。

## 架构

```
┌──────────────────────────────────┐     ┌──────────────────────────────────┐
│  Specification (C++)              │ ==? │  Implementation (SV)              │
│                                   │     │                                   │
│  FP16: fma_spec_wrap_fp16.cpp    │     │  FP16: fma_wrap_fp16.sv           │
│    └─ SoftFloat f16_mulAdd/add/  │     │    └─ fpnew_fma (FP16)            │
│       sub/mul + op_i/op_mod 选择  │     │                                   │
│                                   │     │  FP32: fma_wrap_fmad_fp32.sv     │
│  FP32: fma_spec_wrap_fp32_fmadd   │     │    └─ fpnew_fma (FP32)            │
│    └─ SoftFloat f32_mulAdd()     │     │                                   │
│                                   │     │  统一接口: go/valid 握手           │
│  5 种 RISC-V 舍入模式             │     │                                   │
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

## 配置

### 组合逻辑 vs 流水线

修改 `cosim/rtl/fma_wrap_fp16.sv`（或 `fma_wrap_fmad_fp32.sv`）：

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

## 已知问题

详见 `../temp/hector_open_issues.md`：

1. **HDPS 子证明**：fpnew_fma 内部乘法器和前导零单元的 cutpoint 信号名需确定
2. **NaN payload**：RISC-V canonical NaN vs IEEE 754 NaN payload 差异
3. **时序延迟**：fpnew_fma 确切的 latency cycle 数需验证

## 参考

- [cosim → Hector 迁移计划](../temp/cosim_to_hector_migration_plan.md)
- [Hector 开放问题](../temp/hector_open_issues.md)
- [DPV_Advanced 示例](../third_party/example/DPV_Advanced/)
- [第三方依赖说明](../third_party/README.md)
