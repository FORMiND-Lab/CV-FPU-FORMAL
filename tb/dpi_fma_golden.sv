//============================================================================
// dpi_fma_golden.sv — DPI-C Golden Model Declarations (SystemVerilog side)
//
// Port names aligned with hector/spec/fma_spec.cpp:
//   multiplier, multiplicand, addend, rounding_mode, result, exceptions
//============================================================================

package dpi_fma_golden_pkg;

  // ---- DPI-C import: unified FMA golden model ----
  // op: 0=FMADD, 1=FMSUB, 2=FNMADD, 3=FNMSUB
  import "DPI-C" function void dpi_fma_golden(
    input  int enable,
    input  int multiplier,
    input  int multiplicand,
    input  int addend,
    input  int rounding_mode,
    input  int op,
    output int result,
    output int exceptions
  );

endpackage
