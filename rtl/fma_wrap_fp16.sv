//============================================================================
// fma_hector_wrap_fp16.sv — Hector DP Implementation Wrapper for fpnew_fma (FP16)
//
// FP16 variant of fma_hector_wrap.sv. Identical structure, narrower datapath.
//
// Key differences from FP32 wrapper:
//   - Port widths: 32 → 16 (multiplier, multiplicand, addend, result)
//   - fpnew_fma FpFormat: FP32 → FP16
//   - FP16 format: 1 sign, 5 exp, 10 man, bias=15
//
// Internal datapath (auto-computed by fpnew_fma):
//   PRECISION_BITS = 11   (vs 24 for FP32)
//   Product         = 22b  (vs 48b)
//   Internal sum    = 37b  (vs 76b)
//   LZC input       = 25b  (vs 51b)
//
// The go/valid protocol, operation encoding, rounding modes, and exception
// flags are identical to the FP32 wrapper.
//============================================================================

`include "common_cells/registers.svh"

module fma_hector_wrap_fp16
  import fpnew_pkg::*;
#(
  parameter int unsigned NUM_PIPE_REGS = 0
) (
  // ---- Hector-standard outputs ----
  output logic [15:0] result,
  output logic [4:0]  exceptions,     // {NV, DZ, OF, UF, NX}
  output logic        valid,

  // ---- Hector-standard inputs ----
  input  logic        go,
  input  logic [15:0] multiplier,     // = operand A (FP16)
  input  logic [15:0] multiplicand,   // = operand B (FP16)
  input  logic [15:0] addend,         // = operand C (FP16)
  input  logic [2:0]  rounding_mode,  // RISC-V: 0=RNE, 1=RTZ, 2=RDN, 3=RUP, 4=RMM
  input  logic [3:0]  op_i,           // fpnew_pkg::operation_e
  input  logic        op_mod_i,       // 0/1 selects variant

  // ---- Clock and reset ----
  input  logic        clock,
  input  logic        resetN
);

  //==========================================================================
  // Internal signals
  //==========================================================================

  logic                 fma_in_valid;
  logic                 fma_in_ready;
  logic [2:0][15:0]     fma_operands;
  fpnew_pkg::roundmode_e fma_rm;
  fpnew_pkg::operation_e fma_op;
  logic                 fma_op_mod;
  logic                 fma_out_valid;
  logic                 fma_out_ready;
  logic [15:0]          fma_result;
  fpnew_pkg::status_t   fma_status;

  // ---- Input mapping ----
  assign fma_operands[0] = multiplier;
  assign fma_operands[1] = multiplicand;
  assign fma_operands[2] = addend;

  assign fma_rm = fpnew_pkg::roundmode_e'(rounding_mode);
  assign fma_op     = fpnew_pkg::operation_e'(op_i);
  assign fma_op_mod = op_mod_i;

  assign fma_in_valid = go;
  assign fma_out_ready = 1'b1;

  //==========================================================================
  // fpnew_fma instance — FP16 (the narrower DUT)
  //==========================================================================

  fpnew_fma #(
    .FpFormat    (fpnew_pkg::FP16),   // ← FP16 instead of FP32
    .NumPipeRegs (NUM_PIPE_REGS),
    .PipeConfig  (fpnew_pkg::BEFORE),
    .TagType     (logic),
    .AuxType     (logic)
  ) i_fma (
    .clk_i              (clock),
    .rst_ni             (resetN),
    .operands_i         (fma_operands),
    .is_boxed_i         (3'b111),
    .rnd_mode_i         (fma_rm),
    .op_i               (fma_op),
    .op_mod_i           (fma_op_mod),
    .tag_i              (1'b0),
    .mask_i             (1'b1),
    .aux_i              (1'b0),
    .in_valid_i         (fma_in_valid),
    .in_ready_o         (fma_in_ready),
    .flush_i            (1'b0),
    .result_o           (fma_result),
    .status_o           (fma_status),
    .extension_bit_o    (),
    .tag_o              (),
    .mask_o             (),
    .aux_o              (),
    .out_valid_o        (fma_out_valid),
    .out_ready_i        (fma_out_ready),
    .busy_o             (),
    .reg_ena_i          ('0),
    .early_out_valid_o  ()
  );

  //==========================================================================
  // Output mapping
  //==========================================================================

  assign valid = fma_out_valid;
  assign result = fma_result;
  assign exceptions = {
    fma_status.NV,
    fma_status.DZ,
    fma_status.OF,
    fma_status.UF,
    fma_status.NX
  };

endmodule
