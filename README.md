# cvfpu FP32 FMA 协同验证项目

本项目对 OpenHW Group cvfpu 的 FP32 融合乘加 (FMA) 模块建立**双重验证闭环**：

```
                           输入 (a, b, c, rounding_mode)
                                      │
              ┌───────────────────────┴───────────────────────┐
              ▼                                               ▼
┌──────────────────────────┐                 ┌──────────────────────────┐
│  Cosim (仿真验证)          │                 │  Hector (形式化验证)       │
│                           │                 │                          │
│  Verilator + DPI-C        │                 │  VC Formal Hector DPV    │
│  随机/定向采样 ~5000 cases │                 │  全空间穷举 ~2^97 输入     │
│  秒级                     │                 │  小时级                   │
└──────────────────────────┘                 └──────────────────────────┘
              │                                               │
              ▼                                               ▼
     result_rtl vs result_ref                    lemma result_eq, except_eq
     status_rtl vs fflags_ref                    case split: inf/NaN/norm/dnorm
```

## 项目结构

```
cosim/
├── README.md
├── Makefile                          # cosim: Verilator 编译 + 仿真
├── run_eda.sh                        # Docker 启动脚本 (EDA 工具环境)
├── .gitignore
│
├── rtl/
│   └── fma_dut_wrapper.sv            # cosim DUT wrapper (valid/ready 接口)
├── tb/
│   ├── tb_fma_cosim.sv               # cosim testbench (FSM + DPI-C)
│   └── dpi_softfloat.sv              # DPI-C 函数声明
├── csrc/
│   ├── sim_main.cpp                  # Verilator 仿真入口
│   ├── softfloat_dpi.cpp             # DPI-C 实现 (SoftFloat golden)
│   └── softfloat_dpi.h               # DPI-C 头文件
├── tests/
│   ├── directed_cases.hex            # 定向测试用例
│   └── random_seed_list.txt          # 随机种子列表
├── logs/                             # cosim 仿真产物 (gitignored)
│
├── hector/                           # ★ Hector 形式化验证
│   ├── README.md
│   ├── run/                          # vcf 运行目录 (中间产物在此)
│   ├── spec/fma_spec.cpp             # C++ spec (SoftFloat golden)
│   ├── rtl/fma_hector_wrap.sv        # SV impl wrapper (go/valid 接口)
│   ├── tcl/command_script_fma32.tcl  # TCL 控制脚本
│   └── scripts/run_hector.sh         # 一键启动
│
├── third_party/                      # 第三方依赖 (内嵌, 含本地修改)
│   ├── README.md                     # 依赖来源与修改说明
│   ├── cvfpu/                        # cvfpu RTL (Solderpad License)
│   ├── softfloat/                    # SoftFloat 3e (BSD-like, Hector 兼容修改)
│   └── example/                      # DPV_Advanced 参考样例 (gitignored)
│
└── temp/                             # 项目文档
    ├── cosim_to_hector_migration_plan.md
    └── hector_open_issues.md
```

## 快速开始

### 环境准备

```bash
# 克隆项目后，确保依赖就位（third_party/ 已内含）
cd cosim

# 如果还需要外部依赖（cosim Makefile 仍引用 ../cvfpu 和 ../berkeley-softfloat-3）：
git clone https://github.com/openhwgroup/cvfpu ../cvfpu
git clone https://github.com/ucb-bar/berkeley-softfloat-3 ../berkeley-softfloat-3
```

### Cosim 仿真验证

```bash
make all NUM=100      # 编译 + 小规模运行
make run NUM=10000    # 大规模回归
make wave             # 查看波形 (GTKWave)
make clean            # 清理
```

### Hector 形式化验证

```bash
# Docker 环境 (宿主机)
./run_eda.sh

# 容器内
cd /home/eda
./hector/scripts/run_hector.sh
# vcf> make
# vcf> run_main
```

详见 [hector/README.md](hector/README.md)。

## 验证层次

| 层级 | 内容 | Cosim | Hector |
|------|------|-------|--------|
| Sanity | 手工用例 (1.0×2.0+3.0 等) | ✅ | — |
| Random | 随机 32-bit (正常浮点范围) | ✅ | — |
| Formal | 全空间穷举等价证明 | — | 🔄 搭建中 |
| Corner | ±0, ±∞, NaN, sNaN, subnormal | ⏳ | 🔄 case split 已覆盖 |
| Full Ops | FMSUB / FNMADD / FNMSUB | ⏳ | ⏳ |

## 核心模型

| 角色 | Cosim | Hector |
|------|-------|--------|
| RTL (DUT) | `rtl/fma_dut_wrapper.sv` → `fpnew_fma` | `hector/rtl/fma_hector_wrap.sv` → `fpnew_fma` |
| Golden | `csrc/softfloat_dpi.cpp` → SoftFloat `f32_mulAdd` | `hector/spec/fma_spec.cpp` → SoftFloat `f32_mulAdd` |
| 接口 | valid/ready 握手 | go/valid 脉冲 |
| 比较 | SV FSM 逐 case | TCL lemma 形式化断言 |

## 依赖

| 工具 | 用途 | 版本 |
|------|------|------|
| Verilator | cosim 仿真 | >= 5.0 |
| GCC / Clang | C++ 编译 | C++11 |
| VC Formal (vcf/svi) | Hector 形式化验证 | W-2024.09-SP1 |
| Berkeley SoftFloat | Golden reference | 3e |
| GTKWave | 波形查看 (可选) | — |

## 参考

- [cosim → Hector 迁移计划](temp/cosim_to_hector_migration_plan.md)
- [Hector 开放问题](temp/hector_open_issues.md)
- [第三方依赖说明](third_party/README.md)
- [cvfpu (OpenHW Group)](https://github.com/openhwgroup/cvfpu)
- [Berkeley SoftFloat](https://github.com/ucb-bar/berkeley-softfloat-3)
