//============================================================================
// fpu_top_wrap_fp32.sv — Hector DP Implementation Wrapper for fpnew_top
//
// Wraps the cvfpu fpnew_top module (instead of fpnew_fma directly) into the
// Hector DPV interface convention:
//   - go/valid handshake (single pulse) instead of valid/ready streaming
//   - Standardized port names matching the spec model (fma_spec_wrap_fp32.cpp)
//   - Fixed FP32 format, ADDMUL-only operation group
//   - All other formats/opgroups disabled via Features/Implementation
//
// Differences from fma_wrap_fp32.sv (direct fpnew_fma wrapper):
//   - Instantiates fpnew_top instead of fpnew_fma
//   - Internal control signals (src_fmt_i, dst_fmt_i, vectorial_op_i, etc.)
//     are fixed to minimal values rather than being exposed as ports
//   - Uses fpu_top_formal_cfg_pkg for Features/Implementation constants
//   - Result passes through fpnew_top's opgroup routing + rr_arb_tree output
//
// The Hector interface convention:
//   Inputs:  go, multiplier, multiplicand, addend, rounding_mode, op_i, op_mod_i,
//            clock, resetN
//   Outputs: result, exceptions, valid
//
// References:
//   - temp/top_plan.md: Top migration plan (all phases)
//   - cvfpu/src/fpnew_top.sv: Top-level FPU with opgroup routing + arbitration
//   - cvfpu/src/fpnew_pkg.sv: Types, RV32F features, fpu_implementation_t
//   - rtl/fma_wrap_fp32.sv: Existing wrapper (baseline for interface)
//============================================================================

module fpu_top_wrap_fp32
  import fpnew_pkg::*;
  import fpu_top_formal_cfg_pkg::*;
#(
  // Number of pipeline registers.
  //   Kept for interface compatibility with fma_wrap_fp32.sv.
  //   In the minimal formal configuration, all PipeRegs are hardcoded to 0
  //   via FORMAL_ADDMUL_FP32_ONLY. This parameter is reserved for future
  //   pipelined proofs (would require overriding the Implementation struct).
  parameter int unsigned NUM_PIPE_REGS = 0
) (
  // ---- Hector-standard outputs ----
  output logic [31:0] result,
  output logic [4:0]  exceptions,     // {NV, DZ, OF, UF, NX}
  output logic        valid,

  // ---- Hector-standard inputs ----
  input  logic        go,             // Start computation (single-cycle pulse)
  input  logic [31:0] multiplier,     // = operand A
  input  logic [31:0] multiplicand,   // = operand B
  input  logic [31:0] addend,         // = operand C
  input  logic [2:0]  rounding_mode,  // RISC-V: 0=RNE, 1=RTZ, 2=RDN, 3=RUP, 4=RMM
  input  logic [3:0]  op_i,           // fpnew_pkg::operation_e: FMADD,FNMSUB,ADD,MUL,ADDS
  input  logic        op_mod_i,       // 0/1 selects variant per operation

  // ---- Clock and reset ----
  input  logic        clock,
  input  logic        resetN          // Active-low reset (Hector convention)
);

  //==========================================================================
  // Internal signals
  //==========================================================================

  // Packed operands: fpnew_top expects [NUM_OPERANDS-1:0][WIDTH-1:0]
  // NUM_OPERANDS=3, WIDTH=32 → [2:0][31:0]
  logic [2:0][31:0]     operands;

  // Exception status from fpnew_top
  fpnew_pkg::status_t   status;

  //==========================================================================
  // Input packing
  //==========================================================================

  // Map Hector operand names to fpnew_top packed operands
  //   operands[0] = multiplier (A)
  //   operands[1] = multiplicand (B)
  //   operands[2] = addend (C)
  assign operands[0] = multiplier;
  assign operands[1] = multiplicand;
  assign operands[2] = addend;

  //==========================================================================
  // fpnew_top instance
  //
  // Fixed control signals (per Phase 2 of the migration plan):
  //
  //   Signal          | Value  | Rationale
  //   ----------------|--------|------------------------------------------
  //   src_fmt_i       | FP32   | Fixed input format
  //   dst_fmt_i       | FP32   | Fixed output format / format slice select
  //   int_fmt_i       | INT32  | Conversion unused, must not be X/floating
  //   vectorial_op_i  | 0      | No SIMD/vector semantics
  //   simd_mask_i     | '1     | All lanes active (NumLanes=1 with our config)
  //   tag_i           | '0     | Tag unused in functional verification
  //   flush_i         | 0      | No flush-to-zero interference
  //   out_ready_i     | 1      | Always accept output (matches current wrapper)
  //   in_valid_i      | go     | Hector go pulse → streaming valid
  //
  // Features (FORMAL_RV32F_FEATURES):
  //   Width=32, EnableVectors=0, EnableNanBox=1,
  //   FpFmtMask=5'b10000, IntFmtMask=4'b0010
  //
  // Implementation (FORMAL_ADDMUL_FP32_ONLY):
  //   ADDMUL×FP32 = PARALLEL, all other opgroup×format = DISABLED
  //   PipeRegs = 0, PipeConfig = BEFORE
  //==========================================================================

  fpnew_top #(
    .Features       (FORMAL_RV32F_FEATURES),
    .Implementation (FORMAL_ADDMUL_FP32_ONLY),
    .TagType        (logic)
  ) i_fpnew_top (
    .clk_i          (clock),
    .rst_ni         (resetN),

    // ---- Operands and operation control ----
    .operands_i     (operands),
    .rnd_mode_i     (fpnew_pkg::roundmode_e'(rounding_mode)),
    .op_i           (fpnew_pkg::operation_e'(op_i)),
    .op_mod_i       (op_mod_i),

    // ---- Format / SIMD control (all fixed) ----
    .src_fmt_i      (fpnew_pkg::FP32),
    .dst_fmt_i      (fpnew_pkg::FP32),
    .int_fmt_i      (fpnew_pkg::INT32),
    .vectorial_op_i (1'b0),
    .tag_i          (1'b0),
    .simd_mask_i    ('1),

    // ---- Input handshake ----
    .in_valid_i     (go),
    .in_ready_o     (),             // unused — we drive with go pulse
    .flush_i        (1'b0),

    // ---- Output ----
    .result_o       (result),
    .status_o       (status),
    .tag_o          (),             // unused — no tag tracking

    // ---- Output handshake ----
    .out_valid_o    (valid),
    .out_ready_i    (1'b1),         // always ready to accept output

    // ---- Status (optional debug) ----
    .busy_o         (),
    .early_valid_o  ()
  );

  //==========================================================================
  // Output mapping
  //==========================================================================

  // Map fpnew_pkg::status_t to Hector 5-bit exceptions: {NV, DZ, OF, UF, NX}
  //   status.NV = Invalid Operation  (e.g., 0×∞, ∞−∞, sNaN input)
  //   status.DZ = Divide by Zero     (always 0 for FMA path)
  //   status.OF = Overflow
  //   status.UF = Underflow
  //   status.NX = Inexact
  assign exceptions = {
    status.NV,   // bit 4
    status.DZ,   // bit 3
    status.OF,   // bit 2
    status.UF,   // bit 1
    status.NX    // bit 0
  };

endmodule
