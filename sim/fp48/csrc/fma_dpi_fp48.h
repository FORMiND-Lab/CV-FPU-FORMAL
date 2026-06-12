//============================================================================
// fma_dpi_fp48.h — FP48 ADDMUL DPI-C Golden Model Header
//
// Port names aligned with fma_wrap_fp48.sv (Hector DPV convention):
//   multiplier, multiplicand, addend, rounding_mode, result, exceptions
//
// op_i / op_mod_i encoding matches fpnew_pkg / fpnew_fma RTL:
//   ┌────────┬──────────┬─────────────┬──────────────────────────┐
//   │ op_i   │ op_mod_i │ Operation   │ Implementation           │
//   ├────────┼──────────┼─────────────┼──────────────────────────┤
//   │ FMADD  │ 0        │ FMADD       │ f48_mulAdd(a, b, c)      │
//   │ FMADD  │ 1        │ FMSUB       │ f48_mulAdd(a, b, neg(c)) │
//   │ FNMSUB │ 0        │ FNMSUB      │ f48_mulAdd(neg(a),b,c)   │
//   │ FNMSUB │ 1        │ FNMADD      │ f48_mulAdd(neg(a),b,neg(c))│
//   │ ADD    │ 0        │ ADD         │ f48_mulAdd(1.0, b, c)    │
//   │ ADD    │ 1        │ SUB         │ f48_mulAdd(1.0, b, neg(c))│
//   │ MUL    │ x        │ MUL         │ f48_mulAdd(a, b, 0)      │
//   │ ADDS   │ x        │ ADDS        │ f48_mulAdd(1.0, b, c)    │
//   └────────┴──────────┴─────────────┴──────────────────────────┘
//
// FP48 format: E11M36, bias=1023, NaN-boxed in 64-bit container.
//
// NOTE: Currently STUB — returns 0 for result and exceptions.
//       Replace with real FP48 SoftFloat or MPFR-based golden model.
//============================================================================

#ifndef FMA_DPI_FP48_H
#define FMA_DPI_FP48_H

#include <cstdint>

// fpnew_pkg::operation_e encoding (same as fp32 variant)
#define OP_FP48_FMADD  0
#define OP_FP48_FNMSUB 1
#define OP_FP48_ADD    2
#define OP_FP48_MUL    3
#define OP_FP48_ADDS   4

extern "C" {

// FP48 ADDMUL golden model — encoding matches fpnew_pkg / fpnew_fma RTL
//
// Parameters:
//   enable        - 1 = perform computation, 0 = output zeros
//   multiplier    - FP48 operand A (64-bit container, NaN-boxed)
//   multiplicand  - FP48 operand B (64-bit container, NaN-boxed)
//   addend        - FP48 operand C (64-bit container, NaN-boxed)
//   rounding_mode - RISC-V: 0=RNE, 1=RTZ, 2=RDN, 3=RUP, 4=RMM
//   op_i          - fpnew_pkg::operation_e: FMADD=0, FNMSUB=1, ADD=2, MUL=3, ADDS=4
//   op_mod_i      - variant select (0 or 1)
//   result        - [out] FP48 result (64-bit container, NaN-boxed)
//   exceptions    - [out] {NV, DZ, OF, UF, NX}
//
// NOTE: STUB implementation — always returns result=0, exceptions=0.
//       Replace body with real FP48 computation when golden model is available.
//
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
);

} // extern "C"

#endif // FMA_DPI_FP48_H
