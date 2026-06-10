//============================================================================
// fma_hector_wrap_fp16_spec.cpp — Hector Specification Model for FP16 FMA
//
// UNIFIED golden model covering all FP16 operations supported by
// fma_hector_wrap_fp16.sv. Uses op_i / op_mod_i to select the operation,
// matching the RTL's single-module-multi-operation architecture.
//
// Operations covered:
//   FMADD  (op_i=0, op_mod=0): A * B + C       → f16_mulAdd(A, B, C)
//   FMSUB  (op_i=0, op_mod=1): A * B - C       → f16_mulAdd(A, B, C^0x8000)
//   FNMSUB (op_i=1, op_mod=0): -A * B + C      → f16_mulAdd(A^0x8000, B, C)
//   FNMADD (op_i=1, op_mod=1): -A * B - C      → f16_mulAdd(A^0x8000, B, C^0x8000)
//   ADD    (op_i=2, op_mod=0): B + C           → f16_add(B, C)
//   SUB    (op_i=2, op_mod=1): B - C           → f16_sub(B, C)
//   MUL    (op_i=3, *):        A * B           → f16_mul(A, B)
//
// Replaces the following separate spec files:
//   fma_spec_fp16.cpp, fmsub_spec_fp16.cpp, fnmadd_spec_fp16.cpp,
//   fnmsub_spec_fp16.cpp, add_spec_fp16.cpp, sub_spec_fp16.cpp,
//   mul_spec_fp16.cpp
//
// References:
//   - DPV_Advanced example: cosim/third_party/example/DPV_Advanced/c/madd32.cc
//   - Merger plan:          temp/spec_merge_plan_fp16.md
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
// I/O ports (match fma_hector_wrap_fp16.sv port names):
//   Inputs:  multiplier, multiplicand, addend, rounding_mode, op_i, op_mod_i
//   Outputs: result, exceptions
//
// Operation encoding (op_i, op_mod_i → operation):
//   op_i = 0 (FMADD):  op_mod=0 → FMADD,  op_mod=1 → FMSUB
//   op_i = 1 (FNMSUB): op_mod=0 → FNMSUB, op_mod=1 → FNMADD
//   op_i = 2 (ADD):    op_mod=0 → ADD,    op_mod=1 → SUB
//   op_i = 3 (MUL):    op_mod ignored  → MUL
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
    uint16_t multiplier;         // FP16 operand A
    uint16_t multiplicand;       // FP16 operand B
    uint16_t addend;             // FP16 operand C
    uint16_t result;             // FP16 result
    uint8_t  op_i;               // operation selector (4-bit, fpnew_pkg::operation_e)
    uint8_t  op_mod_i;           // operation modifier (1-bit)

    float16_t f_multiplier;
    float16_t f_multiplicand;
    float16_t f_addend;
    float16_t f_result;

    // ---- Hector I/O registration ----
    // Names MUST match the port names in fma_hector_wrap_fp16.sv for map_by_name.
    Hector::registerInput("multiplier",     &multiplier,     16);
    Hector::registerInput("multiplicand",   &multiplicand,   16);
    Hector::registerInput("addend",         &addend,         16);
    Hector::registerInput("rounding_mode",  &rounding_mode,  8 * sizeof(rounding_mode));
    Hector::registerInput("op_i",           &op_i,           4);   // 4-bit, matches RTL input [3:0]
    Hector::registerInput("op_mod_i",       &op_mod_i,       1);   // 1-bit, matches RTL input
    Hector::registerOutput("result",        &result,         16);
    Hector::registerOutput("exceptions",    &exceptions,     8 * sizeof(exceptions));

    Hector::beginCapture();

    // ---- Input mapping: uint16_t → SoftFloat float16_t ----
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

    //====================================================================
    // Operation selection — replicates fpnew_fma behavior for each mode
    //====================================================================

    if (op_i == 0) {
        // ---- FMADD family (FMA) ----
        //   op_mod=0: FMADD  → A * B + C
        //   op_mod=1: FMSUB  → A * B - C  (negate addend)
        if (op_mod_i == 1) {
            f_addend.v ^= 0x8000;  // FMSUB: invert sign of C
        }
        f_result = f16_mulAdd(f_multiplier, f_multiplicand, f_addend);

    } else if (op_i == 1) {
        // ---- FNMSUB family (negated-product FMA) ----
        //   op_mod=0: FNMSUB → -A * B + C  (negate multiplier)
        //   op_mod=1: FNMADD → -A * B - C  (negate both multiplier and addend)
        f_multiplier.v ^= 0x8000;  // invert sign of A
        if (op_mod_i == 1) {
            f_addend.v ^= 0x8000;  // FNMADD: also invert sign of C
        }
        f_result = f16_mulAdd(f_multiplier, f_multiplicand, f_addend);

    } else if (op_i == 2) {
        // ---- ADD family ----
        //   op_mod=0: ADD → B + C
        //   op_mod=1: SUB → B - C
        // NOTE: multiplier (A) is ignored; RTL forces A=1.0 internally.
        if (op_mod_i == 0) {
            f_result = f16_add(f_multiplicand, f_addend);
        } else {
            f_result = f16_sub(f_multiplicand, f_addend);
        }

    } else if (op_i == 3) {
        // ---- MUL ----
        //   op_mod ignored: A * B
        // NOTE: addend (C) is ignored; RTL forces C=0 internally.
        f_result = f16_mul(f_multiplier, f_multiplicand);

    } else {
        // ---- Undefined operation ----
        // Return canonical NaN to flag invalid state; matches RTL behavior
        // where undefined op_i values produce unspecified output.
        f_result.v = 0x7E00;  // FP16 canonical NaN
    }

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
