//============================================================================
// fma_hector_wrap.sv — Hector DP Implementation Wrapper for fpnew_fma
//
// Wraps the cvfpu fpnew_fma module into the Hector DPV interface convention:
//   - go/valid handshake (single pulse) instead of valid/ready streaming
//   - Standardized port names matching the spec model (fma_spec.cpp)
//   - Fixed FP32 format
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
// Differences from the old fma_dut_wrapper.sv (cosim, deleted):
//   - go pulse instead of in_valid/in_ready handshake
//   - Single valid output instead of out_valid/out_ready handshake
//   - Port names match Hector spec model for map_by_name
//   - resetN (active-low) naming convention for -negReset flag
//   - op_i / op_mod_i ports use fpnew_pkg encoding, direct passthrough to fpnew_fma
//============================================================================

`include "common_cells/registers.svh"

module fma_hector_wrap_fp16
  import fpnew_pkg::*;
#(
  // Number of pipeline registers inside fpnew_fma.
  //   0 = purely combinational (simplest for initial proof)
  //   >0 = pipelined (adds latency, adjust TCL lemmas accordingly)
  parameter int unsigned NUM_PIPE_REGS = 0
) (
  // ---- Hector-standard outputs ----
  output logic [15:0] result,
  output logic [4:0]  exceptions,     // {NV, DZ, OF, UF, NX}
  output logic        valid,

  // ---- Hector-standard inputs ----
  input  logic        go,             // Start computation (single-cycle pulse)
  input  logic [15:0] multiplier,     // = operand A
  input  logic [15:0] multiplicand,   // = operand B
  input  logic [15:0] addend,         // = operand C
  input  logic [2:0]  rounding_mode,  // RISC-V: 0=RNE, 1=RTZ, 2=RDN, 3=RUP, 4=RMM
  input  logic [3:0]  op_i,           // fpnew_pkg::operation_e: FMADD,FNMSUB,ADD,MUL,ADDS
  input  logic        op_mod_i,       // 0/1 selects variant (see fpnew_fma encoding table)

  // ---- Clock and reset ----
  input  logic        clock,
  input  logic        resetN          // Active-low reset (Hector convention)
);

  //==========================================================================
  // Internal signals
  //==========================================================================

  // fpnew_fma interface signals
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

  // Pipeline tracking for latency

  // ---- Input mapping ----
  // op_i and op_mod_i are passed directly through to fpnew_fma.
  // The fpnew_fma module internally handles all sign manipulation,
  // ADD (forces A=1.0), MUL (forces C=0), and ADDS variants.
  // Encoding matches fpnew_pkg::operation_e:
  //   FMADD=0, FNMSUB=1, ADD=2, MUL=3, ADDS=4
  //   op_mod_i: 0 or 1 selects variant (see fpnew_fma comments)

  // Pack operands
  assign fma_operands[0] = multiplier;
  assign fma_operands[1] = multiplicand;
  assign fma_operands[2] = addend;

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
  // fpnew_fma instance (the DUT — identical to fma_dut_wrapper.sv)
  //==========================================================================

  fpnew_fma #(
    .FpFormat    (fpnew_pkg::FP16),
    .NumPipeRegs (NUM_PIPE_REGS),
    .PipeConfig  (fpnew_pkg::BEFORE),
    .TagType     (logic),
    .AuxType     (logic)
  ) i_fma (
    .clk_i              (clock),
    .rst_ni             (resetN),       // Both use active-low reset
    .operands_i         (fma_operands),
    .is_boxed_i         (3'b111),       // All boxed (RISC-V)
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

  // Result: direct passthrough
  assign result = fma_result;

  // Exception flags: {NV, DZ, OF, UF, NX}
  assign exceptions = {
    fma_status.NV,   // bit 4: Invalid Operation
    fma_status.DZ,   // bit 3: Divide by Zero (always 0 for FMA)
    fma_status.OF,   // bit 2: Overflow
    fma_status.UF,   // bit 1: Underflow
    fma_status.NX    // bit 0: Inexact
  };

endmodule
