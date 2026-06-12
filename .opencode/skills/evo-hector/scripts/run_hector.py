#!/usr/bin/env python3
"""
Run hector (vcf DPV) verification from analysis.json.

For each case:
  1. Creates a dedicated run directory under log_dir/hector_log/<case>/
  2. Generates host.qsub
  3. Removes stale session.lock if present
  4. Runs via docker exec: vcf -fmode DPV -batch -f <tcl> -y "make; run_main"
     (uses original TCL with original relative paths, cwd = run_dir)
  5. Parses listproofs output to determine PASS/FAIL
  6. Writes structured log and summary report.md

Two trace modes on failure:
  simple (default): simcex counter-example trace (inputs only)
  deep   (--deep_trace): VCS replay with full internal signal VCD dump

Note: TCL relative paths are resolved from the run directory. Since the
original TCL uses paths like ../../rtl/ and ../../../third_party/, the
run directory must be at the correct depth (e.g. formal/run/run_add16/).
The run directory is created under log_dir/hector_log/<case>/ by default,
but can be overridden via --run_base_dir to match the expected depth.
"""

import argparse
import json
import os
import re
import shutil
import signal
import subprocess
import textwrap
import traceback
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

STATUS_SUCCESS     = "VERIFICATION SUCCESSFUL"
STATUS_FAILED      = "VERIFICATION FAILED"
STATUS_TIMEOUT     = "EXECUTION TIMEOUT"
STATUS_OTHER_ERROR = "OTHER ERROR"

DOCKER_CONTAINER = "eda-hector"

HOST_TO_DOCKER = {
    "/home/zhangyang/workspace/eda": "/home/eda",
    "/home/zhangyang/workspace/c_rtl": "/home/c_rtl",
}


def to_docker_path(host_path: str) -> str:
    for host_prefix, docker_prefix in HOST_TO_DOCKER.items():
        if str(host_path).startswith(host_prefix):
            return str(host_path).replace(host_prefix, docker_prefix, 1)
    return str(host_path)


# ═══════════════════════════════════════════════════════════════════════════════
# Result parsing
# ═══════════════════════════════════════════════════════════════════════════════

def parse_hector_status(output: str, timed_out: bool) -> str:
    if timed_out:
        return STATUS_TIMEOUT
    has_failed = bool(re.search(r'(?:Proof\s+\S+:\s+FAILED|\bfailed\b)', output))
    has_success = bool(re.search(r'  success', output))
    all_100pct  = bool(re.search(
        r'All\s+\d+\s+proof\s+obligations?\s+proven', output, re.I
    ))
    no_tasks    = bool(re.search(r'No running tasks', output))
    if has_failed:
        return STATUS_FAILED
    if has_success and no_tasks:
        return STATUS_SUCCESS
    if all_100pct:
        return STATUS_SUCCESS
    return STATUS_OTHER_ERROR


# ═══════════════════════════════════════════════════════════════════════════════
# Counter-example input parser
# ═══════════════════════════════════════════════════════════════════════════════

def parse_counter_example(trace_txt: str) -> dict[str, str]:
    """Parse a simcex trace_<lemma>.txt into {port_name: value_h} dict.
    
    Format from simcex:
      impl_go_in             1'h1 0 1
      impl_addend_in         16'h0000 0 16
      impl_multiplier_in     16'h7c00 0 16
      impl_rounding_mode_in  3'h4 0 3
    Returns keys matching Verilog port names: go, addend, multiplier, ...
    """
    result: dict[str, str] = {}
    for line in trace_txt.splitlines():
        m = re.match(r'\s+impl_(\w+)_in\s+(\d+\'h[0-9a-fA-F]+)\b', line)
        if m:
            result[m.group(1)] = m.group(2)
    return result


# ═══════════════════════════════════════════════════════════════════════════════
# VCS deep trace – replay counter-example through real RTL simulation
# ═══════════════════════════════════════════════════════════════════════════════

