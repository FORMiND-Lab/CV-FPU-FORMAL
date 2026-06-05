//============================================================================
// fma_golden_dpi.cpp — FP32 FMA DPI-C Golden Model Implementation
//
// Port names aligned with hector/spec/fma_spec.cpp:
//   multiplier, multiplicand, addend, rounding_mode, result, exceptions
//
// Uses Berkeley SoftFloat f32_mulAdd as the golden reference.
// Supports all 4 FMA operation variants via the `op` parameter.
//============================================================================

extern "C" {
#include "softfloat.h"
}
#include "fma_golden_dpi.h"

#include <cstdio>
#include <cstring>

//============================================================================
// Helpers
//============================================================================

// Flip sign bit of float32_t
static inline float32_t f32_negate(float32_t f) {
    f.v ^= 0x80000000u;
    return f;
}

// Convert SoftFloat exception flags to RTL format
// RTL status_t = {NV, DZ, OF, UF, NX} (5 bits)
// SoftFloat:  inexact=1, underflow=2, overflow=4, infinite=8, invalid=16
// NOTE: softfloat_flag_infinite is intentionally NOT mapped — FMA never sets
// DZ (divide-by-zero). Infinite results from FMA are caused by overflow (OF+NX)
// or invalid operations (NV), both already handled.
static unsigned int softfloat_to_rtl_exceptions(unsigned char sf_flags) {
    unsigned int out = 0;
    if (sf_flags & softfloat_flag_invalid)   out |= (1 << 4);  // NV
    if (sf_flags & softfloat_flag_overflow)  out |= (1 << 2);  // OF
    if (sf_flags & softfloat_flag_underflow) out |= (1 << 1);  // UF
    if (sf_flags & softfloat_flag_inexact)   out |= (1 << 0);  // NX
    return out;
}

// Convert RTL rounding mode to SoftFloat rounding mode
// RISC-V: RNE=000, RTZ=001, RDN=010, RUP=011, RMM=100
static unsigned char rtl_to_sf_rm(unsigned int rm) {
    switch (rm) {
        case 0: return softfloat_round_near_even;     // RNE
        case 1: return softfloat_round_minMag;        // RTZ
        case 2: return softfloat_round_min;           // RDN
        case 3: return softfloat_round_max;           // RUP
        case 4: return softfloat_round_near_maxMag;   // RMM
        default: return softfloat_round_near_even;    // default RNE
    }
}

//============================================================================
// DPI-C: dpi_fma_golden — unified FMA golden model
//
// Port names match hector/spec/fma_spec.cpp:
//   multiplier, multiplicand, addend, rounding_mode, result, exceptions
//
// op selects the FMA variant:
//   0 = FMADD  : result = a * b + c
//   1 = FMSUB  : result = a * b - c
//   2 = FNMADD : result = -(a * b) + c
//   3 = FNMSUB : result = -(a * b) - c
//============================================================================
void dpi_fma_golden(
    int             enable,
    unsigned int    multiplier,
    unsigned int    multiplicand,
    unsigned int    addend,
    unsigned int    rounding_mode,
    unsigned int    op,
    unsigned int*   result,
    unsigned int*   exceptions
) {
    if (!enable) {
        *result     = 0;
        *exceptions = 0;
        return;
    }

    // Clear SoftFloat exception flags and set rounding mode
    softfloat_exceptionFlags = 0;
    softfloat_roundingMode   = rtl_to_sf_rm(rounding_mode);

    float32_t fa = {.v = multiplier};
    float32_t fb = {.v = multiplicand};
    float32_t fc = {.v = addend};
    float32_t fres;

    switch (op) {
        case 0: // FMADD:  a * b + c
            fres = f32_mulAdd(fa, fb, fc);
            break;
        case 1: // FMSUB:  a * b - c
            fres = f32_mulAdd(fa, fb, f32_negate(fc));
            break;
        case 2: // FNMADD: -(a * b) + c
            fres = f32_mulAdd(f32_negate(fa), fb, fc);
            break;
        case 3: // FNMSUB: -(a * b) - c
            fres = f32_mulAdd(f32_negate(fa), fb, f32_negate(fc));
            break;
        default: // fallback to FMADD
            fres = f32_mulAdd(fa, fb, fc);
            break;
    }

    *exceptions = softfloat_to_rtl_exceptions(softfloat_exceptionFlags);
    *result     = fres.v;
}
