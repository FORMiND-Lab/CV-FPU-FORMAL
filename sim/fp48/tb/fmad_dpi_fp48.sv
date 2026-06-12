//============================================================================
// fmad_dpi_fp48.sv — DPI-C Golden Model Declarations for FP48 (SV side)
//
// Port names aligned with fma_wrap_fp48.sv:
//   multiplier, multiplicand, addend, rounding_mode, result, exceptions
//
// op_i / op_mod_i encoding matches fpnew_pkg / fpnew_fma:
//   FMADD=0, FNMSUB=1, ADD=2, MUL=3, ADDS=4
//   op_mod_i: 0/1 selects variant (FMSUB, FNMADD, SUB, ...)
//
// NOTE: DPI function is currently a STUB — always returns 0.
//       Once real FP48 golden model is ready, only fma_dpi_fp48.cpp needs updating.
//============================================================================

package dpi_fma_golden_fp48_pkg;

  // fpnew_pkg::operation_e encoding
  localparam int OP_FP48_FMADD  = 0;
  localparam int OP_FP48_FNMSUB = 1;
  localparam int OP_FP48_ADD    = 2;
  localparam int OP_FP48_MUL    = 3;
  localparam int OP_FP48_ADDS   = 4;

  // FP48 NaN-boxed container
  // +0.0 in FP48 NaN-boxed = 64'hffff000000000000
  localparam logic [63:0] FP48_POS_ZERO_BOXED = 64'hffff000000000000;

  import "DPI-C" function void dpi_fma_golden_fp48(
    input  int          enable,
    input  longint      multiplier,
    input  longint      multiplicand,
    input  longint      addend,
    input  int          rounding_mode,
    input  int          op_i,
    input  int          op_mod_i,
    output longint      result,
    output int          exceptions
  );

endpackage
