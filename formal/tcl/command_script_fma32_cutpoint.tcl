set _hector_comp_use_new_flow true
set _hector_softfloat_version custom

proc compile_spec {} {
    create_design -name spec -top hector_wrapper
    cppan -I../../third_party/softfloat/include \
          -I../../third_party/softfloat/source/RISCV \
          ../spec/fma_spec.cpp \
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

proc compile_impl {} {
    create_design -name impl -top fma_hector_wrap -clock clock -reset resetN -negReset
    set_cutpoint fma_hector_wrap.i_fma.product_shifted
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

proc ual_main {} {
    assume impl.go(1) == 1
    map_by_name -inputs -specphase 1 -implphase 1
    assume spec.rounding_mode(1) < 5
    assume impl.op_i(1) == 0
    assume impl.op_mod_i(1) == 0
    assume impl.i_fma.product_shifted(1) == \
        (impl.i_fma.mantissa_a(1) * impl.i_fma.mantissa_b(1)) << 2
    lemma result_eq = spec.result(1) == impl.result(1)
    lemma except_eq = spec.exceptions(1) == impl.exceptions(1)
    set_resource_limit 36000
    set_hector_multiple_solve_scripts false
}

proc case_split_fma32 {} {
    caseSplitStrategy basic
    caseBegin A_inf_NaN
    caseAssume (spec.multiplier(1)[30:23] == 8'hff)
    caseBegin B_inf_NaN
    caseAssume (spec.multiplicand(1)[30:23] == 8'hff)
    caseBegin C_inf_NaN
    caseAssume (spec.addend(1)[30:23] == 8'hff)
    caseBegin norm_norm_norm
    caseAssume (spec.multiplier(1)[30:23] != 8'h00)
    caseAssume (spec.multiplier(1)[30:23] != 8'hff)
    caseAssume (spec.multiplicand(1)[30:23] != 8'h00)
    caseAssume (spec.multiplicand(1)[30:23] != 8'hff)
    caseAssume (spec.addend(1)[30:23] != 8'h00)
    caseAssume (spec.addend(1)[30:23] != 8'hff)
    caseBegin A_dnorm
    caseAssume (spec.multiplier(1)[30:23] == 8'h00)
    caseAssume (spec.multiplicand(1)[30:23] != 8'h00)
    caseAssume (spec.multiplicand(1)[30:23] != 8'hff)
    caseAssume (spec.addend(1)[30:23] != 8'h00)
    caseAssume (spec.addend(1)[30:23] != 8'hff)
    caseBegin B_dnorm
    caseAssume (spec.multiplicand(1)[30:23] == 8'h00)
    caseAssume (spec.multiplier(1)[30:23] != 8'h00)
    caseAssume (spec.multiplier(1)[30:23] != 8'hff)
    caseAssume (spec.addend(1)[30:23] != 8'h00)
    caseAssume (spec.addend(1)[30:23] != 8'hff)
    caseBegin C_dnorm
    caseAssume (spec.addend(1)[30:23] == 8'h00)
    caseAssume (spec.multiplier(1)[30:23] != 8'h00)
    caseAssume (spec.multiplier(1)[30:23] != 8'hff)
    caseAssume (spec.multiplicand(1)[30:23] != 8'h00)
    caseAssume (spec.multiplicand(1)[30:23] != 8'hff)
    caseEnumerate cdn1 -expr spec.addend[22:0] -parent C_dnorm -type leading1
    caseBegin AB_dnorm
    caseAssume (spec.multiplier(1)[30:23] == 8'h00)
    caseAssume (spec.multiplicand(1)[30:23] == 8'h00)
    caseAssume (spec.addend(1)[30:23] != 8'h00)
    caseAssume (spec.addend(1)[30:23] != 8'hff)
    caseBegin BC_dnorm
    caseAssume (spec.multiplicand(1)[30:23] == 8'h00)
    caseAssume (spec.addend(1)[30:23] == 8'h00)
    caseAssume (spec.multiplier(1)[30:23] != 8'h00)
    caseAssume (spec.multiplier(1)[30:23] != 8'hff)
    caseBegin AC_dnorm
    caseAssume (spec.multiplier(1)[30:23] == 8'h00)
    caseAssume (spec.addend(1)[30:23] == 8'h00)
    caseAssume (spec.multiplicand(1)[30:23] != 8'h00)
    caseAssume (spec.multiplicand(1)[30:23] != 8'hff)
    caseBegin ABC_dnorm
    caseAssume (spec.multiplier(1)[30:23] == 8'h00)
    caseAssume (spec.multiplicand(1)[30:23] == 8'h00)
    caseAssume (spec.addend(1)[30:23] == 8'h00)
}

proc make {} {
    compile_spec
    compile_impl
    compose
}

proc run_main {} {
    set_user_assumes_lemmas_procedure "ual_main"
    set_hector_case_splitting_procedure "case_split_fma32"
    set_fml_var orch_distrib 8
    solveNB p
}
