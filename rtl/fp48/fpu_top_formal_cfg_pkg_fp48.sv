//============================================================================
// fpu_top_formal_cfg_pkg_fp48.sv — Formal-Only Configuration for fpnew_top (FP48)
//
// Companion to rtl/fpnew_pkg_fp48.sv. Provides FP48-only Features and
// Implementation constants for the fpnew_top-based wrapper.
//
// NOTE: This package must be compiled together with rtl/fpnew_pkg_fp48.sv
//       (the FP48-extended fpnew_pkg), NOT with the original fpnew_pkg.
//
// Design decisions:
//   - FP48 only (E11M36, bias=1023, native width=48)
//   - ADDMUL opgroup only (no DIVSQRT, NONCOMP, CONV)
//   - No vectors/SIMD
//   - No pipeline registers (combinational path)
//   - NaN-boxing disabled at fpnew_top level (wrapper handles 64↔48)
//
// References:
//   - rtl/fpnew_pkg_fp48.sv: FP48-extended fpnew_pkg
//   - rtl/fpu_top_wrap_fp48.sv: FP48 top wrapper
//============================================================================

package fpu_top_formal_cfg_pkg_fp48;
  import fpnew_pkg::*;  // resolves to fpnew_pkg_fp48.sv (drop-in replacement)

  //--------------------------------------------------------------------------
  // FORMAL_RV48_FEATURES — FP48-only feature set
  //
  //   Width=48 (native FP48 width, wrapper handles 64-bit container)
  //   EnableVectors=0, EnableNanBox=0,
  //   FpFmtMask=6'b000001 (FP48 only), IntFmtMask=4'b0000
  //
  // NaN-boxing: disabled at fpnew_top level because Width == fp_width(FP48),
  // so no internal boxing check is generated. The wrapper (fpu_top_wrap_fp48)
  // handles 64↔48 container conversion with NaN-boxing on the output.
  //--------------------------------------------------------------------------
  localparam fpu_features_t FORMAL_RV48_FEATURES = '{
    Width:         48,
    EnableVectors: 1'b0,
    EnableNanBox:  1'b0,
    FpFmtMask:     6'b000001,
    IntFmtMask:    4'b0000
  };

  //--------------------------------------------------------------------------
  // FORMAL_ADDMUL_FP48_ONLY — Minimal implementation (FP48 only)
  //
  // UnitTypes layout: {ADDMUL, DIVSQRT, NONCOMP, CONV}
  //                 × {FP32, FP64, FP16, FP8, FP16ALT, FP48}
  //
  //   Opgroup  | FP32     | FP64     | FP16     | FP8      | FP16ALT  | FP48
  //   ---------|----------|----------|----------|----------|----------|----------
  //   ADDMUL   | DISABLED | DISABLED | DISABLED | DISABLED | DISABLED | PARALLEL
  //   DIVSQRT  | DISABLED | DISABLED | DISABLED | DISABLED | DISABLED | DISABLED
  //   NONCOMP  | DISABLED | DISABLED | DISABLED | DISABLED | DISABLED | DISABLED
  //   CONV     | DISABLED | DISABLED | DISABLED | DISABLED | DISABLED | DISABLED
  //
  // PipeRegs: all 0 (combinational). PipeConfig: BEFORE.
  //--------------------------------------------------------------------------
  localparam fpu_implementation_t FORMAL_ADDMUL_FP48_ONLY = '{
    PipeRegs: '{default: 0},
    UnitTypes: '{
      // ADDMUL: FP48 enabled as PARALLEL, all other formats disabled
      '{DISABLED, DISABLED, DISABLED, DISABLED, DISABLED, PARALLEL},
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
