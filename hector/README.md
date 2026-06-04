# Hector DPV — FP32 FMA 形式化等价验证

> cvfpu fpnew_fma (RTL) == Berkeley SoftFloat f32_mulAdd (C)

## 快速开始

```bash
# 0. 启动 EDA Docker 容器（宿主机 cosim/ 目录下）
./run_eda.sh

# 1. 容器内，从项目根目录运行

# 快速冒烟：11 个 directed cases，秒级
cd /home/eda
./hector/scripts/run_directed.sh
# vcf> make
# vcf> run

# 完整证明：全空间穷举，小时级
./hector/scripts/run_hector.sh
# vcf> make
# vcf> run_main
```

两个脚本都自动 `cd hector/run/` 后调用 `vcf`，所有中间产物留在 `hector/run/` 中。

## 两个 TCL 的区别

| | `_directed.tcl` | `command_script_fma32.tcl` |
|---|---|---|
| 输入空间 | 11 个固定 case | 全空间 ~2^97 |
| 约束方式 | `assume` OR 锁定具体值 | `case_split` 11 个分支逐类穷举 |
| 舍入模式 | 固定 RNE (0) | 全部 5 种 (0-4) |
| 耗时 | 秒~分钟 | 小时 |
| 入口 proc | `run` | `run_main` |
| 启动脚本 | `run_directed.sh` | `run_hector.sh` |

## 目录结构

```
hector/
├── README.md
├── run/                                # vcf 运行目录（所有产物在这里）
│   └── .gitkeep
├── spec/
│   └── fma_spec.cpp                    # C++ spec (SoftFloat golden)
├── rtl/
│   └── fma_hector_wrap.sv              # SV wrapper (go/valid 接口)
├── tcl/
│   ├── command_script_fma32.tcl        # 完整证明 (case split)
│   └── command_script_fma32_directed.tcl  # 快速冒烟 (directed cases)
└── scripts/
    ├── run_hector.sh                   # 启动完整证明
    └── run_directed.sh                 # 启动快速冒烟
```

## 架构

```
┌─────────────────────────────┐     ┌──────────────────────────────┐
│  Specification (C++)         │ ==? │  Implementation (SV)          │
│                              │     │                              │
│  fma_spec.cpp                │     │  fma_hector_wrap.sv           │
│    ├─ Hector::API            │     │    ├─ fpnew_fma (cvfpu RTL)   │
│    ├─ SoftFloat f32_mulAdd() │     │    └─ go/valid 握手          │
│    └─ 5 种 RISC-V 舍入模式    │     │                              │
└─────────────────────────────┘     └──────────────────────────────┘
              │                                    │
              └────────── map_by_name ─────────────┘
              ┌──────────────────────────────────┐
              │  lemma: result_eq, except_eq      │
              └──────────────────────────────────┘
```

## 验证流程

| 步骤 | 命令 | 说明 |
|------|------|------|
| 1 | `make` | 编译 spec (cppan) + impl (vcs) + compose |
| 2 | `run` | 快速冒烟：验证 11 个 directed cases |
| 2 | `run_main` | 完整证明：case split → parallel solve |

## 配置

### 组合逻辑 vs 流水线

修改 `hector/rtl/fma_hector_wrap.sv`：

```systemverilog
parameter int unsigned NUM_PIPE_REGS = 0   // 当前：最小延迟（1 cycle）
parameter int unsigned NUM_PIPE_REGS = 1   // 1 级流水线
```

然后在 TCL 的 `ual_main` (或 `ual`) 中调整 phase：

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
| 验证方式 | 随机采样 (N=5000) | 11 个 fixed cases | 全空间穷举 (~2^97) |
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
