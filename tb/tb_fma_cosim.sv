//============================================================================
// tb_fma_cosim.sv — FMA Co-Simulation Testbench (cycle-based FSM)
// 组合逻辑生成测试向量 + DPI 调用，时序逻辑驱动 DUT 和状态机
//============================================================================

import dpi_softfloat_pkg::*;
import fpnew_pkg::*;

module tb_fma_cosim (
  input logic clk,     // 由 C++ sim_main 驱动
  input logic rst_n    // 由 C++ sim_main 驱动
);

  // ---- 仿真参数 ----
  int seed, num_tests, trace_en;
  int pass_cnt, fail_cnt;
  int case_idx, total_cases;

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

  // ---- 测试状态机 ----
  typedef enum logic [1:0] {
    ST_RESET,
    ST_SETUP,
    ST_CHECK,
    ST_DONE
  } state_t;
  state_t state;

  // ---- 参数读取 + 启动 Banner ----
  initial begin
    if (!$value$plusargs("SEED=%d", seed))   seed = 1;
    if (!$value$plusargs("NUM=%d", num_tests)) num_tests = 10;
    if (!$value$plusargs("TRACE=%d", trace_en)) trace_en = 0;
    $display("============================================================");
    $display(" cvfpu FMA + SoftFloat Co-Simulation Testbench");
    $display(" SEED=%0d, NUM=%0d", seed, num_tests);
    $display("============================================================");
  end

  // ==========================================================================
  // Combinational: Generate test vectors and call DPI golden model
  // ==========================================================================

  // Combinational outputs of this block
  logic [31:0] comb_a, comb_b, comb_c;
  logic [2:0]  comb_rm;
  logic [3:0]  comb_op;
  int          comb_ref_res, comb_ref_flg;
  string       comb_name;

  int ref_a, ref_b, ref_c, ref_rm;
  int ref_result, ref_fflags;

  always @* begin
    // Defaults
    comb_a   = '0;
    comb_b   = '0;
    comb_c   = '0;
    comb_rm  = '0;
    comb_op  = FMADD;
    comb_name = "";
    ref_a = 0; ref_b = 0; ref_c = 0; ref_rm = 0;
    ref_result = 0; ref_fflags = 0;
    comb_ref_res = 0; comb_ref_flg = 0;

    if (state == ST_SETUP) begin
      if (case_idx < 4) begin
        // ---- Sanity cases ----
        unique case (case_idx)
          0: begin comb_a=32'h3F800000; comb_b=32'h40000000; comb_c=32'h40400000;
                   comb_rm=3'b000; comb_op=FMADD; comb_name="1.0*2.0+3.0"; end
          1: begin comb_a=32'h00000000; comb_b=32'h40A00000; comb_c=32'h40400000;
                   comb_rm=3'b000; comb_op=FMADD; comb_name="0.0*5.0+3.0"; end
          2: begin comb_a=32'h3FC00000; comb_b=32'h40000000; comb_c=32'h3F000000;
                   comb_rm=3'b000; comb_op=FMADD; comb_name="1.5*2.0+0.5"; end
          3: begin comb_a=32'hBF800000; comb_b=32'h40000000; comb_c=32'h40400000;
                   comb_rm=3'b000; comb_op=FMADD; comb_name="-1.0*2.0+3.0"; end
        endcase
      end else begin
        // ---- Random cases ----
        // 用掩码限制 exponent 范围，避免 inf/NaN/overflow 极端值
        //   & 32'h3FFFFFFF: exponent <= 0111_1111 (max 127, actual max 2^0)
        //   | 32'h3F800000: exponent >= 0111_1111 (min 1.0) — 保证普通值范围
        //   最终 exponent 在 0x7F 左右，值域大致 [0.5, 2.0]
        comb_a   = ($urandom(case_idx * 4 + 0) & 32'h3FFFFFFF) | 32'h3F800000;
        comb_b   = ($urandom(case_idx * 4 + 1) & 32'h3FFFFFFF) | 32'h3F800000;
        comb_c   = ($urandom(case_idx * 4 + 2) & 32'h3FFFFFFF) | 32'h3F800000;
        comb_rm  = $urandom(case_idx * 4 + 3) % 5;  // 0..4
        comb_op  = FMADD;
        comb_name = $sformatf("random_%0d", case_idx - 4);
      end

      // Call DPI golden model
      ref_a = int'(comb_a);
      ref_b = int'(comb_b);
      ref_c = int'(comb_c);
      ref_rm = int'(comb_rm);
      dpi_fmadd_s(1, ref_a, ref_b, ref_c, ref_rm, ref_result, ref_fflags);
      comb_ref_res = ref_result;
      comb_ref_flg = ref_fflags;
    end
  end

  // ==========================================================================
  // Sequential: FSM + DUT driving + check
  // ==========================================================================

  // Registered copies of combinational values (captured in ST_SETUP)
  logic [31:0] reg_a, reg_b, reg_c;
  logic [2:0]  reg_rm;
  logic [3:0]  reg_op;
  int          reg_ref_res, reg_ref_flg;
  string       reg_name;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state      <= ST_RESET;
      case_idx   <= 0;
      pass_cnt   <= 0;
      fail_cnt   <= 0;
      dut_valid  <= 1'b0;
      dut_out_ready <= 1'b1;
      reg_a   <= '0;
      reg_b   <= '0;
      reg_c   <= '0;
      reg_rm  <= '0;
      reg_op  <= FMADD;
      reg_ref_res <= 0;
      reg_ref_flg <= 0;
      reg_name <= "";
    end else begin
      unique case (state)
        ST_RESET: begin
          state      <= ST_SETUP;
          case_idx   <= 0;
          total_cases <= 4 + num_tests;
        end

        ST_SETUP: begin
          // Capture combinational values into registers
          reg_a       <= comb_a;
          reg_b       <= comb_b;
          reg_c       <= comb_c;
          reg_rm      <= comb_rm;
          reg_op      <= comb_op;
          reg_ref_res <= comb_ref_res;
          reg_ref_flg <= comb_ref_flg;
          reg_name    <= comb_name;

          // Send to DUT
          dut_valid <= 1'b1;
          dut_a  <= comb_a;
          dut_b  <= comb_b;
          dut_c  <= comb_c;
          dut_rm <= comb_rm;
          dut_op <= comb_op;

          state <= ST_CHECK;
        end

        ST_CHECK: begin
          dut_valid <= 1'b0;

          if (dut_out_valid) begin
            if ((dut_result == reg_ref_res) && (dut_fflags == reg_ref_flg)) begin
              pass_cnt <= pass_cnt + 1;
              if (trace_en)
                $display("[PASS] %s -> RES=%08h FLG=%05b", reg_name, dut_result, dut_fflags);
            end else begin
              fail_cnt <= fail_cnt + 1;
              $display("[FAIL] %s", reg_name);
              $display("  Input:  A=%08h B=%08h C=%08h RM=%0d OP=%0d",
                       reg_a, reg_b, reg_c, reg_rm, reg_op);
              $display("  RTL:    RES=%08h FLG=%05b", dut_result, dut_fflags);
              $display("  Ref:    RES=%08h FLG=%05b", reg_ref_res, reg_ref_flg);
            end

            if (case_idx + 1 < total_cases) begin
              case_idx <= case_idx + 1;
              state <= ST_SETUP;
            end else begin
              state <= ST_DONE;
            end
          end
        end

        ST_DONE: begin
          $display("============================================================");
          $display(" PASS: %0d, FAIL: %0d, TOTAL: %0d", pass_cnt, fail_cnt, pass_cnt+fail_cnt);
          $display("============================================================");
          if (fail_cnt > 0) begin
            $display("TEST FAILED");
            $fatal(1, "TEST FAILED");
          end else begin
            $display("ALL TESTS PASSED");
            $finish;
          end
        end
      endcase
    end
  end

  // ---- DUT 实例 ----
  fma_dut_wrapper #(
    .NumPipeRegs (0)
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

endmodule
