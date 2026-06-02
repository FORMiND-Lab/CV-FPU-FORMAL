//============================================================================
// dpi_softfloat.sv — SoftFloat DPI-C 函数声明 (SystemVerilog 侧)
//============================================================================

package dpi_softfloat_pkg;

  // ---- DPI-C 导入函数 ----
  import "DPI-C" function void dpi_fmadd_s(
    input  int     enable,
    input  int     a,
    input  int     b,
    input  int     c,
    input  int     rm,
    output int     result,
    output int     fflags
  );

  import "DPI-C" function void dpi_fmsub_s(
    input  int     enable,
    input  int     a,
    input  int     b,
    input  int     c,
    input  int     rm,
    output int     result,
    output int     fflags
  );

  import "DPI-C" function void dpi_fnmadd_s(
    input  int     enable,
    input  int     a,
    input  int     b,
    input  int     c,
    input  int     rm,
    output int     result,
    output int     fflags
  );

  import "DPI-C" function void dpi_fnmsub_s(
    input  int     enable,
    input  int     a,
    input  int     b,
    input  int     c,
    input  int     rm,
    output int     result,
    output int     fflags
  );

endpackage
