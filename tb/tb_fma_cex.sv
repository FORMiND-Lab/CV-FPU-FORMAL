//============================================================================
// tb_fma_cex.sv — CEX Replay Testbench (file-driven, multi-case)
//
// Reads test cases from a file and prints side-by-side spec vs impl comparison.
//
// Usage:
//   ./tb_fma_cex +CEX_FILE=tests/my_cex.hex
//
// File format:
//   # comments start with # or //
//   <A_hex> <B_hex> <C_hex> <RM> <OP_I> <OP_MOD>
//
//   OP_I encoding (fpnew_pkg::operation_e):
//     FMADD=0, FNMSUB=1, ADD=2, MUL=3, ADDS=4
//   OP_MOD: 0/1 selects variant (FMSUB, FNMADD, SUB, ...)
//============================================================================

import dpi_fma_golden_pkg::*;

module tb_fma_cex (
  input logic clk,
  input logic rst_n
);

  // ---- Test case storage ----
  localparam int MAX_CASES = 1024;
  int num_cases;
  logic [31:0] tc_multiplier   [MAX_CASES];
  logic [31:0] tc_multiplicand [MAX_CASES];
  logic [31:0] tc_addend       [MAX_CASES];
  logic [2:0]  tc_rm           [MAX_CASES];
  logic [3:0]  tc_op_i         [MAX_CASES];
  logic        tc_op_mod       [MAX_CASES];

  int pass_cnt, fail_cnt;

  // ---- DUT interface (go/valid protocol) ----
  logic        dut_go;
  logic [31:0] dut_multiplier, dut_multiplicand, dut_addend;
  logic [2:0]  dut_rounding_mode;
  logic [3:0]  dut_op_i;
  logic        dut_op_mod;
  logic        dut_valid;
  logic [31:0] dut_result;
  logic [4:0]  dut_exceptions;

  // ---- Golden model results ----
  int ref_result, ref_exceptions;

  string cex_file;
  int case_idx;

  // ---- Helpers ----
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
      OP_FMADD:  return mod ? "FMSUB  (a*b-c)"        : "FMADD  (a*b+c)";
      OP_FNMSUB: return mod ? "FNMADD (-(a*b)-c)"     : "FNMSUB (-(a*b)+c)";
      OP_ADD:    return mod ? "SUB    (b-c)"           : "ADD    (b+c)";
      OP_MUL:    return "MUL    (a*b)";
      OP_ADDS:   return mod ? "ADDS/SUB"               : "ADDS/ADD";
      default:   return "???";
    endcase
  endfunction

  // ---- Load test cases from file ----
  function automatic void load_cex_file();
    int fd, tmp_rm, tmp_op_i, tmp_op_mod;
    string line;

    if (!$value$plusargs("CEX_FILE=%s", cex_file)) begin
      $display("ERROR: +CEX_FILE=<path> not specified");
      $fatal(1, "Missing +CEX_FILE argument");
    end

    num_cases = 0;
    fd = $fopen(cex_file, "r");
    if (!fd) begin
      $display("ERROR: Cannot open file '%s'", cex_file);
      $fatal(1, "File not found");
    end

    while (num_cases < MAX_CASES && !$feof(fd)) begin
      line = "";
      if ($fgets(line, fd) == 0) continue;
      if (line.len() == 0)   continue;
      if (line[0] == "#")    continue;
      if (line[0] == "/")    continue;
      if (line[0] == "\n")   continue;
      if (line[0] == " ")    continue;
      // Parse: A B C RM OP_I OP_MOD
      if ($sscanf(line, "%h %h %h %d %d %d",
          tc_multiplier[num_cases],
          tc_multiplicand[num_cases],
          tc_addend[num_cases],
          tmp_rm, tmp_op_i, tmp_op_mod) == 6) begin
        tc_rm[num_cases]     = tmp_rm[2:0];
        tc_op_i[num_cases]   = tmp_op_i[3:0];
        tc_op_mod[num_cases] = tmp_op_mod[0];
        num_cases++;
      end
    end
    $fclose(fd);
    $display("Loaded %0d test case(s) from '%s'", num_cases, cex_file);
  endfunction

  // ---- FSM ----
  typedef enum logic [2:0] {
    ST_IDLE, ST_RUN, ST_WAIT, ST_REPORT, ST_NEXT, ST_DONE
  } state_t;
  state_t state;

  // ---- Call golden model combinatorially ----
  always @* begin
    ref_result     = 0;
    ref_exceptions = 0;
    if (state == ST_RUN) begin
      dpi_fma_golden(1,
          int'(tc_multiplier[case_idx]), int'(tc_multiplicand[case_idx]),
          int'(tc_addend[case_idx]),
          int'(tc_rm[case_idx]),
          int'(tc_op_i[case_idx]), int'(tc_op_mod[case_idx]),
          ref_result, ref_exceptions);
    end
  end

  // ---- Capture registers ----
  logic [31:0] cap_rtl_result;
  logic [4:0]  cap_rtl_exceptions;
  int          cap_ref_result, cap_ref_exceptions;
  logic [31:0] cap_multiplier, cap_multiplicand, cap_addend;
  logic [2:0]  cap_rm;
  logic [3:0]  cap_op_i;
  logic        cap_op_mod;

  // ---- Main FSM ----
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state    <= ST_IDLE;
      dut_go   <= 1'b0;
      pass_cnt <= 0;
      fail_cnt <= 0;
    end else begin
      unique case (state)
        ST_IDLE: begin
          load_cex_file();
          case_idx <= 0;
          state <= ST_RUN;
        end

        ST_RUN: begin
          dut_go            <= 1'b1;
          dut_multiplier    <= tc_multiplier[case_idx];
          dut_multiplicand  <= tc_multiplicand[case_idx];
          dut_addend        <= tc_addend[case_idx];
          dut_rounding_mode <= tc_rm[case_idx];
          dut_op_i          <= tc_op_i[case_idx];
          dut_op_mod        <= tc_op_mod[case_idx];
          state <= ST_WAIT;
        end

        ST_WAIT: begin
          dut_go <= 1'b0;
          if (dut_valid) begin
            cap_rtl_result     <= dut_result;
            cap_rtl_exceptions <= dut_exceptions;
            cap_ref_result     <= ref_result;
            cap_ref_exceptions <= ref_exceptions;
            cap_multiplier     <= tc_multiplier[case_idx];
            cap_multiplicand   <= tc_multiplicand[case_idx];
            cap_addend         <= tc_addend[case_idx];
            cap_rm             <= tc_rm[case_idx];
            cap_op_i           <= tc_op_i[case_idx];
            cap_op_mod         <= tc_op_mod[case_idx];
            state <= ST_REPORT;
          end
        end

        ST_REPORT: begin
          $display("============================================================");
          $display(" Case %0d/%0d", case_idx + 1, num_cases);
          $display("============================================================");
          $display(" Inputs:");
          $display("   multiplier   (A)  = 32'h%08h", cap_multiplier);
          $display("   multiplicand (B)  = 32'h%08h", cap_multiplicand);
          $display("   addend       (C)  = 32'h%08h", cap_addend);
          $display("   rounding_mode     = %0d (%s)", cap_rm, rm_name(cap_rm));
          $display("   op_i / op_mod     = %0d / %0d  (%s)", cap_op_i, cap_op_mod,
                   op_name(cap_op_i, cap_op_mod));
          $display("");
          $display(" Golden (SoftFloat via DPI):");
          $display("   result     = 32'h%08h", cap_ref_result);
          $display("   exceptions = 5'h%02h     -> %s", cap_ref_exceptions, exc_bits(5'(cap_ref_exceptions)));
          $display("");
          $display(" RTL (fpnew_fma via fma_hector_wrap):");
          $display("   result     = 32'h%08h", cap_rtl_result);
          $display("   exceptions = 5'h%02h     -> %s", cap_rtl_exceptions, exc_bits(cap_rtl_exceptions));
          $display("");

          if ((cap_rtl_result == cap_ref_result[31:0]) &&
              (cap_rtl_exceptions == cap_ref_exceptions[4:0])) begin
            $display(" VERDICT: PASS");
            pass_cnt <= pass_cnt + 1;
          end else begin
            $display(" VERDICT: MISMATCH");
            if (cap_rtl_result != cap_ref_result[31:0])
              $display("   result diff     : spec=%08h  impl=%08h", cap_ref_result, cap_rtl_result);
            if (cap_rtl_exceptions != cap_ref_exceptions[4:0]) begin
              $display("   exceptions diff : spec=%02h   impl=%02h",
                       cap_ref_exceptions[4:0], cap_rtl_exceptions);
              $display("     NV: spec=%0d impl=%0d", cap_ref_exceptions[4], cap_rtl_exceptions[4]);
              $display("     DZ: spec=%0d impl=%0d", cap_ref_exceptions[3], cap_rtl_exceptions[3]);
              $display("     OF: spec=%0d impl=%0d", cap_ref_exceptions[2], cap_rtl_exceptions[2]);
              $display("     UF: spec=%0d impl=%0d", cap_ref_exceptions[1], cap_rtl_exceptions[1]);
              $display("     NX: spec=%0d impl=%0d", cap_ref_exceptions[0], cap_rtl_exceptions[0]);
            end
            fail_cnt <= fail_cnt + 1;
          end
          $display("============================================================");
          state <= ST_NEXT;
        end

        ST_NEXT: begin
          if (case_idx + 1 < num_cases) begin
            case_idx <= case_idx + 1;
            state <= ST_RUN;
          end else begin
            state <= ST_DONE;
          end
        end

        ST_DONE: begin
          $display("");
          $display("============================================================");
          $display(" CEX Replay Summary: %0d PASS, %0d FAIL, %0d TOTAL",
                   pass_cnt, fail_cnt, pass_cnt + fail_cnt);
          $display("============================================================");
          $finish;
        end
      endcase
    end
  end

  // ---- DUT instance ----
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
    .op_i          (dut_op_i),
    .op_mod_i      (dut_op_mod),
    .valid         (dut_valid),
    .result        (dut_result),
    .exceptions    (dut_exceptions)
  );

endmodule
