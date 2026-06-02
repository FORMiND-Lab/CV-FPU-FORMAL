//============================================================================
// fma_dut_wrapper.sv — FP32 FMA DUT Wrapper
// 将 fpnew_fma 包装成固定 FP32 的简单接口，便于 testbench 对接
//============================================================================

`include "common_cells/registers.svh"

module fma_dut_wrapper #(
  parameter int unsigned NumPipeRegs = 0
) (
  input  logic        clk_i,
  input  logic        rst_ni,

  // ---- 输入数据 ----
  input  logic        in_valid_i,
  output logic        in_ready_o,
  input  logic [31:0] a_i,
  input  logic [31:0] b_i,
  input  logic [31:0] c_i,
  input  logic [2:0]  rnd_mode_i,
  input  logic [3:0]  op_i,       // operation_e encoding

  // ---- 输出数据 ----
  output logic        out_valid_o,
  input  logic        out_ready_i,
  output logic [31:0] result_o,
  output logic [4:0]  fflags_o
);

  // ---- 内部信号 ----
  logic [2:0][31:0]  operands;
  fpnew_pkg::roundmode_e   rm;
  fpnew_pkg::operation_e   op;

  fpnew_pkg::status_t status;

  // ---- 操作数打包 ----
  assign operands[0] = a_i;
  assign operands[1] = b_i;
  assign operands[2] = c_i;

  // ---- 类型转换 ----
  assign rm = fpnew_pkg::roundmode_e'(rnd_mode_i);
  assign op = fpnew_pkg::operation_e'(op_i);

  // ---- FMA 实例 ----
  fpnew_fma #(
    .FpFormat    (fpnew_pkg::FP32),
    .NumPipeRegs (NumPipeRegs),
    .PipeConfig  (fpnew_pkg::BEFORE),
    .TagType     (logic),
    .AuxType     (logic)
  ) i_fma (
    .clk_i              (clk_i),
    .rst_ni             (rst_ni),
    .operands_i         (operands),
    .is_boxed_i         (3'b111),          // all boxed (RISC-V)
    .rnd_mode_i         (rm),
    .op_i               (op),
    .op_mod_i           (1'b0),            // op_mod controlled externally via op_i
    .tag_i              (1'b0),
    .mask_i             (1'b1),            // no SIMD masking
    .aux_i              (1'b0),
    .in_valid_i         (in_valid_i),
    .in_ready_o         (in_ready_o),
    .flush_i            (1'b0),            // no flush
    .result_o           (result_o),
    .status_o           (status),
    .extension_bit_o    (),                // unused
    .tag_o              (),                // unused
    .mask_o             (),                // unused
    .aux_o              (),                // unused
    .out_valid_o        (out_valid_o),
    .out_ready_i        (out_ready_i),
    .busy_o             (),                // unused
    .reg_ena_i          ('0),              // no external reg enable
    .early_out_valid_o  ()                 // unused
  );

  // ---- Status flag 打包 ----
  assign fflags_o = {
    status.NV,
    status.DZ,
    status.OF,
    status.UF,
    status.NX
  };

endmodule
