//============================================================================
// fma_spec_wrap_fp32.cpp — Hector Specification Model for FP32 FMA
//
// UNIFIED golden model covering all FP32 operations supported by
// fma_hector_wrap.sv (i.e., rtl/fma_wrap_fmad_fp32.sv).
// Uses op_i / op_mod_i to select the operation, matching the RTL's
// single-module-multi-operation architecture.
//
// Operations covered:
//   FMADD  (op_i=0, op_mod=0): A * B + C       → f32_mulAdd(A, B, C)
//   FMSUB  (op_i=0, op_mod=1): A * B - C       → f32_mulAdd(A, B, C^0x80000000)
//   FNMSUB (op_i=1, op_mod=0): -A * B + C      → f32_mulAdd(A^0x80000000, B, C)
//   FNMADD (op_i=1, op_mod=1): -A * B - C      → f32_mulAdd(A^0x80000000, B, C^0x80000000)
//   ADD    (op_i=2, op_mod=0): B + C           → f32_add(B, C)
//   SUB    (op_i=2, op_mod=1): B - C           → f32_sub(B, C)
//   MUL    (op_i=3, *):        A * B           → f32_mul(A, B)
//
// Extends the original fma_spec_wrap_fp32_fmadd.cpp (FMADD-only) to a
// unified spec that mirrors the FP16 fma_spec_wrap_fp16.cpp structure.
//
// References:
//   - DPV_Advanced example: cosim/third_party/example/DPV_Advanced/c/madd32.cc
//   - FP16 unified spec:   formal/spec/fma_spec_wrap_fp16.cpp
//   - DPI golden model:    sim/csrc/fma_dpi.cpp
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
    uint32_t multiplier;         // FP32 operand A
    uint32_t multiplicand;       // FP32 operand B
    uint32_t addend;             // FP32 operand C
    uint32_t result;             // FP32 result
    uint8_t  op_i;               // operation selector (4-bit, fpnew_pkg::operation_e)
    uint8_t  op_mod_i;           // operation modifier (1-bit)

    float32_t f_multiplier;
    float32_t f_multiplicand;
    float32_t f_addend;
    float32_t f_result;

    // ---- Hector I/O registration ----
    // Names MUST match the port names in fma_hector_wrap.sv for map_by_name.
    Hector::registerInput("multiplier",     &multiplier,     8 * sizeof(multiplier));
    Hector::registerInput("multiplicand",   &multiplicand,   8 * sizeof(multiplicand));
    Hector::registerInput("addend",         &addend,         8 * sizeof(addend));
    Hector::registerInput("rounding_mode",  &rounding_mode,  8 * sizeof(rounding_mode));
    Hector::registerInput("op_i",           &op_i,           8 * sizeof(op_i));
    Hector::registerInput("op_mod_i",       &op_mod_i,       8 * sizeof(op_mod_i));
    Hector::registerOutput("result",        &result,         8 * sizeof(result));
    Hector::registerOutput("exceptions",    &exceptions,     8 * sizeof(exceptions));

    Hector::beginCapture();

    // ---- Input mapping: uint32_t → SoftFloat float32_t ----
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
            f_addend.v ^= 0x80000000u;  // FMSUB: invert sign of C
        }
        f_result = f32_mulAdd(f_multiplier, f_multiplicand, f_addend);

    } else if (op_i == 1) {
        // ---- FNMSUB family (negated-product FMA) ----
        //   op_mod=0: FNMSUB → -A * B + C  (negate multiplier)
        //   op_mod=1: FNMADD → -A * B - C  (negate both multiplier and addend)
        f_multiplier.v ^= 0x80000000u;  // invert sign of A
        if (op_mod_i == 1) {
            f_addend.v ^= 0x80000000u;  // FNMADD: also invert sign of C
        }
        f_result = f32_mulAdd(f_multiplier, f_multiplicand, f_addend);

    } else if (op_i == 2) {
        // ---- ADD family ----
        //   op_mod=0: ADD → B + C
        //   op_mod=1: SUB → B - C
        // NOTE: multiplier (A) is ignored; RTL forces A=1.0 internally.
        if (op_mod_i == 0) {
            f_result = f32_add(f_multiplicand, f_addend);
        } else {
            f_result = f32_sub(f_multiplicand, f_addend);
        }

    } else if (op_i == 3) {
        // ---- MUL ----
        //   op_mod ignored: A * B
        // NOTE: addend (C) is ignored; RTL forces C=0 internally.
        f_result = f32_mul(f_multiplier, f_multiplicand);

    } else {
        // ---- Undefined operation ----
        // Return canonical NaN to flag invalid state; matches RTL behavior
        // where undefined op_i values produce unspecified output.
        f_result.v = 0x7FC00000;  // FP32 canonical NaN
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
