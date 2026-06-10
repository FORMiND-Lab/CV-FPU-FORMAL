//============================================================================
// dpi_fma_golden.sv — DPI-C Golden Model Declarations (SystemVerilog side)
//
// Port names aligned with formal/spec/fma_spec_wrap_fp32_fmad.cpp:
//   multiplier, multiplicand, addend, rounding_mode, result, exceptions
//
// op_i / op_mod_i encoding matches fpnew_pkg / fpnew_fma:
//   FMADD=0, FNMSUB=1, ADD=2, MUL=3, ADDS=4
//   op_mod_i: 0/1 selects variant (FMSUB, FNMADD, SUB, ...)
//============================================================================

package dpi_fma_golden_pkg;

  // fpnew_pkg::operation_e encoding
  localparam int OP_FMADD  = 0;
  localparam int OP_FNMSUB = 1;
  localparam int OP_ADD    = 2;
  localparam int OP_MUL    = 3;
  localparam int OP_ADDS   = 4;

  import "DPI-C" function void dpi_fma_golden(
    input  int enable,
    input  int multiplier,
    input  int multiplicand,
    input  int addend,
    input  int rounding_mode,
    input  int op_i,
    input  int op_mod_i,
    output int result,
    output int exceptions
  );

endpackage
