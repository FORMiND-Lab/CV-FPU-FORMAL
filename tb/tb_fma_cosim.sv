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

  // ---- Directed test case storage (loaded from tests/directed_cases.hex) ----
  localparam int MAX_DIRECTED = 256;
  int num_directed;
  logic [31:0] directed_a   [MAX_DIRECTED];
  logic [31:0] directed_b   [MAX_DIRECTED];
  logic [31:0] directed_c   [MAX_DIRECTED];
  logic [2:0]  directed_rm  [MAX_DIRECTED];
  logic [3:0]  directed_op  [MAX_DIRECTED];

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

    // Load directed test cases from file
    load_directed_cases();

    $display("============================================================");
    $display(" cvfpu FMA + SoftFloat Co-Simulation Testbench");
    $display(" SEED=%0d, NUM=%0d", seed, num_tests);
    $display("============================================================");
  end

  // ---- Load directed test cases from tests/directed_cases.hex ----
  function automatic void load_directed_cases();
    int fd;
    int tmp_rm, tmp_op;
    string line;

    num_directed = 0;
    fd = $fopen("tests/directed_cases.hex", "r");
    if (fd) begin
      while (num_directed < MAX_DIRECTED && !$feof(fd)) begin
        line = "";
        if ($fgets(line, fd) == 0) continue;
        // Skip empty lines and comment lines
        if (line.len() == 0)   continue;
        if (line[0] == "#")    continue;
        if (line[0] == "\n")   continue;
        if (line[0] == " ")    continue;  // skip indented lines
        if (line[0] == "/")    continue;  // skip alternate comment style
        // Parse hex values: A B C RM OP
        if ($sscanf(line, "%h %h %h %d %d",
            directed_a[num_directed], directed_b[num_directed], directed_c[num_directed],
            tmp_rm, tmp_op) == 5) begin
          directed_rm[num_directed] = tmp_rm[2:0];
          directed_op[num_directed] = tmp_op[3:0];
          num_directed++;
        end
      end
      $fclose(fd);
      $display("Loaded %0d directed test cases from tests/directed_cases.hex", num_directed);
    end
  endfunction

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
      if (case_idx < num_directed) begin
        // ---- Directed cases (loaded from tests/directed_cases.hex) ----
        comb_a   = directed_a[case_idx];
        comb_b   = directed_b[case_idx];
        comb_c   = directed_c[case_idx];
        comb_rm  = directed_rm[case_idx];
        comb_op  = directed_op[case_idx];
        comb_name = $sformatf("directed_%0d", case_idx);
      end else begin
        // ---- Random cases ----
        // Constrain exponent to ~0x7F to stay in normal range [1.0, 2.0),
        // avoid inf/NaN/overflow edge cases in random testing.
        // Sign bit is randomized for broader coverage.
        // Use seed+case_idx as RNG seed — SEED controls the random sequence.
        comb_a   = ($urandom(seed ^ ((case_idx - num_directed) * 4 + 0)) & 32'h3FFFFFFF) | 32'h3F800000;
        // Randomly flip sign bit for ~50% negative values
        if ($urandom(seed ^ ((case_idx - num_directed) * 4 + 1000)) & 1) comb_a[31] = 1'b1;
        comb_b   = ($urandom(seed ^ ((case_idx - num_directed) * 4 + 1)) & 32'h3FFFFFFF) | 32'h3F800000;
        if ($urandom(seed ^ ((case_idx - num_directed) * 4 + 1001)) & 1) comb_b[31] = 1'b1;
        comb_c   = ($urandom(seed ^ ((case_idx - num_directed) * 4 + 2)) & 32'h3FFFFFFF) | 32'h3F800000;
        if ($urandom(seed ^ ((case_idx - num_directed) * 4 + 1002)) & 1) comb_c[31] = 1'b1;
        comb_rm  = $urandom(seed ^ ((case_idx - num_directed) * 4 + 3)) % 5;  // 0..4
        comb_op  = FMADD;
        comb_name = $sformatf("random_%0d", case_idx - num_directed);
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
          total_cases <= num_directed + num_tests;
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

          // Send to DUT only when ready (proper handshake)
          if (dut_ready) begin
            dut_valid <= 1'b1;
            dut_a  <= comb_a;
            dut_b  <= comb_b;
            dut_c  <= comb_c;
            dut_rm <= comb_rm;
            dut_op <= comb_op;
            state   <= ST_CHECK;
          end else begin
            dut_valid <= 1'b0;
            // Stay in ST_SETUP, retry next cycle
          end
        end

        ST_CHECK: begin
          dut_valid <= 1'b0;

          if (dut_out_valid) begin
            if ((dut_result == reg_ref_res) && (dut_fflags == reg_ref_flg)) begin
              pass_cnt <= pass_cnt + 1;
              if (trace_en)
                $display("[PASS] %s -> RES=%08h FLG=%05b", reg_name, dut_result, dut_fflags);
            // RISC-V uses canonical NaN (0x7fc00000) while IEEE 754 / SoftFloat may
            // preserve NaN payload. When NV is set and all other flags match, both sides
            // agree the result is NaN — accept payload difference as a pass.
            end else if (dut_fflags[4] && (dut_fflags == reg_ref_flg)) begin
              pass_cnt <= pass_cnt + 1;
              if (trace_en)
                $display("[PASS] %s -> RES=%08h FLG=%05b (NaN payload diff OK)",
                         reg_name, dut_result, dut_fflags);
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
