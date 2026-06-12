//============================================================================
// fma_wrap_fp48.sv — Hector DP Implementation Wrapper for fpnew_fma (FP48)
//
// Wraps the cvfpu fpnew_fma module into the Hector DPV interface convention:
//   - go/valid handshake (single pulse) instead of valid/ready streaming
//   - Standardized port names matching the spec model (fma_spec_wrap_fp48.cpp)
//   - Fixed FP48 format (E11M36, bias=1023)
//   - 64-bit container: operands/results use 64-bit ports,
//     low 48 bits hold the FP48 payload, high 16 bits are NaN-boxed (16'hffff)
//   - op_i / op_mod_i ports use fpnew_pkg encoding, passed through to fpnew_fma:
//       FMADD + op_mod=0 → FMADD,  FMADD + op_mod=1 → FMSUB
//       FNMSUB + op_mod=0 → FNMSUB, FNMSUB + op_mod=1 → FNMADD
//       ADD + op_mod=0 → ADD,  ADD + op_mod=1 → SUB
//       MUL + op_mod=0 → MUL,  ADDS + op_mod=0 → ADDS
//
// The Hector interface convention (from DPV_Advanced examples):
//   Inputs:  go, [operands], rounding_mode, clock, resetN
//   Outputs: result, exceptions, valid
//
// References:
//   - rtl/fma_wrap_fp32.sv: FP32 wrapper (baseline for interface)
//   - cvfpu/src/fpnew_fma.sv: Parameterized FMA unit
//   - cvfpu/src/fpnew_pkg.sv: FP48 format definition
//============================================================================

`include "common_cells/registers.svh"

module fma_wrap_fp48
  import fpnew_pkg::*;
#(
  // Number of pipeline registers inside fpnew_fma.
  //   0 = purely combinational (simplest for initial proof)
  //   >0 = pipelined (adds latency, adjust TCL lemmas accordingly)
  parameter int unsigned NUM_PIPE_REGS = 0
) (
  // ---- Hector-standard outputs ----
  output logic [63:0] result,
  output logic [4:0]  exceptions,     // {NV, DZ, OF, UF, NX}
  output logic        valid,

  // ---- Hector-standard inputs ----
  input  logic        go,             // Start computation (single-cycle pulse)
  input  logic [63:0] multiplier,     // = operand A (FP48 in 64-bit container)
  input  logic [63:0] multiplicand,   // = operand B (FP48 in 64-bit container)
  input  logic [63:0] addend,         // = operand C (FP48 in 64-bit container)
  input  logic [2:0]  rounding_mode,  // RISC-V: 0=RNE, 1=RTZ, 2=RDN, 3=RUP, 4=RMM
  input  logic [3:0]  op_i,           // fpnew_pkg::operation_e: FMADD,FNMSUB,ADD,MUL,ADDS
  input  logic        op_mod_i,       // 0/1 selects variant (see fpnew_fma encoding table)

  // ---- Clock and reset ----
  input  logic        clock,
  input  logic        resetN          // Active-low reset (Hector convention)
);

  //==========================================================================
  // Constants
  //==========================================================================
  localparam int unsigned FP48_WIDTH = fp_width(FP48);  // = 48
  localparam int unsigned CONTAINER_WIDTH = 64;

  //==========================================================================
  // Internal signals
  //==========================================================================

  // fpnew_fma interface signals (48-bit native width)
  logic                 fma_in_valid;
  logic                 fma_in_ready;
  logic [2:0][FP48_WIDTH-1:0] fma_operands;
  fpnew_pkg::roundmode_e      fma_rm;
  fpnew_pkg::operation_e      fma_op;
  logic                       fma_op_mod;
  logic                       fma_out_valid;
  logic                       fma_out_ready;
  logic [FP48_WIDTH-1:0]      fma_result;
  fpnew_pkg::status_t         fma_status;

  //==========================================================================
  // 64-bit container ↔ 48-bit payload conversion
  //==========================================================================
  // Input: extract low 48 bits from 64-bit container
  //   The high 16 bits are expected to be NaN-boxed (16'hffff) per RISC-V
  //   convention, but for formal verification we don't check boxing here;
  //   we just pass the low 48 bits through.
  assign fma_operands[0] = multiplier[FP48_WIDTH-1:0];
  assign fma_operands[1] = multiplicand[FP48_WIDTH-1:0];
  assign fma_operands[2] = addend[FP48_WIDTH-1:0];

  // Rounding mode: direct cast (0-4 map identically)
  assign fma_rm = fpnew_pkg::roundmode_e'(rounding_mode);

  // Operation: pass through directly to fpnew_fma
  assign fma_op     = fpnew_pkg::operation_e'(op_i);
  assign fma_op_mod = op_mod_i;

  // go → in_valid (Hector single-pulse to streaming handshake)
  // For NUM_PIPE_REGS=0 (combinational), in_ready is always 1.
  assign fma_in_valid = go;
  assign fma_out_ready = 1'b1;  // Always ready to accept output

  //==========================================================================
  // fpnew_fma instance — the DUT
  //
  // FpFormat = FP48: WIDTH=48, EXP_BITS=11, MAN_BITS=36, BIAS=1023
  // Internal widths derived automatically:
  //   PRECISION_BITS = 37  (p)
  //   Product width   = 74  (2p)
  //   Internal sum    = 115 (3p+4)
  //   LZC input       = 77  (2p+3)
  //==========================================================================

  fpnew_fma #(
    .FpFormat    (fpnew_pkg::FP48),
    .NumPipeRegs (NUM_PIPE_REGS),
    .PipeConfig  (fpnew_pkg::BEFORE),
    .TagType     (logic),
    .AuxType     (logic)
  ) i_fma (
    .clk_i              (clock),
    .rst_ni             (resetN),
    .operands_i         (fma_operands),
    .is_boxed_i         (3'b111),       // All boxed (trust input)
    .rnd_mode_i         (fma_rm),
    .op_i               (fma_op),
    .op_mod_i           (fma_op_mod),
    .tag_i              (1'b0),
    .mask_i             (1'b1),         // No SIMD masking
    .aux_i              (1'b0),
    .in_valid_i         (fma_in_valid),
    .in_ready_o         (fma_in_ready),
    .flush_i            (1'b0),         // No flush-to-zero
    .result_o           (fma_result),
    .status_o           (fma_status),
    .extension_bit_o    (),             // Unused
    .tag_o              (),             // Unused
    .mask_o             (),             // Unused
    .aux_o              (),             // Unused
    .out_valid_o        (fma_out_valid),
    .out_ready_i        (fma_out_ready),
    .busy_o             (),             // Unused
    .reg_ena_i          ('0),           // No external reg enable
    .early_out_valid_o  ()              // Unused
  );

  //==========================================================================
  // Output mapping
  //==========================================================================

  // valid: asserted when the result is available
  // For combinational (NUM_PIPE_REGS=0): same-cycle as go
  // For pipelined (NUM_PIPE_REGS=N): delayed by N+1 cycles
  assign valid = fma_out_valid;

  // Result: extend 48-bit payload to 64-bit NaN-boxed container
  //   result[63:48] = 16'hffff  (NaN-box)
  //   result[47:0]  = FP48 result
  assign result = {16'hffff, fma_result};

  // Exception flags: {NV, DZ, OF, UF, NX}
  assign exceptions = {
    fma_status.NV,   // bit 4: Invalid Operation
    fma_status.DZ,   // bit 3: Divide by Zero (always 0 for FMA)
    fma_status.OF,   // bit 2: Overflow
    fma_status.UF,   // bit 1: Underflow
    fma_status.NX    // bit 0: Inexact
  };

endmodule
