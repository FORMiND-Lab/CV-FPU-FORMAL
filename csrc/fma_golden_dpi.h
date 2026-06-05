//============================================================================
// fma_golden_dpi.h — FP32 FMA DPI-C Golden Model Header
//
// Port names are aligned with hector/spec/fma_spec.cpp (Hector formal spec):
//   multiplier, multiplicand, addend, rounding_mode, result, exceptions
//
// The only difference from the Hector spec is the extra `op` parameter,
// which enables testing all 4 FMA operation variants in cosim.
//============================================================================

#ifndef FMA_GOLDEN_DPI_H
#define FMA_GOLDEN_DPI_H

#include <cstdint>

extern "C" {

// FP32 FMA golden model — port names aligned with Hector fma_spec.cpp
//
// Parameters:
//   enable        - 1 = perform computation, 0 = output zeros
//   multiplier    - FP32 operand A  (matches Hector spec port name)
//   multiplicand  - FP32 operand B  (matches Hector spec port name)
//   addend        - FP32 operand C  (matches Hector spec port name)
//   rounding_mode - RISC-V: 0=RNE, 1=RTZ, 2=RDN, 3=RUP, 4=RMM
//   op            - 0=FMADD, 1=FMSUB, 2=FNMADD, 3=FNMSUB
//   result        - [out] FP32 result  (matches Hector spec port name)
//   exceptions    - [out] {NV, DZ, OF, UF, NX}  (matches Hector spec port name)
//
void dpi_fma_golden(
    int             enable,
    unsigned int    multiplier,
    unsigned int    multiplicand,
    unsigned int    addend,
    unsigned int    rounding_mode,
    unsigned int    op,
    unsigned int*   result,
    unsigned int*   exceptions
);

} // extern "C"

#endif // FMA_GOLDEN_DPI_H
