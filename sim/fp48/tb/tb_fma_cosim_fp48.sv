//============================================================================
// tb_fma_cosim_fp48.sv — FP48 FMA Co-Simulation Testbench
//
// Drives fma_wrap_fp48 DUT with directed + random test vectors.
// DPI golden model (stub) is called but comparison is currently bypassed
// (SPEC_EN=0). Set SPEC_EN=1 once real FP48 golden model is ready.
//
// Interface aligned with Hector DPV convention:
//   - go/valid handshake (single pulse)
//   - 64-bit NaN-boxed FP48 container
//   - op_i / op_mod_i use fpnew_pkg encoding
//============================================================================

import dpi_fma_golden_fp48_pkg::*;

module tb_fma_cosim_fp48 (
  input logic clk,     // driven by C++ sim_main
  input logic rst_n    // driven by C++ sim_main
);

  // ---- Simulation parameters ----
  int seed, num_tests, trace_en;
  int pass_cnt, fail_cnt, skip_cnt;
  int case_idx, total_cases;

  // ---- Spec comparison enable (set to 1 when golden model is ready) ----
  localparam int SPEC_EN = 0;  // STUB mode: skip golden comparison

  // ---- Directed test case storage ----
  localparam int MAX_DIRECTED = 256;
  int num_directed;
  logic [63:0] directed_a      [MAX_DIRECTED];
  logic [63:0] directed_b      [MAX_DIRECTED];
  logic [63:0] directed_c      [MAX_DIRECTED];
  logic [2:0]  directed_rm     [MAX_DIRECTED];
  logic [3:0]  directed_op_i   [MAX_DIRECTED];
  logic        directed_op_mod [MAX_DIRECTED];

  // ---- DUT interface (aligned with fma_wrap_fp48.sv) ----
  logic        dut_go;
  logic [63:0] dut_multiplier;
  logic [63:0] dut_multiplicand;
  logic [63:0] dut_addend;
  logic [2:0]  dut_rounding_mode;
  logic [3:0]  dut_op_i;          // fpnew_pkg::operation_e
  logic        dut_op_mod;        // variant select
  logic        dut_valid;
  logic [63:0] dut_result;
  logic [4:0]  dut_exceptions;    // {NV, DZ, OF, UF, NX}

  // ---- Test FSM ----
  typedef enum logic [1:0] {
    ST_RESET,
    ST_SETUP,
    ST_CHECK,
    ST_DONE
  } state_t;
  state_t state;

  // ---- Helper functions ----
  function automatic string exc_bits(logic [4:0] e);
    return $sformatf("NV=%0d DZ=%0d OF=%0d UF=%0d NX=%0d",
                     e[4], e[3], e[2], e[1], e[0]);
  endfunction

  function automatic string rm_name(logic [2:0] rm);
    case (rm)
      0: return "RNE"; 1: return "RTZ"; 2: return "RDN";
      3: return "RUP"; 4: return "RMM"; default: return "???";
    endcase
  endfunction

  function automatic string op_name(logic [3:0] op, logic mod);
    case (op)
      OP_FP48_FMADD:  return mod ? "FMSUB  (a*b-c)"        : "FMADD  (a*b+c)";
      OP_FP48_FNMSUB: return mod ? "FNMADD (-(a*b)-c)"     : "FNMSUB (-(a*b)+c)";
      OP_FP48_ADD:    return mod ? "SUB    (b-c)"           : "ADD    (b+c)";
      OP_FP48_MUL:    return "MUL    (a*b)";
      OP_FP48_ADDS:   return mod ? "ADDS/SUB"               : "ADDS/ADD";
      default:        return "???";
    endcase
  endfunction

  // ---- Parameter read + startup banner ----
  initial begin
    if (!$value$plusargs("SEED=%d", seed))   seed = 1;
    if (!$value$plusargs("NUM=%d", num_tests)) num_tests = 10;
    if (!$value$plusargs("TRACE=%d", trace_en)) trace_en = 0;

    load_directed_cases();

    $display("============================================================");
    $display(" cvfpu FP48 FMA + DPI Co-Simulation Testbench");
    $display(" (interface aligned with Hector DPV platform)");
    $display(" SEED=%0d, NUM=%0d, SPEC_EN=%0d (stub)", seed, num_tests, SPEC_EN);
    $display("============================================================");
  end

  // ---- Load directed test cases ----
  function automatic void load_directed_cases();
    int fd;
    int tmp_rm, tmp_op_i, tmp_op_mod;
    string line;

    num_directed = 0;
    fd = $fopen("tests/directed_cases_fp48.hex", "r");
    if (fd) begin
      while (num_directed < MAX_DIRECTED && !$feof(fd)) begin
        line = "";
        if ($fgets(line, fd) == 0) continue;
        if (line.len() == 0)   continue;
        if (line[0] == "#")    continue;
        if (line[0] == "\n")   continue;
        if (line[0] == " ")    continue;
        if (line[0] == "/")    continue;
        // Parse: A B C RM OP_I OP_MOD (64-bit hex operands)
        if ($sscanf(line, "%h %h %h %d %d %d",
            directed_a[num_directed], directed_b[num_directed], directed_c[num_directed],
            tmp_rm, tmp_op_i, tmp_op_mod) == 6) begin
          directed_rm[num_directed]     = tmp_rm[2:0];
          directed_op_i[num_directed]   = tmp_op_i[3:0];
          directed_op_mod[num_directed] = tmp_op_mod[0];
          num_directed++;
        end
      end
      $fclose(fd);
      $display("Loaded %0d directed test cases from tests/directed_cases_fp48.hex", num_directed);
    end else begin
      $display("No directed test file found (tests/directed_cases_fp48.hex) — random only");
    end
  endfunction

  // ==========================================================================
  // Combinational: Generate test vectors and call DPI golden model
  // ==========================================================================

  logic [63:0] comb_multiplier, comb_multiplicand, comb_addend;
  logic [2:0]  comb_rounding_mode;
  logic [3:0]  comb_op_i;
  logic        comb_op_mod;
  longint      comb_ref_res;
  int          comb_ref_exc;
  string       comb_name;

  always @* begin
    comb_multiplier    = '0;
    comb_multiplicand  = '0;
    comb_addend        = '0;
    comb_rounding_mode = '0;
    comb_op_i          = OP_FP48_FMADD;
    comb_op_mod        = 1'b0;
    comb_name          = "";
    comb_ref_res       = 0;
    comb_ref_exc       = 0;

    if (state == ST_SETUP) begin
      if (case_idx < num_directed) begin
        // ---- Directed cases ----
        comb_multiplier    = directed_a[case_idx];
        comb_multiplicand  = directed_b[case_idx];
        comb_addend        = directed_c[case_idx];
        comb_rounding_mode = directed_rm[case_idx];
        comb_op_i          = directed_op_i[case_idx];
        comb_op_mod        = directed_op_mod[case_idx];
        comb_name          = $sformatf("directed_%0d", case_idx);
      end else begin
        // ---- Random cases ----
        // Generate FP48 values in 64-bit NaN-boxed containers.
        // Strategy: generate low 48 bits with valid FP48 patterns,
        // then NaN-box with 16'hffff.
        automatic int rng_idx = case_idx - num_directed;

        // Operand A: normal FP48
        comb_multiplier[47:0] = ($urandom(seed ^ (rng_idx * 4 + 0)) & 48'h7FFFFFFFFFFF) | 48'h3FF000000000;
        if ($urandom(seed ^ (rng_idx * 4 + 1000)) & 1) comb_multiplier[47] = 1'b1;
        // Operand B: normal FP48
        comb_multiplicand[47:0] = ($urandom(seed ^ (rng_idx * 4 + 1)) & 48'h7FFFFFFFFFFF) | 48'h3FF000000000;
        if ($urandom(seed ^ (rng_idx * 4 + 1001)) & 1) comb_multiplicand[47] = 1'b1;
        // Operand C: normal FP48
        comb_addend[47:0] = ($urandom(seed ^ (rng_idx * 4 + 2)) & 48'h7FFFFFFFFFFF) | 48'h3FF000000000;
        if ($urandom(seed ^ (rng_idx * 4 + 1002)) & 1) comb_addend[47] = 1'b1;

        // NaN-box all operands
        comb_multiplier[63:48]   = 16'hffff;
        comb_multiplicand[63:48] = 16'hffff;
        comb_addend[63:48]       = 16'hffff;

        comb_rounding_mode = $urandom(seed ^ (rng_idx * 4 + 3)) % 5;
        comb_op_i          = OP_FP48_FMADD;
        comb_op_mod        = 1'b0;
        comb_name          = $sformatf("random_%0d", rng_idx);
      end

      // Call DPI golden model (stub for now)
      dpi_fma_golden_fp48(1,
          comb_multiplier, comb_multiplicand, comb_addend,
          int'(comb_rounding_mode),
          int'(comb_op_i), int'(comb_op_mod),
          comb_ref_res, comb_ref_exc);
    end
  end

  // ==========================================================================
  // Sequential: FSM + DUT driving + check
  // ==========================================================================

  logic [63:0] reg_multiplier, reg_multiplicand, reg_addend;
  logic [2:0]  reg_rounding_mode;
  logic [3:0]  reg_op_i;
  logic        reg_op_mod;
  longint      reg_ref_res;
  int          reg_ref_exc;
  string       reg_name;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state             <= ST_RESET;
      case_idx          <= 0;
      pass_cnt          <= 0;
      fail_cnt          <= 0;
      skip_cnt          <= 0;
      dut_go            <= 1'b0;
      reg_multiplier    <= '0;
      reg_multiplicand  <= '0;
      reg_addend        <= '0;
      reg_rounding_mode <= '0;
      reg_op_i          <= OP_FP48_FMADD;
      reg_op_mod        <= 1'b0;
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
          reg_op_i          <= comb_op_i;
          reg_op_mod        <= comb_op_mod;
          reg_ref_res       <= comb_ref_res;
          reg_ref_exc       <= comb_ref_exc;
          reg_name          <= comb_name;

          // Send go pulse (go/valid protocol)
          dut_go            <= 1'b1;
          dut_multiplier    <= comb_multiplier;
          dut_multiplicand  <= comb_multiplicand;
          dut_addend        <= comb_addend;
          dut_rounding_mode <= comb_rounding_mode;
          dut_op_i          <= comb_op_i;
          dut_op_mod        <= comb_op_mod;
          state <= ST_CHECK;
        end

        ST_CHECK: begin
          dut_go <= 1'b0;

          if (dut_valid) begin
            if (SPEC_EN) begin
              // ---- Spec comparison mode (golden model must be real) ----
              if ((dut_result == reg_ref_res) && (dut_exceptions == reg_ref_exc[4:0])) begin
                pass_cnt <= pass_cnt + 1;
                if (trace_en)
                  $display("[PASS] %s -> RES=%016h EXC=%05b", reg_name, dut_result, dut_exceptions);
              end else begin
                fail_cnt <= fail_cnt + 1;
                $display("[FAIL] %s", reg_name);
                $display("  Input:  A=%016h B=%016h C=%016h RM=%0d OP=%0d/%0d",
                         reg_multiplier, reg_multiplicand, reg_addend,
                         reg_rounding_mode, reg_op_i, reg_op_mod);
                $display("  RTL:    RES=%016h EXC=%05b  %s", dut_result, dut_exceptions, exc_bits(dut_exceptions));
                $display("  Ref:    RES=%016h EXC=%05b  %s", reg_ref_res, reg_ref_exc[4:0], exc_bits(reg_ref_exc[4:0]));
              end
            end else begin
              // ---- STUB mode: print DUT result, no comparison ----
              skip_cnt <= skip_cnt + 1;
              if (trace_en) begin
                $display("[LOG]  %s", reg_name);
                $display("  Input:  A=%016h B=%016h C=%016h RM=%0d OP=%0d/%0d (%s)",
                         reg_multiplier, reg_multiplicand, reg_addend,
                         reg_rounding_mode, reg_op_i, reg_op_mod,
                         op_name(reg_op_i, reg_op_mod));
                $display("  RTL:    RES=%016h EXC=%05b  %s",
                         dut_result, dut_exceptions, exc_bits(dut_exceptions));
              end
              pass_cnt <= pass_cnt + 1;  // all "pass" in stub mode
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
          if (SPEC_EN) begin
            $display(" PASS: %0d, FAIL: %0d, TOTAL: %0d", pass_cnt, fail_cnt, pass_cnt+fail_cnt);
          end else begin
            $display(" STUB MODE: %0d vectors driven, %0d results observed", skip_cnt, pass_cnt);
            $display(" (Set SPEC_EN=1 in tb_fma_cosim_fp48.sv when golden model is ready)");
          end
          $display("============================================================");
          if (SPEC_EN && fail_cnt > 0) begin
            $display("TEST FAILED");
            $fatal(1, "TEST FAILED");
          end else begin
            $display("SIMULATION COMPLETE");
            $finish;
          end
        end
      endcase
    end
  end

  // ---- DUT instance: fma_wrap_fp48 ----
  fma_wrap_fp48 #(
    .NUM_PIPE_REGS (0)
  ) i_dut (
    .clock         (clk),
    .resetN        (rst_n),
    .go            (dut_go),
    .multiplier    (dut_multiplier),
    .multiplicand  (dut_multiplicand),
    .addend        (dut_addend),
    .rounding_mode (dut_rounding_mode),
    .op_i          (dut_op_i),
    .op_mod_i      (dut_op_mod),
    .valid         (dut_valid),
    .result        (dut_result),
    .exceptions    (dut_exceptions)
  );

endmodule
