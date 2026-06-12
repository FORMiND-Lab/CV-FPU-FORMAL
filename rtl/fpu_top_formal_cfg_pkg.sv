//============================================================================
// fpu_top_formal_cfg_pkg.sv — Formal-Only Minimal Configuration for fpnew_top
//
// Defines minimal Features and Implementation constants for formal verification
// of the fpnew_top-based wrapper. Aggressively disables unused hardware to keep
// the proof cone of influence minimal.
//
// Design decisions (per top_migration_plan.md Phase 3 & 4):
//   - FP32 only (no FP64, FP16, FP8, FP16ALT)
//   - ADDMUL opgroup only (no DIVSQRT, NONCOMP, CONV)
//   - No vectors/SIMD
//   - No pipeline registers (combinational path)
//   - NaN-boxing enabled (but inactive for FP32 @ WIDTH=32)
//
// References:
//   - cvfpu/src/fpnew_pkg.sv: RV32F features, fpu_implementation_t types
//   - temp/top_plan.md: Phase 3 (Features) & Phase 4 (Implementation)
//============================================================================

package fpu_top_formal_cfg_pkg;
  import fpnew_pkg::*;

  //--------------------------------------------------------------------------
  // FORMAL_RV32F_FEATURES — FP32-only feature set
  //
  // Equivalent to fpnew_pkg::RV32F:
  //   Width=32, EnableVectors=0, EnableNanBox=1,
  //   FpFmtMask=5'b10000 (FP32 only), IntFmtMask=4'b0010 (INT32 only)
  //
  // NaN-boxing safety: the fpnew_top NaN-boxing check condition is
  //   Features.EnableNanBox && (FP_WIDTH < WIDTH)
  // With Width=32 and FP32: FP_WIDTH=32, so 32 < 32 is false — no boxing
  // constraints are generated for FP32. EnableNanBox=1 is harmless here.
  //--------------------------------------------------------------------------
  localparam fpu_features_t FORMAL_RV32F_FEATURES = '{
    Width:         32,
    EnableVectors: 1'b0,
    EnableNanBox:  1'b1,
    FpFmtMask:     5'b10000,
    IntFmtMask:    4'b0010
  };

  //--------------------------------------------------------------------------
  // FORMAL_ADDMUL_FP32_ONLY — Minimal implementation
  //
  // UnitTypes layout: {ADDMUL, DIVSQRT, NONCOMP, CONV} × {FP32,FP64,FP16,FP8,FP16ALT}
  //
  //   Opgroup  | FP32     | FP64     | FP16     | FP8      | FP16ALT
  //   ---------|----------|----------|----------|----------|----------
  //   ADDMUL   | PARALLEL | DISABLED | DISABLED | DISABLED | DISABLED
  //   DIVSQRT  | DISABLED | DISABLED | DISABLED | DISABLED | DISABLED
  //   NONCOMP  | DISABLED | DISABLED | DISABLED | DISABLED | DISABLED
  //   CONV     | DISABLED | DISABLED | DISABLED | DISABLED | DISABLED
  //
  // When an opgroup has no enabled formats, fpnew_opgroup_block drives:
  //   in_ready=0, out_valid=0, busy=0, early_valid=0
  // This prevents disabled opgroups from corrupting the output arbiter.
  //
  // PipeRegs: all 0 (combinational). PipeConfig: BEFORE.
  //--------------------------------------------------------------------------
  localparam fpu_implementation_t FORMAL_ADDMUL_FP32_ONLY = '{
    PipeRegs: '{default: 0},
    UnitTypes: '{
      // ADDMUL: FP32 enabled as PARALLEL, all other formats disabled
      '{PARALLEL, DISABLED, DISABLED, DISABLED, DISABLED},
      // DIVSQRT: all disabled
      '{default: DISABLED},
      // NONCOMP: all disabled
      '{default: DISABLED},
      // CONV: all disabled
      '{default: DISABLED}
    },
    PipeConfig: BEFORE
  };

endpackage
