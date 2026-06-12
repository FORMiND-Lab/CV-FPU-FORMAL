//============================================================================
// fma_dpi_fp48.cpp — FP48 ADDMUL DPI-C Golden Model (STUB)
//
// Currently returns result=0, exceptions=0 for all inputs.
//
// TODO: Replace with real FP48 (E11M36, bias=1023) golden model:
//   Option A: Use SoftFloat f64 with truncation to 36-bit mantissa
//   Option B: Use MPFR (mpfr_fma) with custom 48-bit rounding
//   Option C: Hand-roll FP48 emulation using uint64_t bit manipulation
//
// FP48 encoding in 64-bit container (RISC-V NaN-boxed):
//   bits [63:48] = 16'hffff  (NaN-box)
//   bits [47:0]  = FP48 payload: {sign[47], exp[46:36], mant[35:0]}
//   EXP_BITS=11, MAN_BITS=36, BIAS=1023
//============================================================================

#include "fma_dpi_fp48.h"

// Stub: always returns 0 (quiet positive zero in FP48 NaN-boxed format)
void dpi_fma_golden_fp48(
    int              enable,
    unsigned long long multiplier,
    unsigned long long multiplicand,
    unsigned long long addend,
    unsigned int     rounding_mode,
    unsigned int     op_i,
    unsigned int     op_mod_i,
    unsigned long long* result,
    unsigned int*    exceptions
) {
    // Suppress unused-parameter warnings
    (void)multiplier;
    (void)multiplicand;
    (void)addend;
    (void)rounding_mode;
    (void)op_i;
    (void)op_mod_i;

    if (!enable) {
        *result     = 0;
        *exceptions = 0;
        return;
    }

    // STUB: return NaN-boxed +0.0, no exceptions
    // +0.0 in FP48: sign=0, exp=0, mant=0 → payload = 48'h000000000000
    // NaN-boxed: {16'hffff, 48'h000000000000}
    *result     = 0xffff000000000000ULL;
    *exceptions = 0;
}
