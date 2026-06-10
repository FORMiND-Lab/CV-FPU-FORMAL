#============================================================================
# command_script_fp32_sub.tcl — FP32 SUB (op_i=2, op_mod=1)
# Uses unified spec: fma_spec_wrap_fp32.cpp
#============================================================================

set _hector_comp_use_new_flow true
set _hector_softfloat_version custom
set _label "FP32 SUB"
set_hector_multiple_solve_scripts true
set_hector_multiple_solve_scripts_list {orch_multipliers orch_custom_fma}

proc compile_spec {} {
    create_design -name spec -top hector_wrapper
    cppan -I../../third_party/softfloat/include \
          -I../../third_party/softfloat/source/RISCV \
          ../spec/fma_spec_wrap_fp32.cpp \
          ../../third_party/softfloat/source/f32_mulAdd.c \
          ../../third_party/softfloat/source/s_mulAddF32.c \
          ../../third_party/softfloat/source/f32_add.c \
          ../../third_party/softfloat/source/s_addMagsF32.c \
          ../../third_party/softfloat/source/f32_sub.c \
          ../../third_party/softfloat/source/s_subMagsF32.c \
          ../../third_party/softfloat/source/f32_mul.c \
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
    vcs -sverilog \
        +incdir+../../third_party/cvfpu/common_cells/include \
        ../../third_party/cvfpu/fpnew_pkg.sv \
        ../../third_party/cvfpu/fpnew_classifier.sv \
        ../../third_party/cvfpu/fpnew_rounding.sv \
        ../../third_party/cvfpu/fpnew_fma.sv \
        ../../third_party/cvfpu/common_cells/src/cf_math_pkg.sv \
        ../../third_party/cvfpu/common_cells/src/lzc.sv \
        ../../third_party/cvfpu/common_cells/src/rr_arb_tree.sv \
        ../../rtl/fma_wrap_fp32.sv
    compile_design impl
}

proc ual_main {} {
    assume impl.go(1) == 1
    map_by_name -inputs -specphase 1 -implphase 1
    assume spec.rounding_mode(1) < 5
    assume impl.op_i(1) == 2
    assume impl.op_mod_i(1) == 1
    lemma result_eq = spec.result(1) == impl.result(1)
    lemma except_eq = spec.exceptions(1) == impl.exceptions(1)
    set_resource_limit 36000
}

proc case_split_fp32 {} {
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
    caseEnumerate adn1 -expr spec.multiplier[22:0] -parent A_dnorm -type leading1

    caseBegin B_dnorm
    caseAssume (spec.multiplicand(1)[30:23] == 8'h00)
    caseAssume (spec.multiplier(1)[30:23] != 8'h00)
    caseAssume (spec.multiplier(1)[30:23] != 8'hff)
    caseAssume (spec.addend(1)[30:23] != 8'h00)
    caseAssume (spec.addend(1)[30:23] != 8'hff)
    caseEnumerate bdn1 -expr spec.multiplicand[22:0] -parent B_dnorm -type leading1

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
    caseEnumerate bcdn -expr spec.multiplicand[22:0] -parent BC_dnorm -type leading1

    caseBegin AC_dnorm
    caseAssume (spec.multiplier(1)[30:23] == 8'h00)
    caseAssume (spec.addend(1)[30:23] == 8'h00)
    caseAssume (spec.multiplicand(1)[30:23] != 8'h00)
    caseAssume (spec.multiplicand(1)[30:23] != 8'hff)
    caseEnumerate acdn -expr spec.multiplier[22:0] -parent AC_dnorm -type leading1

    caseBegin ABC_dnorm
    caseAssume (spec.multiplier(1)[30:23] == 8'h00)
    caseAssume (spec.multiplicand(1)[30:23] == 8'h00)
    caseAssume (spec.addend(1)[30:23] == 8'h00)
    caseEnumerate abcdn -expr spec.multiplier[22:0] -parent ABC_dnorm -type leading1
}

proc make {} {
    compile_spec
    compile_impl
    compose
}

proc run_main {} {
    set_host_file "host.qsub"
    set_user_assumes_lemmas_procedure "ual_main"
    set_hector_case_splitting_procedure "case_split_fp32"
    set_fml_var orch_distrib 16
    puts "=== Starting $_label proof ==="
    set t0 [clock seconds]
    solveNB p
    set t1 [clock seconds]
    puts "=== $_label proof complete ==="
    puts "elapsed: [expr {$t1-$t0}] seconds"
}
