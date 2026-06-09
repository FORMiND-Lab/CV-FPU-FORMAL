set _hector_comp_use_new_flow true
set _hector_softfloat_version custom
set_hector_multiple_solve_scripts true
set_hector_multiple_solve_scripts_list {orch_multipliers orch_custom_fma}

proc compile_spec {} {
    create_design -name spec -top hector_wrapper
    cppan -I../../third_party/softfloat/include \
          -I../../third_party/softfloat/source/RISCV \
          ../spec/fma_spec_fp16.cpp \
          ../../third_party/softfloat/source/f16_mulAdd.c \
          ../../third_party/softfloat/source/s_mulAddF16.c \
          ../../third_party/softfloat/source/s_roundPackToF16.c \
          ../../third_party/softfloat/source/s_normRoundPackToF16.c \
          ../../third_party/softfloat/source/s_normSubnormalF16Sig.c \
          ../../third_party/softfloat/source/s_shortShiftRightJam64.c \
          ../../third_party/softfloat/source/s_shiftRightJam32.c \
          ../../third_party/softfloat/source/s_shiftRightJam64.c \
          ../../third_party/softfloat/source/s_countLeadingZeros64.c \
          ../../third_party/softfloat/source/s_countLeadingZeros32.c \
          ../../third_party/softfloat/source/s_countLeadingZeros16.c \
          ../../third_party/softfloat/source/s_countLeadingZeros8.c \
          ../../third_party/softfloat/source/RISCV/s_propagateNaNF16UI.c \
          ../../third_party/softfloat/source/RISCV/softfloat_raiseFlags.c \
          ../../third_party/softfloat/source/softfloat_state.c
    compile_design spec
}

proc compile_impl {} {
    create_design -name impl -top fma_hector_wrap_fp16 -clock clock -reset resetN -negReset
    vcs -sverilog \
        +incdir+../../third_party/cvfpu/common_cells/include \
        ../../third_party/cvfpu/fpnew_pkg.sv \
        ../../third_party/cvfpu/fpnew_classifier.sv \
        ../../third_party/cvfpu/fpnew_rounding.sv \
        ../../third_party/cvfpu/fpnew_fma.sv \
        ../../third_party/cvfpu/common_cells/src/cf_math_pkg.sv \
        ../../third_party/cvfpu/common_cells/src/lzc.sv \
        ../../third_party/cvfpu/common_cells/src/rr_arb_tree.sv \
        ../rtl/fma_hector_wrap_fp16.sv
    compile_design impl
}

proc ual_main {} {
    assume impl.go(1) == 1
    map_by_name -inputs -specphase 1 -implphase 1
    assume spec.rounding_mode(1) < 5
    assume impl.op_i(1) == 0
    assume impl.op_mod_i(1) == 0
    lemma result_eq = spec.result(1) == impl.result(1)
    lemma except_eq = spec.exceptions(1) == impl.exceptions(1)
    set_resource_limit 36000

}

proc case_split_fma16 {} {
    caseSplitStrategy basic

    caseBegin A_inf_NaN
    caseAssume (spec.multiplier(1)[14:10] == 5'h1f)

    caseBegin B_inf_NaN
    caseAssume (spec.multiplicand(1)[14:10] == 5'h1f)

    caseBegin C_inf_NaN
    caseAssume (spec.addend(1)[14:10] == 5'h1f)

    caseBegin norm_norm_norm
    caseAssume (spec.multiplier(1)[14:10] != 5'h00)
    caseAssume (spec.multiplier(1)[14:10] != 5'h1f)
    caseAssume (spec.multiplicand(1)[14:10] != 5'h00)
    caseAssume (spec.multiplicand(1)[14:10] != 5'h1f)
    caseAssume (spec.addend(1)[14:10] != 5'h00)
    caseAssume (spec.addend(1)[14:10] != 5'h1f)

    caseBegin A_dnorm
    caseAssume (spec.multiplier(1)[14:10] == 5'h00)
    caseAssume (spec.multiplicand(1)[14:10] != 5'h00)
    caseAssume (spec.multiplicand(1)[14:10] != 5'h1f)
    caseAssume (spec.addend(1)[14:10] != 5'h00)
    caseAssume (spec.addend(1)[14:10] != 5'h1f)
    caseEnumerate adn1 -expr spec.multiplier[9:0] -parent A_dnorm -type leading1

    caseBegin B_dnorm
    caseAssume (spec.multiplicand(1)[14:10] == 5'h00)
    caseAssume (spec.multiplier(1)[14:10] != 5'h00)
    caseAssume (spec.multiplier(1)[14:10] != 5'h1f)
    caseAssume (spec.addend(1)[14:10] != 5'h00)
    caseAssume (spec.addend(1)[14:10] != 5'h1f)
    caseEnumerate bdn1 -expr spec.multiplicand[9:0] -parent B_dnorm -type leading1

    caseBegin C_dnorm
    caseAssume (spec.addend(1)[14:10] == 5'h00)
    caseAssume (spec.multiplier(1)[14:10] != 5'h00)
    caseAssume (spec.multiplier(1)[14:10] != 5'h1f)
    caseAssume (spec.multiplicand(1)[14:10] != 5'h00)
    caseAssume (spec.multiplicand(1)[14:10] != 5'h1f)
    caseEnumerate cdn1 -expr spec.addend[9:0] -parent C_dnorm -type leading1

    caseBegin AB_dnorm
    caseAssume (spec.multiplier(1)[14:10] == 5'h00)
    caseAssume (spec.multiplicand(1)[14:10] == 5'h00)
    caseAssume (spec.addend(1)[14:10] != 5'h00)
    caseAssume (spec.addend(1)[14:10] != 5'h1f)

    caseBegin BC_dnorm
    caseAssume (spec.multiplicand(1)[14:10] == 5'h00)
    caseAssume (spec.addend(1)[14:10] == 5'h00)
    caseAssume (spec.multiplier(1)[14:10] != 5'h00)
    caseAssume (spec.multiplier(1)[14:10] != 5'h1f)
    caseEnumerate bcdn -expr spec.multiplicand[9:0] -parent BC_dnorm -type leading1

    caseBegin AC_dnorm
    caseAssume (spec.multiplier(1)[14:10] == 5'h00)
    caseAssume (spec.addend(1)[14:10] == 5'h00)
    caseAssume (spec.multiplicand(1)[14:10] != 5'h00)
    caseAssume (spec.multiplicand(1)[14:10] != 5'h1f)
    caseEnumerate acdn -expr spec.multiplier[9:0] -parent AC_dnorm -type leading1

    caseBegin ABC_dnorm
    caseAssume (spec.multiplier(1)[14:10] == 5'h00)
    caseAssume (spec.multiplicand(1)[14:10] == 5'h00)
    caseAssume (spec.addend(1)[14:10] == 5'h00)
    caseEnumerate abcdn -expr spec.multiplier[9:0] -parent ABC_dnorm -type leading1
}

proc make {} {
    compile_spec
    compile_impl
    compose
}

proc run_main {} {
    set_host_file "host.qsub"
    set_user_assumes_lemmas_procedure "ual_main"
    set_hector_case_splitting_procedure "case_split_fma16"
    set_fml_var orch_distrib 16
    solveNB p
}
