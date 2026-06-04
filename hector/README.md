# Hector DPV — FP32 FMA 形式化等价验证

> 全空间穷举证明：cvfpu fpnew_fma (RTL) == Berkeley SoftFloat f32_mulAdd (C)

## 快速开始

```bash
# 0. 启动 EDA Docker 容器（如需要，在宿主机 cosim/ 目录下）
./run_eda.sh

# 1. 容器内，从项目根目录运行
cd /home/eda
./hector/scripts/run_hector.sh

# 2. 在 vcf> 提示符下
vcf> make        # 编译 spec + impl, compose
vcf> run_main    # 启动证明（case split → parallel solve）
```

`run_hector.sh` 自动 `cd hector/run/` 后调用 `vcf`，所有中间文件（`vcst_rtdb/`、`vcf.log` 等）都留在 `hector/run/` 中，不污染项目根目录。

## 目录结构

```
hector/
├── README.md
├── run/                                # vcf 运行目录（所有中间产物在这里）
│   └── .gitkeep
├── spec/
│   └── fma_spec.cpp                    # C++ Hector spec (SoftFloat golden)
├── rtl/
│   └── fma_hector_wrap.sv              # SV wrapper (go/valid 接口)
├── tcl/
│   └── command_script_fma32.tcl        # TCL 控制脚本
└── scripts/
    └── run_hector.sh                   # 一键启动脚本
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
              │  case split: inf/NaN/norm/dnorm   │
              └──────────────────────────────────┘
```

## 验证流程

| 步骤 | 命令 | 说明 |
|------|------|------|
| 1 | `make` 或 `compile_spec` | cppan 编译 C++ spec + SoftFloat 源文件 |
| 2 | `make` 或 `compile_impl` | vcs 编译 SV RTL (fpnew_fma + wrapper) |
| 3 | `make` 或 `compose` | 建立 spec ↔ impl 的 formal model |
| 4 | `run_main` | 穷举证明 (case split → parallel solve) |

## 配置

### 组合逻辑 vs 流水线

修改 `hector/rtl/fma_hector_wrap.sv`：

```systemverilog
parameter int unsigned NUM_PIPE_REGS = 0   // 当前：最小延迟（1 cycle）
parameter int unsigned NUM_PIPE_REGS = 1   // 1 级流水线
```

然后在 `command_script_fma32.tcl` 的 `ual_main` 中调整 lemma 的 phase：

```tcl
# NUM_PIPE_REGS=0: impl 比 spec 晚 1 拍
lemma result_eq = spec.result(1) == impl.result(2)

# NUM_PIPE_REGS=1: impl 晚 2 拍
lemma result_eq = spec.result(1) == impl.result(3)
```

### 舍入模式

RISC-V 定义 5 种舍入模式，通过 `assume` 约束范围：

| 编码 | 名称 | 说明 |
|------|------|------|
| 000 | RNE | Round to Nearest, ties to Even |
| 001 | RTZ | Round towards Zero |
| 010 | RDN | Round Down (towards −∞) |
| 011 | RUP | Round Up (towards +∞) |
| 100 | RMM | Round to Nearest, ties to Max Magnitude |

## 与 cosim 仿真的关系

| 维度 | cosim (Verilator) | Hector (形式化) |
|------|-------------------|-------------------|
| 验证方式 | 随机采样 (N=5000) | 全空间穷举 (~2^97) |
| 耗时 | 秒级 | 小时级 |
| 覆盖度 | 统计采样 | 100% 数学证明 |
| 用途 | 快速回归、debug | 签核级完备证明 |

两者互补：Hector 出 CEX → cosim 回放反例定位 bug；cosim 出 FAIL → RTL 有 bug，Hector 也应能找到。

## 已知问题

详见 `../temp/hector_open_issues.md`。主要待解决：

1. **HDPS 子证明**：fpnew_fma 内部乘法器和前导零单元的 cutpoint 信号名需确定
2. **NaN payload**：RISC-V canonical NaN vs IEEE 754 NaN payload 差异
3. **时序延迟**：fpnew_fma 确切的 latency cycle 数需验证

## 参考

- [cosim → Hector 迁移计划](../temp/cosim_to_hector_migration_plan.md)
- [Hector 开放问题](../temp/hector_open_issues.md)
- [DPV_Advanced 示例](../third_party/example/DPV_Advanced/)
- [第三方依赖说明](../third_party/README.md)
