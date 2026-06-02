//============================================================================
// sim_main.cpp — Verilator 仿真入口
// 时钟由 SV testbench 中的 `always #5 clk = ~clk` 驱动，
// C++ main 只负责循环 eval + trace dump。
//============================================================================

#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vtb_fma_cosim.h"

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    Vtb_fma_cosim* top = new Vtb_fma_cosim;

    // 开启波形
    Verilated::traceEverOn(true);
    VerilatedVcdC* tfp = new VerilatedVcdC;
    top->trace(tfp, 99);
    tfp->open("logs/fma_cosim.vcd");

    // 主循环：Verilator --timing 模式下每次 eval() 推进一个时间步
    while (!Verilated::gotFinish()) {
        top->eval();
        tfp->dump(top->contextp()->time());
    }

    top->final();
    tfp->close();
    delete tfp;
    delete top;
    return 0;
}
