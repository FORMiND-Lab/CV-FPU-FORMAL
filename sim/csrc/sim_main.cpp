//============================================================================
// sim_main.cpp — Verilator 仿真入口 (cycle-based, C++ 驱动时钟与复位)
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

    vluint64_t sim_time = 0;
    const vluint64_t MAX_TIME = 100000000; // 安全上限

    // ---- 初始复位 ----
    top->clk   = 0;
    top->rst_n = 0;
    top->eval();

    // 保持复位 5 个完整周期
    for (int i = 0; i < 5; i++) {
        top->clk = 1; top->eval(); sim_time += 5; tfp->dump(sim_time);
        top->clk = 0; top->eval(); sim_time += 5; tfp->dump(sim_time);
    }

    // 释放复位
    top->rst_n = 1;
    top->eval();
    tfp->dump(sim_time);

    // ---- 主循环 ----
    while (!Verilated::gotFinish() && sim_time < MAX_TIME) {
        top->clk = 1; top->eval(); sim_time += 5; tfp->dump(sim_time);
        top->clk = 0; top->eval(); sim_time += 5; tfp->dump(sim_time);
    }

    top->final();
    if (tfp) { tfp->close(); delete tfp; }
    delete top;
    return 0;
}
