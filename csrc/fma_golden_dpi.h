//============================================================================
// fma_golden_dpi.h — FP32 FMA DPI-C Golden Model Header
//
// Port names aligned with hector/spec/fma_spec.cpp (Hector formal spec):
//   multiplier, multiplicand, addend, rounding_mode, result, exceptions
//
// op_i / op_mod_i use fpnew_pkg encoding (matching fpnew_fma RTL):
//   FMADD + op_mod=0 → FMADD,  FMADD + op_mod=1 → FMSUB
//   FNMSUB + op_mod=0 → FNMSUB, FNMSUB + op_mod=1 → FNMADD
//   ADD + op_mod=0 → ADD,    ADD + op_mod=1 → SUB
//   MUL + op_mod=x → MUL,    ADDS + op_mod=x → ADDS
//============================================================================

#ifndef FMA_GOLDEN_DPI_H
#define FMA_GOLDEN_DPI_H

#include <cstdint>

// fpnew_pkg::operation_e encoding
#define OP_FMADD  0
#define OP_FNMSUB 1
#define OP_ADD    2
#define OP_MUL    3
#define OP_ADDS   4

extern "C" {

// FP32 ADDMUL golden model — encoding matches fpnew_pkg / fpnew_fma RTL
//
// Parameters:
//   enable        - 1 = perform computation, 0 = output zeros
//   multiplier    - FP32 operand A
//   multiplicand  - FP32 operand B
//   addend        - FP32 operand C
//   rounding_mode - RISC-V: 0=RNE, 1=RTZ, 2=RDN, 3=RUP, 4=RMM
//   op_i          - fpnew_pkg::operation_e: FMADD=0, FNMSUB=1, ADD=2, MUL=3, ADDS=4
//   op_mod_i      - variant select (0 or 1)
//   result        - [out] FP32 result
//   exceptions    - [out] {NV, DZ, OF, UF, NX}
//
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
);

} // extern "C"

#endif // FMA_GOLDEN_DPI_H
