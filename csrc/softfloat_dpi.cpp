//============================================================================
// softfloat_dpi.cpp — SoftFloat DPI-C 实现
// 调用 Berkeley SoftFloat 的 f32_mulAdd 实现 FP32 FMA golden model
//============================================================================

extern "C" {
#include "softfloat.h"
}
#include "softfloat_dpi.h"

#include <cstdio>
#include <cstring>

// Helper: flip sign bit of float32_t (SoftFloat has no f32_neg)
static inline float32_t f32_negate(float32_t f) {
    f.v ^= 0x80000000u;
    return f;
}

// Helper: convert SoftFloat exception flags to RTL format
// RTL status_t = {NV, DZ, OF, UF, NX} (5 bits)
// SoftFloat:  inexact=1, underflow=2, overflow=4, infinite=8, invalid=16
// NOTE: softfloat_flag_infinite is intentionally NOT mapped — FMA never sets DZ
// (divide-by-zero), and infinite results from FMA are caused by overflow (OF+NX)
// or invalid operations (NV), both already handled.
static std::uint32_t softfloat_to_rtl_flags(std::uint_fast8_t sf_flags) {
    std::uint32_t out = 0;
    if (sf_flags & softfloat_flag_invalid)   out |= (1 << 4);  // NV
    if (sf_flags & softfloat_flag_overflow)  out |= (1 << 2);  // OF
    if (sf_flags & softfloat_flag_underflow) out |= (1 << 1);  // UF
    if (sf_flags & softfloat_flag_inexact)   out |= (1 << 0);  // NX
    return out;
}

// Helper: convert RTL rounding mode to SoftFloat rounding mode
// RISC-V: RNE=000, RTZ=001, RDN=010, RUP=011, RMM=100, DYN=111
static std::uint_fast8_t rtl_to_sf_rm(std::uint32_t rm) {
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
// DPI-C: dpi_fmadd_s — result = a * b + c
//============================================================================
void dpi_fmadd_s(
    int             enable,
    std::uint32_t   a,
    std::uint32_t   b,
    std::uint32_t   c,
    std::uint32_t   rm,
    std::uint32_t*  result,
    std::uint32_t*  fflags
) {
    if (!enable) {
        *result = 0;
        *fflags = 0;
        return;
    }

    // Clear SoftFloat exception flags and set rounding mode
    softfloat_exceptionFlags = 0;
    softfloat_roundingMode   = rtl_to_sf_rm(rm);  // global, not per-call argument

    float32_t fa  = {.v = a};
    float32_t fb  = {.v = b};
    float32_t fc  = {.v = c};

    float32_t fres = f32_mulAdd(fa, fb, fc);

    *fflags = softfloat_to_rtl_flags(softfloat_exceptionFlags);
    *result = fres.v;
}

//============================================================================
// DPI-C: dpi_fmsub_s — result = a * b - c
//============================================================================
void dpi_fmsub_s(
    int             enable,
    std::uint32_t   a,
    std::uint32_t   b,
    std::uint32_t   c,
    std::uint32_t   rm,
    std::uint32_t*  result,
    std::uint32_t*  fflags
) {
    if (!enable) {
        *result = 0;
        *fflags = 0;
        return;
    }

    softfloat_exceptionFlags = 0;
    softfloat_roundingMode   = rtl_to_sf_rm(rm);

    float32_t fa  = {.v = a};
    float32_t fb  = {.v = b};
    float32_t f_c = {.v = c};
    float32_t fnc = f32_negate(f_c);  // fmsub: negate c

    float32_t fres = f32_mulAdd(fa, fb, fnc);

    *fflags = softfloat_to_rtl_flags(softfloat_exceptionFlags);
    *result = fres.v;
}

//============================================================================
// DPI-C: dpi_fnmadd_s — result = -(a * b) + c
//============================================================================
void dpi_fnmadd_s(
    int             enable,
    std::uint32_t   a,
    std::uint32_t   b,
    std::uint32_t   c,
    std::uint32_t   rm,
    std::uint32_t*  result,
    std::uint32_t*  fflags
) {
    if (!enable) {
        *result = 0;
        *fflags = 0;
        return;
    }

    softfloat_exceptionFlags = 0;
    softfloat_roundingMode   = rtl_to_sf_rm(rm);

    float32_t fa  = {.v = a};
    float32_t fb  = {.v = b};
    float32_t fc  = {.v = c};
    float32_t fna = f32_negate(fa);  // fnmadd: negate product (negate a)

    float32_t fres = f32_mulAdd(fna, fb, fc);

    *fflags = softfloat_to_rtl_flags(softfloat_exceptionFlags);
    *result = fres.v;
}

//============================================================================
// DPI-C: dpi_fnmsub_s — result = -(a * b) - c
//============================================================================
void dpi_fnmsub_s(
    int             enable,
    std::uint32_t   a,
    std::uint32_t   b,
    std::uint32_t   c,
    std::uint32_t   rm,
    std::uint32_t*  result,
    std::uint32_t*  fflags
) {
    if (!enable) {
        *result = 0;
        *fflags = 0;
        return;
    }

    softfloat_exceptionFlags = 0;
    softfloat_roundingMode   = rtl_to_sf_rm(rm);

    float32_t fa  = {.v = a};
    float32_t fb  = {.v = b};
    float32_t fc  = {.v = c};
    float32_t fna = f32_negate(fa);  // fnmsub: negate both product and c
    float32_t fnc = f32_negate(fc);

    float32_t fres = f32_mulAdd(fna, fb, fnc);

    *fflags = softfloat_to_rtl_flags(softfloat_exceptionFlags);
    *result = fres.v;
}
