//============================================================================
// tb_fma_cosim.sv — FMA Co-Simulation Testbench (简化初始版)
//============================================================================

`include "common_cells/registers.svh"

import dpi_softfloat_pkg::*;
import fpnew_pkg::*;

module tb_fma_cosim;

  // ---- 仿真参数 ----
  localparam int unsigned NUM_PIPE_REGS = 0; // 第一版无流水线

  int       seed;
  int       num_tests;
  int       trace_en;
  int       pass_cnt, fail_cnt;
  string    test_name;

  // ---- 时钟与复位 ----
  logic clk;
  logic rst_n;

  // ---- DUT 接口 ----
  logic        dut_valid;
  logic        dut_ready;
  logic [31:0] dut_a, dut_b, dut_c;
  logic [2:0]  dut_rm;
  logic [3:0]  dut_op;
  logic        dut_out_valid;
  logic        dut_out_ready;
  logic [31:0] dut_result;
  logic [4:0]  dut_fflags;

  // ---- DPI 参考结果 ----
  int          ref_enable;
  int          ref_a, ref_b, ref_c, ref_rm;
  int          ref_result, ref_fflags;

  // ---- 时钟生成 (10ns period) ----
  initial clk = 0;
  always #5 clk = ~clk;

  // ---- 测试控制 ----
  initial begin
    // 从命令行读参数
    if (!$value$plusargs("SEED=%d", seed))   seed = 1;
    if (!$value$plusargs("NUM=%d", num_tests)) num_tests = 1000;
    if (!$value$plusargs("TRACE=%d", trace_en)) trace_en = 0;

    $display("============================================================");
    $display(" cvfpu FMA + SoftFloat Co-Simulation Testbench");
    $display(" SEED=%0d, NUM=%0d", seed, num_tests);
    $display("============================================================");

    pass_cnt = 0;
    fail_cnt = 0;

    // Reset
    rst_n = 0;
    dut_valid = 0;
    dut_out_ready = 1;  // 第一版：始终 ready（无反压）
    repeat(5) @(posedge clk);
    rst_n = 1;
    repeat(2) @(posedge clk);

    // ---- Phase 1: Sanity Cases ----
    $display("[PHASE 1] Running sanity tests...");
    run_sanity_tests();

    // ---- Phase 2: Random Tests ----
    $display("[PHASE 2] Running random tests (NUM=%0d)...", num_tests);
    run_random_tests(num_tests, seed);

    // ---- Summary ----
    $display("============================================================");
    $display(" PASS: %0d, FAIL: %0d, TOTAL: %0d", pass_cnt, fail_cnt, pass_cnt + fail_cnt);
    $display("============================================================");
    if (fail_cnt > 0) $fatal(1, "TEST FAILED");
    else              $display("ALL TESTS PASSED");
  end

  // ---- DUT 实例 ----
  fma_dut_wrapper #(
    .NumPipeRegs (NUM_PIPE_REGS)
  ) i_dut (
    .clk_i       (clk),
    .rst_ni      (rst_n),
    .in_valid_i  (dut_valid),
    .in_ready_o  (dut_ready),
    .a_i         (dut_a),
    .b_i         (dut_b),
    .c_i         (dut_c),
    .rnd_mode_i  (dut_rm),
    .op_i        (dut_op),
    .out_valid_o (dut_out_valid),
    .out_ready_i (dut_out_ready),
    .result_o    (dut_result),
    .fflags_o    (dut_fflags)
  );

  // ---- 流水线延迟建模（无流水线时 0 cycle 延迟对齐） ----
  // DPI 在同一个 cycle 调用得到参考结果，与 RTL 输出对齐比较

  // ---- 自动比较 ----
  always @(posedge clk) begin
    if (dut_out_valid && rst_n) begin
      // 调用 DPI 获取参考结果（此时 DUT 输入已在上个 valid 时记录）
      // 注意：无流水线时，DPI 应在发送输入的同时调用
      // 这里简化处理：在 valid_o 时比较（需要 scoreboard 支持多笔）
      // 第一版单请求模型：每个 test case 等待 valid_o 后比较
    end
  end

  // ==========================================================================
  // 测试任务
  // ==========================================================================

  // ---- 单个 FMA 测试 ----
  task automatic test_single_fma(
    input string  name,
    input [31:0]  a,
    input [31:0]  b,
    input [31:0]  c,
    input [2:0]   rm,
    input [3:0]   op
  );
    int ref_res, ref_flg;
    int rtl_res, rtl_flg;

    test_name = name;

    // 调用 DPI 参考模型
    ref_enable = 1;
    ref_a = int'(a); ref_b = int'(b); ref_c = int'(c); ref_rm = int'(rm);

    case (op)
      FMADD:   dpi_fmadd_s  (ref_enable, ref_a, ref_b, ref_c, ref_rm, ref_res, ref_flg);
      FNMSUB:  dpi_fnmsub_s (ref_enable, ref_a, ref_b, ref_c, ref_rm, ref_res, ref_flg);
      default: begin
        $display("  [SKIP] op=%0d not implemented in DPI yet", op);
        return;
      end
    endcase

    // 发送到 DUT
    @(posedge clk);
    dut_valid <= 1;
    dut_a <= a; dut_b <= b; dut_c <= c;
    dut_rm <= rm; dut_op <= op;
    @(posedge clk);
    dut_valid <= 0;

    // 等待 DUT 输出
    wait(dut_out_valid);
    rtl_res = int'(dut_result);
    rtl_flg = int'(dut_fflags);

    // 比较
    if ((rtl_res == ref_res) && (rtl_flg == ref_flg)) begin
      pass_cnt++;
      if (trace_en)
        $display("  [PASS] %s | A=%08h B=%08h C=%08h RM=%0d -> RES=%08h FLG=%b",
                 name, a, b, c, rm, rtl_res, rtl_flg);
    end else begin
      fail_cnt++;
      $display("  [FAIL] %s", name);
      $display("    Input:   A=%08h B=%08h C=%08h RM=%0d OP=%0d", a, b, c, rm, op);
      $display("    RTL:     RES=%08h FLG=%05b", rtl_res, rtl_flg);
      $display("    Ref:     RES=%08h FLG=%05b", ref_res, ref_flg);
    end
  endtask

  // ---- Sanity Tests ----
  task automatic run_sanity_tests();
    // 1.0 * 2.0 + 3.0 = 5.0 (RNE)
    test_single_fma("1.0*2.0+3.0",
      32'h3F800000, 32'h40000000, 32'h40400000,
      3'b000, FMADD);

    // 0.0 * 5.0 + 3.0 = 3.0
    test_single_fma("0.0*5.0+3.0",
      32'h00000000, 32'h40A00000, 32'h40400000,
      3'b000, FMADD);

    // 1.5 * 2.0 + 0.5 = 3.5
    test_single_fma("1.5*2.0+0.5",
      32'h3FC00000, 32'h40000000, 32'h3F000000,
      3'b000, FMADD);

    // -1.0 * 2.0 + 3.0 = 1.0
    test_single_fma("-1.0*2.0+3.0",
      32'hBF800000, 32'h40000000, 32'h40400000,
      3'b000, FMADD);

    // 2.0 * 3.0 - 1.0 = 5.0 (FMSUB via op_mod)
    test_single_fma("2.0*3.0-1.0",
      32'h40000000, 32'h40400000, 32'h3F800000,
      3'b000, FMADD);  // Note: wrapper currently has op_mod_i=0, need update

    $display("  Sanity tests complete.");
  endtask

  // ---- Random Tests ----
  task automatic run_random_tests(int n, int s);
    int a32, b32, c32, rm3, op4;
    int status;
    integer i;

    // Simple LFSR-based random (placeholder)
    status = s;

    for (i = 0; i < n; i++) begin
      status = $urandom(status);
      a32 = status;
      status = $urandom(status);
      b32 = status;
      status = $urandom(status);
      c32 = status;
      rm3 = status & 3'h7;  // RNE/RTZ/RDN/RUP/RMM
      op4 = FMADD;          // Phase 1: FMADD only

      test_single_fma($sformatf("random_%0d", i),
                      a32[31:0], b32[31:0], c32[31:0],
                      rm3[2:0], op4);
    end
  endtask

endmodule
