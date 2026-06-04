# Third-Party Dependencies

This directory contains third-party open source components used by the cosim
and Hector verification flows.

## cvfpu (OpenHW Group)

- **Source**: https://github.com/openhwgroup/cvfpu
- **License**: Solderpad Hardware License v0.51 (Apache 2.0 compatible)
- **Files**: `cvfpu/` — only the FP32 FMA subset (fpnew_fma, fpnew_pkg, fpnew_classifier, fpnew_rounding, common_cells helpers)
- **Modifications**: None. Used as-is.

## SoftFloat (Berkeley)

- **Source**: https://github.com/ucb-bar/berkeley-softfloat-3
- **Version**: Release 3e
- **License**: UC Berkeley (BSD-like, see COPYING.txt)
- **Files**: `softfloat/` — only the source files needed for FP32 f32_mulAdd (not the full library)
- **Modifications**: Two local patches for Hector DPV compatibility:
  - `source/RISCV/platform.h` — Removed GCC builtins (SOFTFLOAT_BUILTIN_CLZ, SOFTFLOAT_INTRINSIC_INT128, opts-GCC.h) for Hector cppan pure-C compatibility
  - `include/softfloat.h` — Changed `typedef enum {...} exceptionFlag_t` to anonymous `enum {...}` for C++ compatibility with Hector's cppan
  - These changes do NOT affect functional behavior of SoftFloat.

## Example Projects (Synopsys)

- **Source**: VC Formal DPV_Advanced tutorial examples (W-2024.09-SP1)
- **Location**: `example/` — gitignored, not distributed (reference only)