_VCS_TB_TEMPLATE = """\
`timescale 1ns/1ns

module tb_replay;
    reg        go;
    reg [15:0] multiplier;
    reg [15:0] multiplicand;
    reg [15:0] addend;
    reg [2:0]  rounding_mode;
    reg [3:0]  op_i;
    reg        op_mod_i;
    reg        clock;
    reg        resetN;

    wire [15:0] result;
    wire [4:0]  exceptions;
    wire        valid;

    initial begin
        $dumpfile("replay.vcd");
        $dumpvars(0, tb_replay);
        clock = 0;
        resetN = 1'b0;
        go = 1'b0;
        multiplier    = {MULTIPLIER};
        multiplicand  = {MULTIPLICAND};
        addend        = {ADDEND};
        rounding_mode = {ROUNDING_MODE};
        op_i          = {OP_I};
        op_mod_i      = {OP_MOD_I};

        repeat(3) @(posedge clock);
        #1 resetN = 1'b1;

        go = 1'b1;
        @(posedge clock);
        go = 1'b0;

        repeat(3) @(posedge clock);
        $display("result=%h exceptions=%b valid=%b", result, exceptions, valid);
        repeat(2) @(posedge clock);
        $finish;
    end

    always #5 clock = ~clock;

    {top_module} #(.NUM_PIPE_REGS(0)) u_dut (
        .result        (result),
        .exceptions    (exceptions),
        .valid         (valid),
        .go            (go),
        .multiplier    (multiplier),
        .multiplicand  (multiplicand),
        .addend        (addend),
        .rounding_mode (rounding_mode),
        .op_i          (op_i),
        .op_mod_i      (op_mod_i),
        .clock         (clock),
        .resetN        (resetN)
    );
endmodule
"""


def run_vcs_replay(
    run_dir:   Path,
    trace_txt: str,
    top_impl:  str,
    tcl_text:  str,
    lemma:     str,
) -> str | None:
    """Replay counter-example via VCS simulation, produce replay.vcd."""
    cex = parse_counter_example(trace_txt)
    if not cex:
        return None

    docker_run_dir = to_docker_path(str(run_dir.resolve()))
    vcs_dir = f"{docker_run_dir}/vcs_{lemma}"

    # Build TB with counter-example values from trace
    raw_tb = _VCS_TB_TEMPLATE.replace("{top_module}", top_impl)
    for port, val in cex.items():
        raw_tb = raw_tb.replace(f"{{{port.upper()}}}", val)

    # Parse RTL paths from the TCL compile_impl vcs block
    # These paths are relative to run_dir (same as hector uses)
    m = re.search(r'vcs\s+(.*?)compile_design\s+impl', tcl_text, re.DOTALL)
    if not m:
        return None
    vcs_block = m.group(1)

    rtl_parts = []
    for line in vcs_block.splitlines():
        line = line.strip().rstrip("\\").strip()
        if not line or line.startswith("#"):
            continue
        rtl_parts.append(line)

    rtl_args = " ".join(rtl_parts)

    # Create vcs dir inside docker
    subprocess.run(
        ["docker", "exec", DOCKER_CONTAINER, "mkdir", "-p", vcs_dir],
        check=False, capture_output=True,
    )

    vcs_cmd = f"""\
cat > {vcs_dir}/tb_replay.sv << 'VCDEOF'
{raw_tb}
VCDEOF
cd {docker_run_dir} && \
vcs -sverilog -full64 -top tb_replay -timescale=1ns/1ns \
    {rtl_args} \
    {vcs_dir}/tb_replay.sv \
    -o {vcs_dir}/simv \
    2>&1 && \
cd {vcs_dir} && ./simv 2>&1
"""

    result = subprocess.run(
        ["docker", "exec", DOCKER_CONTAINER, "bash", "-lc", vcs_cmd],
        check=False, capture_output=True, text=True, timeout=300,
    )
    # Log any errors via docker to avoid permission issues
    vcs_log = f"{vcs_dir}/vcs_build.log"
    vcs_err = f"=== stdout ===\n{result.stdout}\n=== stderr ===\n{result.stderr}"
    subprocess.run(
        ["docker", "exec", DOCKER_CONTAINER, "bash", "-c", f"echo '{vcs_err}' > {vcs_log}"],
        check=False, capture_output=True,
    )

    vcd_host = run_dir / f"vcs_{lemma}" / "replay.vcd"
    if vcd_host.exists() and vcd_host.stat().st_size > 0:
        return str(vcd_host.resolve())
    return None


# ═══════════════════════════════════════════════════════════════════════════════
# Per-case runner
# ═══════════════════════════════════════════════════════════════════════════════

