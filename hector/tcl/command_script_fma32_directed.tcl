#=============================================================================
# command_script_fma32_directed.tcl — Quick sanity check with directed cases
#
# Instead of exhaustive case splitting (97-bit space), this script constrains
# inputs to the 11 directed test cases from tests/directed_cases.hex.
# Useful for fast smoke-testing the Hector flow.
#
# Usage:
#   cd hector/run
#   vcf -f ../tcl/command_script_fma32_directed.tcl -fmode DPV
#   vcf> make
#   vcf> run
#=============================================================================

set _hector_comp_use_new_flow true
set _hector_softfloat_version custom

#=============================================================================
proc compile_spec {} {
    create_design -name spec -top hector_wrapper

    cppan -I../../third_party/softfloat/include \
          -I../../third_party/softfloat/source/RISCV \
          ../spec/fma_spec.cpp \
          \
          ../../third_party/softfloat/source/f32_mulAdd.c \
          ../../third_party/softfloat/source/s_mulAddF32.c \
          ../../third_party/softfloat/source/s_roundPackToF32.c \
          ../../third_party/softfloat/source/s_normRoundPackToF32.c \
          ../../third_party/softfloat/source/s_normSubnormalF32Sig.c \
          ../../third_party/softfloat/source/s_shortShiftRightJam64.c \
          ../../third_party/softfloat/source/s_shiftRightJam32.c \
          ../../third_party/softfloat/source/s_shiftRightJam64.c \
          ../../third_party/softfloat/source/s_countLeadingZeros64.c \
          ../../third_party/softfloat/source/s_countLeadingZeros32.c \
          ../../third_party/softfloat/source/s_countLeadingZeros8.c \
          ../../third_party/softfloat/source/RISCV/s_propagateNaNF32UI.c \
          ../../third_party/softfloat/source/RISCV/softfloat_raiseFlags.c \
          ../../third_party/softfloat/source/softfloat_state.c

    compile_design spec
}

#=============================================================================
proc compile_impl {} {
    create_design -name impl -top fma_hector_wrap -clock clock -reset resetN -negReset

    vcs -sverilog \
        +incdir+../../third_party/cvfpu/common_cells/include \
        ../../third_party/cvfpu/fpnew_pkg.sv \
        ../../third_party/cvfpu/fpnew_classifier.sv \
        ../../third_party/cvfpu/fpnew_rounding.sv \
        ../../third_party/cvfpu/fpnew_fma.sv \
        ../../third_party/cvfpu/common_cells/src/cf_math_pkg.sv \
        ../../third_party/cvfpu/common_cells/src/lzc.sv \
        ../../third_party/cvfpu/common_cells/src/rr_arb_tree.sv \
        ../rtl/fma_hector_wrap.sv

    compile_design impl
}

#=============================================================================
# ual — Constrain inputs to the 11 directed test cases only
#
# Each line from tests/directed_cases.hex is encoded as:
#   (multiplier == A) && (multiplicand == B) && (addend == C) && (rm == RM)
#
# This reduces the input space from 2^97 to just 11 points → seconds.
#=============================================================================
proc ual {} {
    assume impl.go(1) == 1
    map_by_name -inputs -specphase 1 -implphase 1
    assume spec.rounding_mode(1) < 5

    # ---- Sanity Cases ----
    # 3F800000 40000000 40400000 0 0   # 1.0 * 2.0 + 3.0 = 5.0
    # 00000000 40A00000 40400000 0 0   # 0.0 * 5.0 + 3.0 = 3.0
    # 3FC00000 40000000 3F000000 0 0   # 1.5 * 2.0 + 0.5 = 3.5
    # BF800000 40000000 40400000 0 0   # -1.0 * 2.0 + 3.0 = 1.0
    # ---- Zero Cases ----
    # 00000000 00000000 00000000 0 0   # 0.0 * 0.0 + 0.0
    # 3F800000 00000000 3F800000 0 0   # 1.0 * 0.0 + 1.0
    # 80000000 3F800000 00000000 0 0   # (-0.0) * 1.0 + 0.0
    # ---- Infinity Cases ----
    # 7F800000 3F800000 3F800000 0 0   # +inf * 1.0 + 1.0
    # FF800000 3F800000 3F800000 0 0   # -inf * 1.0 + 1.0
    # ---- NaN Cases ----
    # 7FC00000 3F800000 3F800000 0 0   # qNaN * 1.0 + 1.0
    # 7F800001 3F800000 3F800000 0 0   # sNaN * 1.0 + 1.0

    assume {
        (spec.multiplier(1) == 32'h3F800000 && spec.multiplicand(1) == 32'h40000000 && spec.addend(1) == 32'h40400000)
        ||
        (spec.multiplier(1) == 32'h00000000 && spec.multiplicand(1) == 32'h40A00000 && spec.addend(1) == 32'h40400000)
        ||
        (spec.multiplier(1) == 32'h3FC00000 && spec.multiplicand(1) == 32'h40000000 && spec.addend(1) == 32'h3F000000)
        ||
        (spec.multiplier(1) == 32'hBF800000 && spec.multiplicand(1) == 32'h40000000 && spec.addend(1) == 32'h40400000)
        ||
        (spec.multiplier(1) == 32'h00000000 && spec.multiplicand(1) == 32'h00000000 && spec.addend(1) == 32'h00000000)
        ||
        (spec.multiplier(1) == 32'h3F800000 && spec.multiplicand(1) == 32'h00000000 && spec.addend(1) == 32'h3F800000)
        ||
        (spec.multiplier(1) == 32'h80000000 && spec.multiplicand(1) == 32'h3F800000 && spec.addend(1) == 32'h00000000)
        ||
        (spec.multiplier(1) == 32'h7F800000 && spec.multiplicand(1) == 32'h3F800000 && spec.addend(1) == 32'h3F800000)
        ||
        (spec.multiplier(1) == 32'hFF800000 && spec.multiplicand(1) == 32'h3F800000 && spec.addend(1) == 32'h3F800000)
        ||
        (spec.multiplier(1) == 32'h7FC00000 && spec.multiplicand(1) == 32'h3F800000 && spec.addend(1) == 32'h3F800000)
        ||
        (spec.multiplier(1) == 32'h7F800001 && spec.multiplicand(1) == 32'h3F800000 && spec.addend(1) == 32'h3F800000)
    }

    # RM is always 0 (RNE) in the directed cases
    assume spec.rounding_mode(1) == 0

    lemma result_eq  = spec.result(1) == impl.result(1)
    lemma except_eq  = spec.exceptions(1) == impl.exceptions(1)

    set_resource_limit 600
}

#=============================================================================
proc make {} {
    compile_spec
    compile_impl
    compose
}

#=============================================================================
proc run {} {
    set_user_assumes_lemmas_procedure "ual"
    solveNB p
}
