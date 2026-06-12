# 第三方依赖说明

本目录包含 cosim 仿真与 Hector 形式化验证流程使用的第三方开源组件。
每个组件均与上游源码做过 diff 对比，修改情况记录如下。

## 上游参考

| 组件 | 上游仓库 | 引入方式 |
|------|----------|----------|
| cvfpu     | https://github.com/openhwgroup/cvfpu | **git submodule** |
| SoftFloat | `/home/shibo/desktop/test_cv_fpv/berkeley-softfloat-3` | vendored copy（部分文件有修改） |

---

## cvfpu (OpenHW Group) — git submodule

- **来源**：https://github.com/openhwgroup/cvfpu
- **许可**：Solderpad Hardware License v0.51（Apache 2.0 兼容）
- **引入方式**：**git submodule**，固定于 commit `8a18a8b468039c80f3988687009984f6299eb4d8`
- **上游目录结构**：所有 RTL 源文件位于 `src/` 子目录下（`src/fpnew_pkg.sv`、`src/fpnew_fma.sv` 等）
- **修改**：**无。** 所有文件与上游逐字节一致，submodule 检出后直接引用，不经过任何本地修改。

### 使用的文件（submodule 内路径）

TCL 与 Makefile 中引用路径均带 `src/` 前缀，与上游目录结构一致：

| 文件（相对于 `third_party/cvfpu/`） | 用途 |
|------|------|
| `src/fpnew_pkg.sv` | FP 格式参数定义、operation_e 枚举 |
| `src/fpnew_fma.sv` | FMA 运算核心（乘法器 + 加法器 + 舍入） |
| `src/fpnew_classifier.sv` | 操作数分类（normal/subnormal/zero/NaN/Inf） |
| `src/fpnew_rounding.sv` | IEEE 754 舍入逻辑 |
| `src/common_cells/src/cf_math_pkg.sv` | 数学函数包 |
| `src/common_cells/src/lzc.sv` | 前导零计数器 |
| `src/common_cells/src/rr_arb_tree.sv` | Round-Robin 仲裁树 |
| `src/common_cells/include/common_cells/registers.svh` | 寄存器宏 |

### submodule 初始化

```bash
git submodule update --init --recursive
```

TCL 脚本运行时，VCS 编译器直接从 submodule 工作树中读取 `src/` 下的源文件，路径为：

```
../../../third_party/cvfpu/src/fpnew_pkg.sv
../../../third_party/cvfpu/src/fpnew_fma.sv
../../../third_party/cvfpu/src/common_cells/...
```

---

## SoftFloat (Berkeley)

- **来源**：https://github.com/ucb-bar/berkeley-softfloat-3
- **版本**：Release 3e
- **许可**：UC Berkeley（BSD 风格，详见各源文件头部）
- **包含文件**：FP32 `f32_mulAdd` / `f32_add` / `f32_sub` / `f32_mul` 及 FP16 `f16_mulAdd` / `f16_add` / `f16_sub` / `f16_mul` 所需文件（非完整库）

### 修改总览：2 个文件修改 + 1 个文件新建 + 5 个 FP16 文件新增 + 5 个 FP32 文件新增 + 其余未改动

所有修改均为 **Hector cppan 兼容性适配**，不影响 SoftFloat 的功能行为或数值结果。

#### 修改 1：`source/RISCV/platform.h` — 新建文件（禁用 GCC 内建函数）

此文件在上游**不存在**（上游仅将 `platform.h` 放在 `build/<target>/` 目录下）。
它基于 `build/Linux-RISCV64-GCC/platform.h` 创建，关键差异如下：

```diff
- #define SOFTFLOAT_BUILTIN_CLZ 1
- #define SOFTFLOAT_INTRINSIC_INT128 1
- #include "opts-GCC.h"
+ // Hector 兼容性：不使用 GCC 内建函数/内置类型。
+ // 故意不定义 SOFTFLOAT_BUILTIN_CLZ 和 SOFTFLOAT_INTRINSIC_INT128，
+ // 使 SoftFloat 回退到纯 C 实现：
+ //   - s_countLeadingZeros*() 替代 __builtin_clz*
+ //   - 多精度 C 函数替代 __int128 运算
+ // "opts-GCC.h" 故意不包含。
+ // #define SOFTFLOAT_BUILTIN_CLZ 1
+ // #define SOFTFLOAT_INTRINSIC_INT128 1
+ // #include "opts-GCC.h"
```

**原因**：Hector 的 `cppan` 是纯 C 编译器，不支持 GCC 的 `__builtin_clz*` 和 `__int128`。禁用这些宏后，SoftFloat 使用自身的可移植 C 实现，在 cppan 下可正常编译。

#### 修改 2：`include/softfloat.h` — 匿名 enum（C++ 兼容）

```diff
- typedef enum {
+ // 移除 exceptionFlag_t typedef，以兼容 Hector/cppan 的 C++ 编译。
+ // enum 值保留为匿名 enum 成员，功能不变。
+ enum {
      softfloat_flag_inexact   = 1,
      ...
      softfloat_flag_invalid   = 16
- } exceptionFlag_t;
+ };
```