_SIMCEX_TCL = textwrap.dedent("""\
proc _extract_failed_traces {} {
    file mkdir traces
    set failed [getlemmas -status failed]
    if {[llength $failed] == 0} {
        puts "All lemmas proven, no traces to extract."
        return
    }
    foreach i $failed {
        set lemma [lindex $i 0]
        puts "========== FAILED LEMMA: $lemma =========="

        # 1) Structured counter-example dump (inputs to file)
        set txt_path "traces/trace_${lemma}.txt"
        catch { simcex $lemma -print -txt $txt_path } err1

        # 2) Waveform (FSDB) for Verdi debug
        set fsdb_path "traces/wave_${lemma}.fsdb"
        catch { simcex $lemma -fsdb $fsdb_path } err2

        # 3) Full all-signal dump via simcex -print to stdout
        puts "@@@SIMCEX_BEGIN $lemma@@@"
        catch { simcex $lemma -print } err3
        puts "@@@SIMCEX_END $lemma@@@"

        # 4) Lemma status and proof details
        puts "@@@PROOF_DETAILS $lemma@@@"
        catch { listproofs } err4

        # 5) Design signal mappings
        puts "@@@SIGNAL_MAPPINGS $lemma@@@"
        catch { report_dpv_mappings } err5

        puts "Traces for $lemma saved: $txt_path $fsdb_path"
    }
}
_extract_failed_traces
""")


def run_one_case(
    case_name:    str,
    case_info:    dict,
    timeout:      int,
    workers:      int,
    run_base_dir: Path,
    log_dir:      Path,
    deep_trace:   bool = False,
) -> tuple[str, str, str]:
    """Returns (log_path, status, traces_dir)."""

    run_dir  = run_base_dir / case_name
    run_dir.mkdir(parents=True, exist_ok=True)
    log_path = log_dir / f"hector_{case_name}.log"

    # ── Generate host.qsub ──
    tmp_dir = f"/tmp/hector_qsub_{case_name}"
    subprocess.run(
        ["docker", "exec", DOCKER_CONTAINER, "mkdir", "-p", tmp_dir],
        check=False, capture_output=True,
    )
    (run_dir / "host.qsub").write_text(
        f"1 | localhost | {workers} | {tmp_dir} | SSH | ssh\n"
    )

    # ── Remove stale session.lock ──
    lock = run_dir / "vcst_rtdb" / "session.lock"
    if lock.exists():
        lock.unlink()

    # ── Generate trace extraction TCL ──
    (run_dir / "_extract_trace.tcl").write_text(_SIMCEX_TCL)

    # ── Use original TCL ──
    tcl_src         = Path(case_info["tcl_script"])
    docker_run_dir  = to_docker_path(str(run_dir.resolve()))
    docker_tcl_path = to_docker_path(str(tcl_src.resolve()))
    docker_trace    = to_docker_path(str((run_dir / "_extract_trace.tcl").resolve()))

    vcf_cmd = (
        f"cd {docker_run_dir} && "
        f"vcf -fmode DPV -batch "
        f"-f {docker_tcl_path} "
        f'-y "make; run_main; source {docker_trace}"'
    )
    cmd = ["docker", "exec", DOCKER_CONTAINER, "bash", "-lc", vcf_cmd]

    try:
        with log_path.open("w", encoding="utf-8") as f:
            f.write("[HEADER]\n")
            f.write(f"case:            {case_name}\n")
            f.write(f"tcl_script:      {tcl_src}\n")
            f.write(f"run_dir(host):   {run_dir}\n")
            f.write(f"run_dir(docker): {docker_run_dir}\n")
            f.write(f"top_impl:        {case_info.get('top_impl', '')}\n")
            f.write(f"timeout:         {timeout}s\n")
            f.write(f"workers:         {workers}\n")
            f.write(f"deep_trace:      {deep_trace}\n")
            f.write("[COMMAND]\n")
            f.write(" ".join(cmd) + "\n")
            f.write("[OUTPUT]\n")
            f.flush()

            proc = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                errors="replace",
                start_new_session=True,
            )

            timed_out = False
            try:
                output, _ = proc.communicate(timeout=timeout)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except OSError:
                    proc.kill()
                output, _ = proc.communicate()
                timed_out = True

            output = output or ""
            f.write(output)
            if output and not output.endswith("\n"):
                f.write("\n")

            status = parse_hector_status(output, timed_out)
            f.write("[STATUS]\n")
            f.write(f"{status}\n")

            # ── Copy traces to log_dir ──
            traces_dst = ""
            traces_src = run_dir / "traces"
            if traces_src.exists() and any(traces_src.iterdir()):

                # Deep trace: run VCS replay for each failed lemma to get
                # internal signal VCD via real RTL simulation
                if deep_trace and status == STATUS_FAILED:
                    top_impl = case_info.get("top_impl", "")
                    tcl_text = Path(case_info["tcl_script"]).read_text(errors="ignore")
                    for txt_file in sorted(traces_src.glob("trace_*.txt")):
                        lemma = txt_file.stem.replace("trace_", "")
                        cex_text = txt_file.read_text(errors="ignore")
                        f.write(f"[VCS_REPLAY] Running VCS for lemma: {lemma}\n")
                        vcd = run_vcs_replay(
                            run_dir, cex_text, top_impl, tcl_text, lemma
                        )
                        if vcd:
                            f.write(f"[VCS_REPLAY] VCD saved: {vcd}\n")

                traces_dst = str(log_dir / f"traces_{case_name}")
                shutil.copytree(str(traces_src), str(traces_dst), dirs_exist_ok=True)
                f.write(f"[TRACES]\n{traces_dst}\n")

                # Extract delimited sections from output into per-lemma dump files
                for section_name in ["SIMCEX_BEGIN", "PROOF_DETAILS", "SIGNAL_MAPPINGS"]:
                    pattern = re.compile(
                        rf'@@@{section_name} (\S+)@@@(.*?)(?=@@@\w|$)',
                        re.DOTALL,
                    )
                    file_prefix = section_name.lower().replace("_begin", "")
                    for m in pattern.finditer(output):
                        lemma = m.group(1)
                        content = m.group(2).strip()
                        if content and len(content) > 10:
                            dump_file = Path(traces_dst) / f"{file_prefix}_{lemma}.txt"
                            dump_file.write_text(content)

        return str(log_path.resolve()), status, traces_dst

    except Exception:
        err_text = traceback.format_exc()
        with log_path.open("w", encoding="utf-8") as f:
            f.write(err_text)
            f.write("\n[STATUS]\n")
            f.write(f"{STATUS_OTHER_ERROR}\n")
        return str(log_path.resolve()), STATUS_OTHER_ERROR, ""


