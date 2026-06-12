---
name: evo-hector-verification
description: 形式化验证专家：基于hector (vcf DPV) 对演进后的RTL代码进行C-RTL等价性验证，所有路径直接从TCL脚本解析，无需手动指定RTL目录。
---

# evo-hector-verification SKILL

## Overview

`evo-hector-verification` 是 **RTL自动演进任务 (EvoRTL)** 中的 **验证者 (Verifier)**，使用 **hector (vcf DPV)** 作为验证后端。

核心设计原则：**所有路径从 TCL 脚本自动解析，无需手动指定 RTL 目录。**

TCL 脚本已经包含了所有路径信息（spec 文件、RTL 文件、incdir），`analyze_hector.py` 直接从 TCL 解析，`run_hector.py` 使用原始 TCL 执行，路径由 hector 自己解析。

## Role Definition

你是一位 **自动化形式化验证执行者**，专注于基于 hector (vcf DPV) 的 C-RTL 等价性验证。

- **路径解析专家**：所有路径从 TCL 脚本自动提取，无需手动维护路径列表。
- **客观公正**：验证结果完全依据 `listproofs` 输出。
- **故障排查**：遇到执行问题能分析报错并修复。

## Expert Knowledge & Guidelines

### 1. 验证结果判定

| 输出特征 | 判定状态 |
|---------|---------|
| 所有 `Proof X: PROVEN` | `VERIFICATION SUCCESSFUL` |
| 任意 `Proof X: FAILED` | `VERIFICATION FAILED` |
| 进程被 timeout 终止 | `EXECUTION TIMEOUT` |
| 其他 Error 或无 proof 输出 | `OTHER ERROR` |

### 2. 执行方式

通过 `docker exec eda-hector` 在容器内执行 `vcf`，宿主机路径自动转换为 docker 内部路径：

- `/home/zhangyang/workspace/eda/` → `/home/eda/`
- `/home/zhangyang/workspace/c_rtl/` → `/home/c_rtl/`

### 3. 路径解析基准（关键）

TCL 脚本里的相对路径（如 `../../rtl/`、`../../../third_party/`）是 hector 在 **运行目录**（vcf 的 cwd）解析的，而非相对 TCL 文件自身目录。也就是说 TCL 所在位置与路径解析无关，vcf 的 cwd 才是解析基准。

因此 `run_base_dir` 参数必须与 TCL 设计的目录深度匹配。

本例中 TCL 的目录深度设计：
```
cosim_ref/                         # TCL 中 ../../.. 到达这里
├── formal/
│   ├── tcl/xxx.tcl               # TCL 文件位置（不影响路径解析）
│   ├── run/<case>/                # 运行目录 → vcf cwd
│   │   └── host.qsub
│   ├── rtl/                       # ../../rtl/ 从这里解析
│   └── spec/                      # ../../spec/ 从这里解析
├── third_party/                   # ../../../third_party/ 从这里解析
│   ├── cvfpu/
│   └── softfloat/
```

如果 TCL 是为 `formal/run/run_add16/` 深度设计的，则：
```
run_base_dir: "/home/zhangyang/workspace/eda/cosim_ref/formal/run"
```
这样每个 case 的 run 目录为 `formal/run/<case_name>/`，TCL 相对路径正确匹配。

注意：`analyze_hector.py` 的 `resolve_path()` 将相对路径相对于 **TCL 文件目录** 解析（而非运行目录），因此 `analysis.json` 中的 `rtl_files`/`spec_files`/`incdirs` 路径可能不正确。但这不影响验证结果——`run_hector.py` 直接使用原始 TCL，hector 在正确的 cwd 下自行解析路径。

## Execution Policy: Stateless & Fresh Start

1. 将本次执行视为全新会话，不参考历史状态。
2. 必须重新读取所有输入文件。
3. 禁止自动修改 C++/RTL 代码。

## Inputs

| Input | Type | Description | Example |
|-------|------|-------------|---------|
| `verification_environment` | list[string] | hector TCL 脚本文件列表（宿主机绝对路径） | `["/home/zhangyang/workspace/eda/cosim_ref/formal/tcl/command_script_add16.tcl"]` |
| `timeout` | int | 单次验证超时时间（秒） | `3600` |
| `thread` | int | 并行 case 数 | `1` |
| `workers` | int | hector 并行 worker 数 | `16` |
| `log_dir` | string | 验证日志输出目录（宿主机路径） | `"/home/zhangyang/workspace/eda/cosim_ref/formal/run/test_skill_add16"` |
| `run_base_dir` | string | vcf 运行目录的父目录，用于匹配 TCL 相对路径深度（可选） | `"/home/zhangyang/workspace/eda/cosim_ref/formal/run"` |

> `origin_rtl_dir` 不再需要，路径从 TCL 自动解析。

## Outputs

```
log_dir/
├── hector_log/
│   ├── <case>/              # vcf 运行目录（含 host.qsub、vcst_rtdb/）
│   └── hector_<case>.log    # 结构化执行日志
├── analysis.json            # TCL 解析结果
└── report.md                # 验证结果汇总
```

## Workflow

### Step 1: 环境校验

1. 验证 `verification_environment` 中每个 TCL 文件存在且可读
2. 验证 Docker 容器 `eda-hector` 正在运行（`docker ps --filter name=eda-hector`）
3. 创建 `log_dir` 和 `log_dir/hector_log`
4. 任一检查失败 → 输出错误并 **TERMINATE**

> 不需要逐个验证 TCL 中引用的文件。hector 在运行时从正确的 cwd 自己解析相对路径。

### Step 2: 解析 TCL 路径

```bash
python3 <当前skill存放目录>/scripts/analyze_hector.py \
    -t <tcl_file1> [<tcl_file2> ...] \
    -l <log_dir>
```

检查 `log_dir/analysis.json` 是否生成，确认 `top_impl`、`rtl_files`、`spec_files` 字段正确。

### Step 3: 验证执行

```bash
python3 <当前skill存放目录>/scripts/run_hector.py \
    --timeout <timeout> \
    --thread <thread> \
    --workers <workers> \
    --info_json <log_dir/analysis.json> \
    --log_dir <log_dir> \
    [--run_base_dir <run_base_dir>]
```

等待完成，输出 `log_dir/report.md` 路径。

## Usage Example

```
调用 evo-hector-verification SKILL
verification_environment: ["/home/zhangyang/workspace/eda/cosim_ref/formal/tcl/command_script_add16.tcl"]
timeout:                  3600
thread:                   1
workers:                  16
log_dir:                  "/home/zhangyang/workspace/eda/cosim_ref/formal/run/test_skill_add16"
run_base_dir:             "/home/zhangyang/workspace/eda/cosim_ref/formal/run"
```