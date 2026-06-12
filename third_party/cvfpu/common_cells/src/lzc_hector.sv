// lzc_hector.sv - Hector-friendly version
// Use single always_comb with temporary arrays to avoid multi-driver
module lzc #(
  parameter int unsigned WIDTH = 2,
  parameter bit          MODE  = 1'b0,
  parameter int unsigned CNT_WIDTH = cf_math_pkg::idx_width(WIDTH)
) (
  input  logic [WIDTH-1:0]     in_i,
  output logic [CNT_WIDTH-1:0] cnt_o,
  output logic                 empty_o
);

  if (WIDTH == 1) begin : gen_degenerate_lzc
    assign cnt_o[0] = !in_i[0];
    assign empty_o  = !in_i[0];
  end else begin : gen_lzc
    localparam int unsigned NumLevels = $clog2(WIDTH);

    logic [WIDTH-1:0] in_tmp;
    logic [2**NumLevels-1:0]                sel_nodes;
    logic [2**NumLevels-1:0][NumLevels-1:0] index_nodes;

    always_comb begin : flip_vector
      for (int unsigned i = 0; i < WIDTH; i++)
        in_tmp[i] = MODE ? in_i[WIDTH-1-i] : in_i[i];
    end

    always_comb begin : gen_tree
      automatic logic [WIDTH-1:0][NumLevels-1:0] idx_lut;
      automatic logic [2**NumLevels-1:0]                sel_tmp;
      automatic logic [2**NumLevels-1:0][NumLevels-1:0] idx_tmp;

      // build index_lut
      for (int unsigned j = 0; j < WIDTH; j++)
        idx_lut[j] = (NumLevels)'(unsigned'(j));

      // init
      for (int unsigned n = 0; n < 2**NumLevels; n++) begin
        sel_tmp[n] = 1'b0;
        idx_tmp[n] = '0;
      end

      // leaf level
      for (int unsigned k = 0; k < 2**(NumLevels-1); k++) begin
        if (k*2 < WIDTH-1) begin
          sel_tmp[2**(NumLevels-1)-1+k] = in_tmp[k*2] | in_tmp[k*2+1];
          idx_tmp[2**(NumLevels-1)-1+k] = in_tmp[k*2] ? idx_lut[k*2] : idx_lut[k*2+1];
        end else if (k*2 == WIDTH-1) begin
          sel_tmp[2**(NumLevels-1)-1+k] = in_tmp[k*2];
          idx_tmp[2**(NumLevels-1)-1+k] = idx_lut[k*2];
        end
      end

      // upper levels
      for (int level = NumLevels-2; level >= 0; level--) begin
        for (int unsigned l = 0; l < 2**level; l++) begin
          sel_tmp[2**level-1+l] =
            sel_tmp[2**(level+1)-1+l*2] | sel_tmp[2**(level+1)-1+l*2+1];
          idx_tmp[2**level-1+l] =
            sel_tmp[2**(level+1)-1+l*2]
            ? idx_tmp[2**(level+1)-1+l*2]
            : idx_tmp[2**(level+1)-1+l*2+1];
        end
      end

      sel_nodes   = sel_tmp;
      index_nodes = idx_tmp;
    end

    assign cnt_o   = NumLevels > 0 ? index_nodes[0] : {($clog2(WIDTH)){1'b0}};
    assign empty_o = NumLevels > 0 ? ~sel_nodes[0]  : ~(|in_i);
  end : gen_lzc

endmodule : lzc
