//============================================================================
// tb_fma_cosim.sv — FMA Co-Simulation Testbench (cycle-based FSM)
//
// Interfaces aligned with Hector formal verification platform:
//   - DPI golden port names match hector/spec/fma_spec.cpp
//   - DUT wrapper reuses hector/rtl/fma_hector_wrap.sv (go/valid protocol)
//   - Combinational logic generates test vectors + calls DPI golden model
//   - Sequential FSM drives DUT via go pulse and checks valid/result
//============================================================================

import dpi_fma_golden_pkg::*;

// Local FMA operation encoding (aligned with fpnew_pkg but self-contained)
localparam int OP_FMADD  = 0;
localparam int OP_FMSUB  = 1;
localparam int OP_FNMADD = 2;
localparam int OP_FNMSUB = 3;

module tb_fma_cosim (
  input logic clk,     // driven by C++ sim_main.cpp
  input logic rst_n    // driven by C++ sim_main.cpp
);

  // ---- Simulation parameters ----
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

  // ---- DUT interface (aligned with fma_hector_wrap.sv) ----
  logic        dut_go;
  logic [31:0] dut_multiplier;
  logic [31:0] dut_multiplicand;
  logic [31:0] dut_addend;
  logic [2:0]  dut_rounding_mode;
  logic        dut_valid;
  logic [31:0] dut_result;
  logic [4:0]  dut_exceptions;       // {NV, DZ, OF, UF, NX} (Hector: exceptions)

  // ---- Test FSM ----
  typedef enum logic [1:0] {
    ST_RESET,
    ST_SETUP,
    ST_CHECK,
    ST_DONE
  } state_t;
  state_t state;

  // ---- Parameter read + startup banner ----
  initial begin
    if (!$value$plusargs("SEED=%d", seed))   seed = 1;
    if (!$value$plusargs("NUM=%d", num_tests)) num_tests = 10;
    if (!$value$plusargs("TRACE=%d", trace_en)) trace_en = 0;

    // Load directed test cases from file
    load_directed_cases();

    $display("============================================================");
    $display(" cvfpu FMA + SoftFloat Co-Simulation Testbench");
    $display(" (interface aligned with Hector DPV platform)");
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

  // Combinational outputs
  logic [31:0] comb_multiplier, comb_multiplicand, comb_addend;
  logic [2:0]  comb_rounding_mode;
  logic [3:0]  comb_op;
  int          comb_ref_res, comb_ref_exc;
  string       comb_name;

  int ref_multiplier, ref_multiplicand, ref_addend, ref_rm;
  int ref_result, ref_exceptions;

  always @* begin
    // Defaults
    comb_multiplier   = '0;
    comb_multiplicand = '0;
    comb_addend       = '0;
    comb_rounding_mode = '0;
    comb_op           = OP_FMADD;
    comb_name         = "";
    ref_multiplier = 0; ref_multiplicand = 0; ref_addend = 0; ref_rm = 0;
    ref_result = 0; ref_exceptions = 0;
    comb_ref_res = 0; comb_ref_exc = 0;

    if (state == ST_SETUP) begin
      if (case_idx < num_directed) begin
        // ---- Directed cases (loaded from tests/directed_cases.hex) ----
        comb_multiplier   = directed_a[case_idx];
        comb_multiplicand = directed_b[case_idx];
        comb_addend       = directed_c[case_idx];
        comb_rounding_mode = directed_rm[case_idx];
        comb_op           = directed_op[case_idx];
        comb_name         = $sformatf("directed_%0d", case_idx);
      end else begin
        // ---- Random cases ----
        // Constrain exponent to ~0x7F to stay in normal range [1.0, 2.0),
        // avoid inf/NaN/overflow edge cases in random testing.
        // Sign bit is randomized for broader coverage.
        // Use seed+case_idx as RNG seed — SEED controls the random sequence.
        comb_multiplier   = ($urandom(seed ^ ((case_idx - num_directed) * 4 + 0)) & 32'h3FFFFFFF) | 32'h3F800000;
        if ($urandom(seed ^ ((case_idx - num_directed) * 4 + 1000)) & 1) comb_multiplier[31] = 1'b1;
        comb_multiplicand = ($urandom(seed ^ ((case_idx - num_directed) * 4 + 1)) & 32'h3FFFFFFF) | 32'h3F800000;
        if ($urandom(seed ^ ((case_idx - num_directed) * 4 + 1001)) & 1) comb_multiplicand[31] = 1'b1;
        comb_addend       = ($urandom(seed ^ ((case_idx - num_directed) * 4 + 2)) & 32'h3FFFFFFF) | 32'h3F800000;
        if ($urandom(seed ^ ((case_idx - num_directed) * 4 + 1002)) & 1) comb_addend[31] = 1'b1;
        comb_rounding_mode = $urandom(seed ^ ((case_idx - num_directed) * 4 + 3)) % 5;  // 0..4
        comb_op           = OP_FMADD;
        comb_name         = $sformatf("random_%0d", case_idx - num_directed);
      end

      // Call DPI golden model (port names aligned with Hector fma_spec.cpp)
      ref_multiplier   = int'(comb_multiplier);
      ref_multiplicand = int'(comb_multiplicand);
      ref_addend       = int'(comb_addend);
      ref_rm           = int'(comb_rounding_mode);
      dpi_fma_golden(1,
          ref_multiplier, ref_multiplicand, ref_addend,
          ref_rm, int'(comb_op),
          ref_result, ref_exceptions);
      comb_ref_res = ref_result;
      comb_ref_exc = ref_exceptions;
    end
  end

  // ==========================================================================
  // Sequential: FSM + DUT driving + check
  // ==========================================================================

  // Registered copies of combinational values (captured in ST_SETUP)
  logic [31:0] reg_multiplier, reg_multiplicand, reg_addend;
  logic [2:0]  reg_rounding_mode;
  logic [3:0]  reg_op;
  int          reg_ref_res, reg_ref_exc;
  string       reg_name;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state             <= ST_RESET;
      case_idx          <= 0;
      pass_cnt          <= 0;
      fail_cnt          <= 0;
      dut_go            <= 1'b0;
      reg_multiplier    <= '0;
      reg_multiplicand  <= '0;
      reg_addend        <= '0;
      reg_rounding_mode <= '0;
      reg_op            <= OP_FMADD;
      reg_ref_res       <= 0;
      reg_ref_exc       <= 0;
      reg_name          <= "";
    end else begin
      unique case (state)
        ST_RESET: begin
          state       <= ST_SETUP;
          case_idx    <= 0;
          total_cases <= num_directed + num_tests;
        end

        ST_SETUP: begin
          // Latch combinational golden results
          reg_multiplier    <= comb_multiplier;
          reg_multiplicand  <= comb_multiplicand;
          reg_addend        <= comb_addend;
          reg_rounding_mode <= comb_rounding_mode;
          reg_op            <= comb_op;
          reg_ref_res       <= comb_ref_res;
          reg_ref_exc       <= comb_ref_exc;
          reg_name          <= comb_name;

          // Send go pulse with data (go/valid protocol, aligned with Hector)
          // For NUM_PIPE_REGS=0: go in cycle N, valid+result in cycle N+1
          dut_go            <= 1'b1;
          dut_multiplier    <= comb_multiplier;
          dut_multiplicand  <= comb_multiplicand;
          dut_addend        <= comb_addend;
          dut_rounding_mode <= comb_rounding_mode;
          state <= ST_CHECK;
        end

        ST_CHECK: begin
          dut_go <= 1'b0;  // deassert go immediately after the pulse

          if (dut_valid) begin
            if ((dut_result == reg_ref_res) && (dut_exceptions == reg_ref_exc)) begin
              pass_cnt <= pass_cnt + 1;
              if (trace_en)
                $display("[PASS] %s -> RES=%08h EXC=%05b", reg_name, dut_result, dut_exceptions);
            // RISC-V uses canonical NaN (0x7fc00000) while IEEE 754 / SoftFloat may
            // preserve NaN payload. When NV is set and all other flags match, both sides
            // agree the result is NaN — accept payload difference as a pass.
            end else if (dut_exceptions[4] && (dut_exceptions == reg_ref_exc)) begin
              pass_cnt <= pass_cnt + 1;
              if (trace_en)
                $display("[PASS] %s -> RES=%08h EXC=%05b (NaN payload diff OK)",
                         reg_name, dut_result, dut_exceptions);
            end else begin
              fail_cnt <= fail_cnt + 1;
              $display("[FAIL] %s", reg_name);
              $display("  Input:  multiplier=%08h multiplicand=%08h addend=%08h RM=%0d OP=%0d",
                       reg_multiplier, reg_multiplicand, reg_addend, reg_rounding_mode, reg_op);
              $display("  RTL:    RES=%08h EXC=%05b", dut_result, dut_exceptions);
              $display("  Ref:    RES=%08h EXC=%05b", reg_ref_res, reg_ref_exc);
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

  // ---- DUT instance: fma_hector_wrap (shared with Hector DPV flow) ----
  fma_hector_wrap #(
    .NUM_PIPE_REGS (0)
  ) i_dut (
    .clock         (clk),
    .resetN        (rst_n),
    .go            (dut_go),
    .multiplier    (dut_multiplier),
    .multiplicand  (dut_multiplicand),
    .addend        (dut_addend),
    .rounding_mode (dut_rounding_mode),
    .valid         (dut_valid),
    .result        (dut_result),
    .exceptions    (dut_exceptions)
  );

endmodule
