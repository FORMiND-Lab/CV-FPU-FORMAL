//============================================================================
// sim_main_cex.cpp — Verilator 仿真入口 for CEX Replay
//============================================================================

#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vtb_fma_cex.h"

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    Vtb_fma_cex* top = new Vtb_fma_cex;

    // Enable waveform tracing
    Verilated::traceEverOn(true);
    VerilatedVcdC* tfp = new VerilatedVcdC;
    top->trace(tfp, 99);
    tfp->open("logs/fma_cex.vcd");

    vluint64_t sim_time = 0;
    const vluint64_t MAX_TIME = 1000; // CEX replay only needs a few cycles

    // ---- Reset ----
    top->clk   = 0;
    top->rst_n = 0;
    top->eval();

    for (int i = 0; i < 5; i++) {
        top->clk = 1; top->eval(); sim_time += 5; tfp->dump(sim_time);
        top->clk = 0; top->eval(); sim_time += 5; tfp->dump(sim_time);
    }

    top->rst_n = 1;
    top->eval();
    tfp->dump(sim_time);

    // ---- Main loop ----
    while (!Verilated::gotFinish() && sim_time < MAX_TIME) {
        top->clk = 1; top->eval(); sim_time += 5; tfp->dump(sim_time);
        top->clk = 0; top->eval(); sim_time += 5; tfp->dump(sim_time);
    }

    top->final();
    if (tfp) { tfp->close(); delete tfp; }
    delete top;
    return 0;
}
