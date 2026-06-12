//============================================================================
// fpu_top_wrap_fp48.sv — Hector DP Implementation Wrapper for fpnew_top (FP48)
//
// Wraps the cvfpu fpnew_top module into the Hector DPV interface convention:
//   - go/valid handshake (single pulse) instead of valid/ready streaming
//   - Standardized port names matching the spec model (fma_spec_wrap_fp48.cpp)
//   - Fixed FP48 format, ADDMUL-only operation group
//   - All other formats/opgroups disabled via Features/Implementation
//   - 64-bit container: external ports are 64-bit; fpnew_top operates on
//     native 48-bit width; wrapper handles 64↔48 conversion
//
// Differences from fma_wrap_fp48.sv (direct fpnew_fma wrapper):
//   - Instantiates fpnew_top instead of fpnew_fma
//   - Internal control signals (src_fmt_i, dst_fmt_i, vectorial_op_i, etc.)
//     are fixed to minimal values rather than being exposed as ports
//   - Uses fpu_top_formal_cfg_pkg_fp48 for Features/Implementation constants
//   - Result passes through fpnew_top's opgroup routing + rr_arb_tree output
//   - This path validates the full fpnew_top infrastructure for FP48
//
// BUILD: Must compile rtl/fpnew_pkg_fp48.sv (NOT third_party/cvfpu/src/fpnew_pkg.sv)
//        and rtl/fpu_top_formal_cfg_pkg_fp48.sv (NOT fpu_top_formal_cfg_pkg.sv)
//
// References:
//   - rtl/fpu_top_wrap_fp32.sv: FP32 top-level wrapper (baseline)
//   - cvfpu/src/fpnew_top.sv: Top-level FPU with opgroup routing + arbitration
//   - rtl/fpnew_pkg_fp48.sv: FP48-extended fpnew_pkg
//============================================================================

module fpu_top_wrap_fp48
  import fpnew_pkg::*;                    // resolves to fpnew_pkg_fp48.sv
  import fpu_top_formal_cfg_pkg_fp48::*;  // FP48-specific config
#(
  // Number of pipeline registers.
  //   In the minimal formal configuration, all PipeRegs are hardcoded to 0
  //   via FORMAL_ADDMUL_FP48_ONLY.
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
  input  logic        op_mod_i,       // 0/1 selects variant per operation

  // ---- Clock and reset ----
  input  logic        clock,
  input  logic        resetN          // Active-low reset (Hector convention)
);

  //==========================================================================
  // Constants
  //==========================================================================
  localparam int unsigned FP48_WIDTH = fp_width(FP48);  // = 48
  localparam int unsigned NUM_OPERANDS = 3;

  //==========================================================================
  // Internal signals
  //==========================================================================

  // fpnew_top uses native 48-bit width internally
  // Packed operands: [NUM_OPERANDS-1:0][FP48_WIDTH-1:0] = [2:0][47:0]
  logic [NUM_OPERANDS-1:0][FP48_WIDTH-1:0] fpu_operands;
  logic [FP48_WIDTH-1:0]                   fpu_result;

  // Exception status from fpnew_top
  fpnew_pkg::status_t   status;

  //==========================================================================
  // 64-bit container ↔ 48-bit payload conversion
  //==========================================================================

  // Input: extract low 48 bits from 64-bit container
  assign fpu_operands[0] = multiplier[FP48_WIDTH-1:0];
  assign fpu_operands[1] = multiplicand[FP48_WIDTH-1:0];
  assign fpu_operands[2] = addend[FP48_WIDTH-1:0];

  //==========================================================================
  // fpnew_top instance
  //
  // Fixed control signals:
  //
  //   Signal          | Value  | Rationale
  //   ----------------|--------|------------------------------------------
  //   src_fmt_i       | FP48   | Fixed input format
  //   dst_fmt_i       | FP48   | Fixed output format
  //   int_fmt_i       | INT32  | Conversion unused, must not be X/floating
  //   vectorial_op_i  | 0      | No SIMD/vector semantics
  //   simd_mask_i     | '1     | All lanes active (NumLanes=1 with our config)
  //   tag_i           | '0     | Tag unused in functional verification
  //   flush_i         | 0      | No flush-to-zero interference
  //   out_ready_i     | 1      | Always accept output
  //   in_valid_i      | go     | Hector go pulse → streaming valid
  //
  // Features (FORMAL_RV48_FEATURES):
  //   Width=48, EnableVectors=0, EnableNanBox=0,
  //   FpFmtMask=6'b100000 (FP48 only), IntFmtMask=4'b0000
  //
  //   NOTE: Width=48 (not 64) because fpnew_top operates on native FP48
  //   width internally. The wrapper handles 64↔48 container conversion.
  //   EnableNanBox=0 because Width == fp_width(FP48), so no boxing check
  //   is needed at the fpnew_top level.
  //
  // Implementation (FORMAL_ADDMUL_FP48_ONLY):
  //   ADDMUL×FP48 = PARALLEL, all other opgroup×format = DISABLED
  //   PipeRegs = 0, PipeConfig = BEFORE
  //==========================================================================

  fpnew_top #(
    .Features       (FORMAL_RV48_FEATURES),
    .Implementation (FORMAL_ADDMUL_FP48_ONLY),
    .TagType        (logic)
  ) i_fpnew_top (
    .clk_i          (clock),
    .rst_ni         (resetN),

    // ---- Operands and operation control ----
    .operands_i     (fpu_operands),
    .rnd_mode_i     (fpnew_pkg::roundmode_e'(rounding_mode)),
    .op_i           (fpnew_pkg::operation_e'(op_i)),
    .op_mod_i       (op_mod_i),

    // ---- Format / SIMD control (all fixed) ----
    .src_fmt_i      (fpnew_pkg::FP48),
    .dst_fmt_i      (fpnew_pkg::FP48),
    .int_fmt_i      (fpnew_pkg::INT32),
    .vectorial_op_i (1'b0),
    .tag_i          (1'b0),
    .simd_mask_i    ('1),

    // ---- Input handshake ----
    .in_valid_i     (go),
    .in_ready_o     (),             // unused — we drive with go pulse
    .flush_i        (1'b0),

    // ---- Output ----
    .result_o       (fpu_result),
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

  // Result: extend 48-bit payload to 64-bit NaN-boxed container
  //   result[63:48] = 16'hffff  (NaN-box)
  //   result[47:0]  = FP48 result
  assign result = {16'hffff, fpu_result};

  // Map fpnew_pkg::status_t to Hector 5-bit exceptions: {NV, DZ, OF, UF, NX}
  assign exceptions = {
    status.NV,   // bit 4
    status.DZ,   // bit 3
    status.OF,   // bit 2
    status.UF,   // bit 1
    status.NX    // bit 0
  };

endmodule
