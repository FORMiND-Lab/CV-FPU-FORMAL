//============================================================================
// fma_spec.cpp — Hector Specification Model for FP32 FMA
//
// This is the C++ "golden model" that Hector uses as the specification side
// of the equivalence check. It wraps Berkeley SoftFloat's f16_mulAdd with
// the Hector API (Hector::registerInput, Hector::registerOutput, etc.).
//
// References:
//   - DPV_Advanced example: cosim/third_party/example/DPV_Advanced/c/madd32.cc
//   - Migration plan:    temp/cosim_to_hector_migration_plan.md
//============================================================================

#include "Hector.h"
#include "softfloat.h"

//============================================================================
// hector_wrapper — Hector entry point
//
// This function is called by Hector's compilation and solving framework.
// It registers I/O, captures the computation, and lets Hector derive the
// formal equivalence between this C++ spec and the RTL implementation.
//
// I/O ports (match fma_hector_wrap.sv port names):
//   Inputs:  multiplier, multiplicand, addend, rounding_mode
//   Outputs: result, exceptions
//
// Rounding mode mapping (RISC-V → SoftFloat):
//   RISC-V: RNE=0, RTZ=1, RDN=2, RUP=3, RMM=4, DYN=7
//   SoftFloat: near_even=0, minMag=1, min=2, max=3, near_maxMag=4
//   Direct 1:1 mapping for 0-4.
//
// Exception flag mapping (RISC-V / RTL: {NV, DZ, OF, UF, NX}):
//   SoftFloat: inexact=1, underflow=2, overflow=4, infinite=8, invalid=16
//   RTL:       NV=bit4, DZ=bit3, OF=bit2, UF=bit1, NX=bit0
//   NOTE: SoftFloat's flag_infinite(=8) / DZ is NOT mapped; FMA never sets DZ.
//============================================================================

void hector_wrapper()
{
    // ---- I/O variables ----
    uint8_t  rounding_mode;      // 0..4 (RISC-V encoding), 5-7 undefined
    uint8_t  exceptions;         // {NV, DZ, OF, UF, NX} (5 bits)
    uint16_t multiplier;         // FP32 operand A
    uint16_t multiplicand;       // FP32 operand B
    uint16_t addend;             // FP32 operand C
    uint16_t result;             // FP32 result

    float16_t f_multiplier;
    float16_t f_multiplicand;
    float16_t f_addend;
    float16_t f_result;

    // ---- Hector I/O registration ----
    // Names MUST match the port names in fma_hector_wrap.sv for map_by_name.
    Hector::registerInput("multiplier",     &multiplier,     16);
    Hector::registerInput("multiplicand",   &multiplicand,   16);
    Hector::registerInput("addend",         &addend,         16);
    Hector::registerInput("rounding_mode",  &rounding_mode,  8 * sizeof(rounding_mode));
    Hector::registerOutput("result",        &result,         16);
    Hector::registerOutput("exceptions",    &exceptions,     8 * sizeof(exceptions));

    Hector::beginCapture();

    // ---- Input mapping: uint32_t → SoftFloat float16_t ----
    f_multiplier.v   = multiplier;
    f_multiplicand.v = multiplicand;
    f_addend.v       = addend;

    // ---- SoftFloat state configuration ----
    // Use AFTER rounding tininess detection to match cvfpu fpnew_fma RTL behavior.
    // The RTL produces only NX (not UF) on subnormal-to-normal boundary cases,
    // which is consistent with after-rounding tininess.
    softfloat_roundingMode   = rounding_mode;  // 0-4 maps directly
    softfloat_exceptionFlags = 0;
    softfloat_detectTininess = softfloat_tininess_afterRounding;

    // ---- Golden computation: FP32 FMA ----
    f_result = f16_mulAdd(f_multiplier, f_multiplicand, f_addend);

    // ---- Output mapping ----
    result     = f_result.v;

    // Extract only the 5 flags relevant to RISC-V FMA:
    //   bit4=NV (invalid), bit3=DZ (infinite), bit2=OF (overflow),
    //   bit1=UF (underflow), bit0=NX (inexact)
    // NOTE: SoftFloat flag_infinite (bit3) is NOT mapped — FMA never sets
    // divide-by-zero. Infinite results from FMA are caused by overflow
    // (OF+NX) or invalid operations (NV), both already handled.
    // The & 0x1f masks out unmapped high bits.
    exceptions = 0;
    if (softfloat_exceptionFlags & softfloat_flag_invalid)   exceptions |= (1 << 4);  // NV
    // softfloat_flag_infinite (bit 3) intentionally skipped
    if (softfloat_exceptionFlags & softfloat_flag_overflow)  exceptions |= (1 << 2);  // OF
    if (softfloat_exceptionFlags & softfloat_flag_underflow) exceptions |= (1 << 1);  // UF
    if (softfloat_exceptionFlags & softfloat_flag_inexact)   exceptions |= (1 << 0);  // NX

    Hector::endCapture();
}
