//============================================================================
// sim_main_fp48.cpp — Verilator simulation entry point for FP48 co-sim
//
// Cycle-based driver: generates clk, handles reset, dumps VCD waveform.
//============================================================================

#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vtb_fma_cosim_fp48.h"

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    Vtb_fma_cosim_fp48* top = new Vtb_fma_cosim_fp48;

    // Enable waveform tracing
    Verilated::traceEverOn(true);
    VerilatedVcdC* tfp = new VerilatedVcdC;
    top->trace(tfp, 99);
    tfp->open("logs/fma_cosim_fp48.vcd");

    vluint64_t sim_time = 0;
    const vluint64_t MAX_TIME = 100000000; // safety upper bound

    // ---- Initial reset ----
    top->clk   = 0;
    top->rst_n = 0;
    top->eval();

    // Hold reset for 5 complete cycles
    for (int i = 0; i < 5; i++) {
        top->clk = 1; top->eval(); sim_time += 5; tfp->dump(sim_time);
        top->clk = 0; top->eval(); sim_time += 5; tfp->dump(sim_time);
    }

    // Release reset
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
