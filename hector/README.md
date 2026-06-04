# Hector DPV Formal Verification for cvfpu FP32 FMA

> 全空间穷举等价证明：cvfpu fpnew_fma (RTL) == Berkeley SoftFloat f32_mulAdd (C)

## 快速开始

```bash
# 0. 启动 EDA Docker 容器（如需要）
./run_eda.sh

# 1. 在容器内运行 Hector 证明
./hector/scripts/run_hector.sh

# 或者直接调 vcf（语法参照 DPV_Advanced 样例）:
vcf -f hector/tcl/command_script_fma32.tcl -fmode DPV
```

## 目录结构

```
hector/
├── README.md                           # 本文件
├── spec/
│   └── fma_spec.cpp                    # C++ Hector spec model (SoftFloat golden)
├── rtl/
│   └── fma_hector_wrap.sv              # SV wrapper (fpnew_fma → Hector interface)
├── tcl/
│   └── command_script_fma32.tcl        # TCL flow: compile → compose → solve
└── scripts/
    └── run_hector.sh                   # 一键运行脚本
```

## 架构概览

```
┌─────────────────────────────┐     ┌──────────────────────────────┐
│  Specification (C++)         │ ==? │  Implementation (SV)          │
│                              │     │                              │
│  fma_spec.cpp                │     │  fma_hector_wrap.sv           │
│    ├─ Hector::API            │     │    ├─ fpnew_fma (cvfpu RTL)   │
│    ├─ SoftFloat f32_mulAdd() │     │    └─ go/valid interface     │
│    └─ 5 RISC-V rounding modes│     │                              │
└─────────────────────────────┘     └──────────────────────────────┘
              │                                    │
              └────────── map_by_name ─────────────┘
              ┌──────────────────────────────────┐
              │  lemma: result_eq, except_eq      │
              │  case split: inf/NaN/norm/dnorm   │
              └──────────────────────────────────┘
```

## 验证流程

| 步骤 | TCL Procedure | 说明 |
|------|--------------|------|
| 1 | `compile_spec` | cppan 编译 C++ spec + SoftFloat 源文件 |
| 2 | `compile_impl` | vcs 编译 SV RTL (fpnew_fma + wrapper) |
| 3 | `compose` | 建立 spec ↔ impl 的 formal model |
| 4 | `solveNB p` | 穷举证明 (case split → parallel solve) |

## 配置选项

### 组合逻辑 vs 流水线

修改 `hector/rtl/fma_hector_wrap.sv` 中的 `NUM_PIPE_REGS` 参数：

```systemverilog
parameter int unsigned NUM_PIPE_REGS = 0   // 0 = combinational (先证这个)
parameter int unsigned NUM_PIPE_REGS = 1   // 1 级流水线
```

然后在 `command_script_fma32.tcl` 的 `ual_main` 中调整时序：

```tcl
# NUM_PIPE_REGS=0: impl phase = 2
lemma result_eq = spec.result(1) == impl.result(2)

# NUM_PIPE_REGS=1: impl phase = 3
lemma result_eq = spec.result(1) == impl.result(3)
```

### 舍入模式

RISC-V 定义了 5 种舍入模式 (0-4)，Hector specification 通过 `assume` 约束：

| 编码 | 名称 | 说明 |
|------|------|------|
| 000 | RNE | Round to Nearest, ties to Even |
| 001 | RTZ | Round towards Zero |
| 010 | RDN | Round Down (towards −∞) |
| 011 | RUP | Round Up (towards +∞) |
| 100 | RMM | Round to Nearest, ties to Max Magnitude |

## 与 cosim 的关系

| 维度 | cosim (仿真) | Hector (形式化) |
|------|-------------|-------------------|
| 验证方式 | 随机采样 (N=5000) | 全空间穷举 (2^97) |
| 时间 | 秒级 | 小时级 |
| 覆盖 | 采样统计 | 100% 数学证明 |
| 用途 | 快速回归、debug | 签核级完备证明 |

两者互补：
- **Hector PROOF** → 全部输入空间覆盖，签核级别 confidence
- **Hector CEX** → 用 cosim 回放反例，定位 RTL bug
- **cosim FAIL** → RTL 有 bug，Hector 应该也能找到 CEX

## 已知问题 / 待办

详见 `temp/hector_open_issues.md`。主要待解决：

1. **HDPS 子证明配置**：fpnew_fma 内部乘法器和前导零单元的 cutpoint 信号名需确定
2. **NaN payload 规范化**：RISC-V canonical NaN vs IEEE 754 NaN payload 差异处理
3. **时序延迟精确值**：fpnew_fma 的确切延迟需要在 Hector 中验证

## 参考

- [cosim → Hector 迁移计划](../temp/cosim_to_hector_migration_plan.md)
- [DPV_Advanced 示例项目](../third_party/example/DPV_Advanced/)
- [cvfpu RTL 源码](../third_party/cvfpu/)
- [Berkeley SoftFloat 3e](../third_party/softfloat/)
