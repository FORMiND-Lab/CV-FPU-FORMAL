//============================================================================
// fma_golden_dpi.cpp — FP32 ADDMUL DPI-C Golden Model Implementation
//
// Port names aligned with formal/spec/fma_spec_wrap_fp32_fmad.cpp:
//   multiplier, multiplicand, addend, rounding_mode, result, exceptions
//
// op_i / op_mod_i encoding matches fpnew_pkg / fpnew_fma RTL:
//   ┌────────┬──────────┬─────────────┬──────────────────────────┐
//   │ op_i   │ op_mod_i │ Operation   │ Implementation           │
//   ├────────┼──────────┼─────────────┼──────────────────────────┤
//   │ FMADD  │ 0        │ FMADD       │ f32_mulAdd(a, b, c)      │
//   │ FMADD  │ 1        │ FMSUB       │ f32_mulAdd(a, b, neg(c)) │
//   │ FNMSUB │ 0        │ FNMSUB      │ f32_mulAdd(neg(a),b,c)   │
//   │ FNMSUB │ 1        │ FNMADD      │ f32_mulAdd(neg(a),b,neg(c))│
//   │ ADD    │ 0        │ ADD         │ f32_mulAdd(1.0, b, c)    │
//   │ ADD    │ 1        │ SUB         │ f32_mulAdd(1.0, b, neg(c))│
//   │ MUL    │ x        │ MUL         │ f32_mulAdd(a, b, 0)      │
//   │ ADDS   │ x        │ ADDS        │ f32_mulAdd(1.0, b, c)    │
//   └────────┴──────────┴─────────────┴──────────────────────────┘
//============================================================================

extern "C" {
#include "softfloat.h"
}
#include "fma_dpi.h"

//============================================================================
// Helpers
//============================================================================

static inline float32_t f32_negate(float32_t f) {
    f.v ^= 0x80000000u;
    return f;
}

static inline float32_t f32_abs(float32_t f) {
    f.v &= ~0x80000000u;  // force sign = 0 (positive)
    return f;
}

// Convert SoftFloat exception flags to RTL format {NV, DZ, OF, UF, NX}
// NOTE: softfloat_flag_infinite is intentionally NOT mapped — FMA never sets DZ.
static unsigned int softfloat_to_rtl_exceptions(unsigned char sf_flags) {
    unsigned int out = 0;
    if (sf_flags & softfloat_flag_invalid)   out |= (1 << 4);  // NV
    if (sf_flags & softfloat_flag_overflow)  out |= (1 << 2);  // OF
    if (sf_flags & softfloat_flag_underflow) out |= (1 << 1);  // UF
    if (sf_flags & softfloat_flag_inexact)   out |= (1 << 0);  // NX
    return out;
}

// RISC-V → SoftFloat rounding mode (1:1)
static unsigned char rtl_to_sf_rm(unsigned int rm) {
    switch (rm) {
        case 0: return softfloat_round_near_even;
        case 1: return softfloat_round_minMag;
        case 2: return softfloat_round_min;
        case 3: return softfloat_round_max;
        case 4: return softfloat_round_near_maxMag;
        default: return softfloat_round_near_even;
    }
}

//============================================================================
// dpi_fma_golden — ADDMUL golden model (fpnew_pkg encoding)
//============================================================================
void dpi_fma_golden(
    int             enable,
    unsigned int    multiplier,
    unsigned int    multiplicand,
    unsigned int    addend,
    unsigned int    rounding_mode,
    unsigned int    op_i,
    unsigned int    op_mod_i,
    unsigned int*   result,
    unsigned int*   exceptions
) {
    if (!enable) {
        *result     = 0;
        *exceptions = 0;
        return;
    }

    softfloat_exceptionFlags = 0;
    softfloat_roundingMode   = rtl_to_sf_rm(rounding_mode);

    float32_t fa = {.v = multiplier};
    float32_t fb = {.v = multiplicand};
    float32_t fc = {.v = addend};
    float32_t fres;

    switch (op_i) {
        // ---- FMADD, FMSUB ----
        case OP_FMADD:
            if (op_mod_i == 0)
                fres = f32_mulAdd(fa, fb, fc);            // FMADD:  a*b + c
            else
                fres = f32_mulAdd(fa, fb, f32_negate(fc)); // FMSUB:  a*b - c
            break;

        // ---- FNMSUB, FNMADD ----
        case OP_FNMSUB:
            if (op_mod_i == 0)
                fres = f32_mulAdd(f32_negate(fa), fb, fc);      // FNMSUB: -(a*b)+c
            else
                fres = f32_mulAdd(f32_negate(fa), fb, f32_negate(fc)); // FNMADD: -(a*b)-c
            break;

        // ---- ADD, SUB ----
        case OP_ADD:
            fa.v = 0x3F800000;  // +1.0
            if (op_mod_i == 0)
                fres = f32_mulAdd(fa, fb, fc);            // ADD:  1.0*b + c = b + c
            else
                fres = f32_mulAdd(fa, fb, f32_negate(fc)); // SUB:  1.0*b - c = b - c
            break;

        // ---- MUL ----
        case OP_MUL: {
            // RTL sets C = ±0 (sign matches op_mod_i if non-zero)
            // Use +0.0 for op_mod=0, -0.0 for op_mod=1 (matches fpnew_fma behavior)
            float32_t zero = {.v = op_mod_i ? 0x80000000u : 0x00000000u};
            fres = f32_mulAdd(fa, fb, zero);              // MUL:  a*b + 0
            break;
        }

        // ---- ADDS (same as ADD) ----
        case OP_ADDS:
            fa.v = 0x3F800000;  // +1.0
            if (op_mod_i == 0)
                fres = f32_mulAdd(fa, fb, fc);
            else
                fres = f32_mulAdd(fa, fb, f32_negate(fc));
            break;

        // ---- Unknown → fallback to FMADD ----
        default:
            fres = f32_mulAdd(fa, fb, fc);
            break;
    }

    *exceptions = softfloat_to_rtl_exceptions(softfloat_exceptionFlags);
    *result     = fres.v;
}