# ═══════════════════════════════════════════════════════════════════════════════
# Report
# ═══════════════════════════════════════════════════════════════════════════════

def write_report(cases: dict, report_path: Path) -> None:
    lines = [
        "| Case | Top Impl | Status | Traces | Log File |",
        "| --- | --- | --- | --- | --- |",
    ]
    for name in sorted(cases):
        info = cases[name]
        traces = info.get("traces", "")
        if traces:
            traces = f"[traces]({traces})"
        lines.append(
            f"| {name} "
            f"| {info.get('top_impl', '')} "
            f"| {info.get('status', STATUS_OTHER_ERROR)} "
            f"| {traces} "
            f"| {info.get('hector_log', '')} |"
        )
    report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


# ═══════════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════════

def main(
    timeout:      int,
    thread:       int,
    workers:      int,
    info_json:    str,
    log_dir:      str,
    run_base_dir: str,
    deep_trace:   bool,
) -> None:
    data  = json.loads(Path(info_json).read_text(encoding="utf-8"))
    cases: dict = data["cases"]

    out_dir      = Path(log_dir).resolve()
    hector_log   = out_dir / "hector_log"
    run_base     = Path(run_base_dir).resolve() if run_base_dir else hector_log
    out_dir.mkdir(parents=True, exist_ok=True)
    hector_log.mkdir(parents=True, exist_ok=True)

    with ThreadPoolExecutor(max_workers=max(1, thread)) as executor:
        future_to_name = {
            executor.submit(
                run_one_case, name, info, timeout, workers,
                run_base, hector_log, deep_trace,
            ): name
            for name, info in cases.items()
        }
        for future in as_completed(future_to_name):
            name = future_to_name[future]
            log_path, status, traces = future.result()
            cases[name]["hector_log"] = log_path
            cases[name]["status"]     = status
            cases[name]["traces"]     = traces
            print(f"[{status}] {name}  ->  {log_path}")

    write_report(cases, out_dir / "report.md")
    print(f"\nReport written to: {out_dir / 'report.md'}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Run hector (vcf DPV) verification cases from analysis.json"
    )
    parser.add_argument("--timeout",      type=int, default=3600)
    parser.add_argument("--thread",       type=int, default=1)
    parser.add_argument("--workers",      type=int, default=16)
    parser.add_argument("--info_json",    required=True)
    parser.add_argument("--log_dir",      required=True)
    parser.add_argument("--run_base_dir", default="")
    parser.add_argument("--deep_trace",   action="store_true",
                        help="On failure, replay counter-example in VCS and "
                             "dump full internal signal VCD")
    args = parser.parse_args()
    main(args.timeout, args.thread, args.workers,
         args.info_json, args.log_dir, args.run_base_dir,
         args.deep_trace)