**原因**：Hector 的 `cppan` 处理 C++ spec 模型。C 风格的 `typedef enum` 语法与 C++ 的隐式类型转换规则冲突。改为匿名 `enum` 可避免编译错误，所有枚举值不变，功能完全等价。

### 文件审计（diff 对比上游 `berkeley-softfloat-3/source/`）

#### FP32 文件

| 文件 | 状态 |
|------|------|
| `source/f32_mulAdd.c` | 一致（上游 FP32 FMA，Cosim DPI 使用） |
| `source/s_mulAddF32.c` | 一致 |
| `source/f32_add.c` | 一致（上游 FP32 加法，Hector 专用） |
| `source/s_addMagsF32.c` | 一致 |
| `source/f32_sub.c` | 一致（上游 FP32 减法，Hector 专用） |
| `source/s_subMagsF32.c` | 一致 |
| `source/f32_mul.c` | 一致（上游 FP32 乘法，Hector 专用） |
| `source/s_roundPackToF32.c` | 一致 |
| `source/s_normRoundPackToF32.c` | 一致 |
| `source/s_normSubnormalF32Sig.c` | 一致 |
| `source/RISCV/s_propagateNaNF32UI.c` | 一致 |

> `f32_add.c`、`f32_sub.c`、`f32_mul.c` 及其内部辅助文件为 Hector 形式化验证专用（统一 FP32 spec 需要）。
> Cosim DPI golden model 通过 `f32_mulAdd` + 操作数符号翻转实现全部运算，不需要这些文件。

#### FP16 文件（Hector DPV 新增）

| 文件 | 状态 |
|------|------|
| `source/f16_mulAdd.c` | 一致（上游 FP16 FMA） |
| `source/s_mulAddF16.c` | 一致 |
| `source/f16_add.c` | 一致（上游 FP16 加法） |
| `source/s_addMagsF16.c` | 一致 |
| `source/f16_sub.c` | 一致（上游 FP16 减法） |
| `source/s_subMagsF16.c` | 一致 |
| `source/f16_mul.c` | 一致（上游 FP16 乘法） |
| `source/s_roundPackToF16.c` | 一致 |
| `source/s_normRoundPackToF16.c` | 一致 |
| `source/s_normSubnormalF16Sig.c` | 一致 |
| `source/RISCV/s_propagateNaNF16UI.c` | 一致 |

#### 共享辅助文件（FP32 + FP16 共用）

| 文件 | 状态 |
|------|------|
| `source/s_shortShiftRightJam64.c` | 一致 |
| `source/s_shiftRightJam32.c` | 一致 |
| `source/s_shiftRightJam64.c` | 一致 |
| `source/s_countLeadingZeros64.c` | 一致 |
| `source/s_countLeadingZeros32.c` | 一致 |
| `source/s_countLeadingZeros16.c` | 一致 |
| `source/s_countLeadingZeros8.c` | 一致 |
| `source/softfloat_state.c` | 一致 |
| `source/RISCV/softfloat_raiseFlags.c` | 一致 |

#### 头文件

| 文件 | 状态 |
|------|------|
| `include/softfloat.h` | **已修改**（见修改 2） |
| `source/RISCV/platform.h` | **新建**（见修改 1） |
| `include/internals.h` | 一致 |
| `include/opts-GCC.h` | 一致（存在但 `platform.h` 中未引用） |
| `include/primitives.h` | 一致 |
| `include/primitiveTypes.h` | 一致 |
| `include/softfloat_types.h` | 一致 |
| `source/RISCV/specialize.h` | 一致 |

### 编译产物溯源

`softfloat/` 目录下存在两个 `.a` 文件，用途不同：

| 文件 | 大小 | 对象数 | 来源 | Makefile 是否使用 |
|------|------|--------|------|-------------------|
| `build/libsoftfloat.a` | 23 KB | 14 | `make` 从本地修改后的源码编译 | ✅ 是 (`SOFTFLOAT_LIB`) |
| `lib/softfloat.a` | 528 KB | 309 | 上游 `build/Linux-x86_64-GCC/softfloat.a` 的完整副本 | ❌ 否 |

编译时，Makefile 通过 `-I` 指定了本地 include 路径，确保 `.o` 文件使用的是修改后的头文件：

```
-I softfloat/include/            →  include/softfloat.h（匿名 enum 修改版）
-I softfloat/source/RISCV/       →  source/RISCV/platform.h（禁用 GCC 内建函数版）
```

每个 `.c` 文件顶部都有 `#include "platform.h"`，编译器在 `source/RISCV/` 下找到的是 cosim 的**修改版** `platform.h`，而非上游的 GCC 版本。

---

## 示例项目 (Synopsys)

- **来源**：VC Formal DPV_Advanced 教程示例（W-2024.09-SP1）
- **位置**：`example/` — gitignored，仅供参考，不随仓库分发
