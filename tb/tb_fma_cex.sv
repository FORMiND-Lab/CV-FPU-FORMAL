//============================================================================
// tb_fma_cex.sv — CEX Replay Testbench (file-driven, multi-case)
//
// Reads test cases from a file (format: A B C RM OP per line, hex values).
// For each case, runs both the DPI golden model and the RTL DUT, then prints
// a side-by-side comparison.
//
// Usage:
//   ./tb_fma_cex +CEX_FILE=tests/my_cex.hex
//
// File format (same as tests/directed_cases.hex):
//   # comment lines start with # or //
//   <A_hex> <B_hex> <C_hex> <RM_dec> <OP_dec>
//
//   OP: 0=FMADD, 1=FMSUB, 2=FNMADD, 3=FNMSUB
//============================================================================

import dpi_fma_golden_pkg::*;

localparam int OP_FMADD  = 0;
localparam int OP_FMSUB  = 1;
localparam int OP_FNMADD = 2;
localparam int OP_FNMSUB = 3;

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
  logic [3:0]  tc_op           [MAX_CASES];

  int pass_cnt, fail_cnt;

  // ---- DUT interface (go/valid protocol, aligned with fma_hector_wrap.sv) ----
  logic        dut_go;
  logic [31:0] dut_multiplier, dut_multiplicand, dut_addend;
  logic [2:0]  dut_rounding_mode;
  logic        dut_valid;
  logic [31:0] dut_result;
  logic [4:0]  dut_exceptions;

  // ---- Golden model results ----
  int ref_result, ref_exceptions;

  string cex_file;
  int case_idx;

  // ---- Helper: decode exceptions ----
  function automatic string exc_bits(logic [4:0] e);
    return $sformatf("NV=%0d DZ=%0d OF=%0d UF=%0d NX=%0d",
                     e[4], e[3], e[2], e[1], e[0]);
  endfunction

  function automatic string rm_name(logic [2:0] rm);
    case (rm)
      0: return "RNE";
      1: return "RTZ";
      2: return "RDN";
      3: return "RUP";
      4: return "RMM";
      default: return "???";
    endcase
  endfunction

  function automatic string op_name(logic [3:0] op);
    case (op)
      0: return "FMADD  (a*b+c)";
      1: return "FMSUB  (a*b-c)";
      2: return "FNMADD (-(a*b)+c)";
      3: return "FNMSUB (-(a*b)-c)";
      default: return "???";
    endcase
  endfunction

  // ---- Load test cases from file ----
  function automatic void load_cex_file();
    int fd;
    int tmp_rm, tmp_op;
    string line;

    if (!$value$plusargs("CEX_FILE=%s", cex_file)) begin
      $display("ERROR: +CEX_FILE=<path> not specified");
      $display("Usage: ./tb_fma_cex +CEX_FILE=tests/my_cex.hex");
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
      // Skip empty lines, comments
      if (line.len() == 0)   continue;
      if (line[0] == "#")    continue;
      if (line[0] == "/")    continue;
      if (line[0] == "\n")   continue;
      if (line[0] == " ")    continue;
      // Parse: A B C RM OP
      if ($sscanf(line, "%h %h %h %d %d",
          tc_multiplier[num_cases],
          tc_multiplicand[num_cases],
          tc_addend[num_cases],
          tmp_rm, tmp_op) == 5) begin
        tc_rm[num_cases] = tmp_rm[2:0];
        tc_op[num_cases] = tmp_op[3:0];
        num_cases++;
      end
    end
    $fclose(fd);
    $display("Loaded %0d test case(s) from '%s'", num_cases, cex_file);
  endfunction

  // ---- FSM ----
  typedef enum logic [2:0] {
    ST_IDLE,
    ST_RUN,
    ST_WAIT,
    ST_REPORT,
    ST_NEXT,
    ST_DONE
  } state_t;
  state_t state;

  // ---- Call golden model combinatorially ----
  always @* begin
    ref_result     = 0;
    ref_exceptions = 0;
    if (state == ST_RUN) begin
      dpi_fma_golden(1,
          int'(tc_multiplier[case_idx]),
          int'(tc_multiplicand[case_idx]),
          int'(tc_addend[case_idx]),
          int'(tc_rm[case_idx]),
          int'(tc_op[case_idx]),
          ref_result, ref_exceptions);
    end
  end

  // ---- Register RTL results for reporting ----
  logic [31:0] cap_rtl_result;
  logic [4:0]  cap_rtl_exceptions;
  int          cap_ref_result, cap_ref_exceptions;
  logic [31:0] cap_multiplier, cap_multiplicand, cap_addend;
  logic [2:0]  cap_rm;
  logic [3:0]  cap_op;

  // ---- Main FSM ----
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state       <= ST_IDLE;
      dut_go      <= 1'b0;
      pass_cnt    <= 0;
      fail_cnt    <= 0;
    end else begin
      unique case (state)
        ST_IDLE: begin
          load_cex_file();
          case_idx <= 0;
          state <= ST_RUN;
        end

        ST_RUN: begin
          // Send go pulse with current test case
          dut_go            <= 1'b1;
          dut_multiplier    <= tc_multiplier[case_idx];
          dut_multiplicand  <= tc_multiplicand[case_idx];
          dut_addend        <= tc_addend[case_idx];
          dut_rounding_mode <= tc_rm[case_idx];
          state <= ST_WAIT;
        end

        ST_WAIT: begin
          dut_go <= 1'b0;
          if (dut_valid) begin
            // Capture both golden and RTL results
            cap_rtl_result     <= dut_result;
            cap_rtl_exceptions <= dut_exceptions;
            cap_ref_result     <= ref_result;
            cap_ref_exceptions <= ref_exceptions;
            cap_multiplier     <= tc_multiplier[case_idx];
            cap_multiplicand   <= tc_multiplicand[case_idx];
            cap_addend         <= tc_addend[case_idx];
            cap_rm             <= tc_rm[case_idx];
            cap_op             <= tc_op[case_idx];
            state <= ST_REPORT;
          end
        end

        ST_REPORT: begin
          // Print side-by-side comparison
          $display("============================================================");
          $display(" Case %0d/%0d", case_idx + 1, num_cases);
          $display("============================================================");
          $display(" Inputs:");
          $display("   multiplier   (A)  = 32'h%08h", cap_multiplier);
          $display("   multiplicand (B)  = 32'h%08h", cap_multiplicand);
          $display("   addend       (C)  = 32'h%08h", cap_addend);
          $display("   rounding_mode     = %0d (%s)", cap_rm, rm_name(cap_rm));
          $display("   op                = %0d (%s)", cap_op, op_name(cap_op));
          $display("");
          $display(" Golden (SoftFloat via DPI):");
          $display("   result     = 32'h%08h", cap_ref_result);
          $display("   exceptions = 5'h%02h     -> %s", cap_ref_exceptions, exc_bits(5'(cap_ref_exceptions)));
          $display("");
          $display(" RTL (fpnew_fma via fma_hector_wrap):");
          $display("   result     = 32'h%08h", cap_rtl_result);
          $display("   exceptions = 5'h%02h     -> %s", cap_rtl_exceptions, exc_bits(cap_rtl_exceptions));
          $display("");

          // Compare
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
