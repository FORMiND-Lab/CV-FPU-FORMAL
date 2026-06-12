#!/usr/bin/env python3
"""
Run hector (vcf DPV) verification from analysis.json.

For each case:
  1. Creates a dedicated run directory under log_dir/hector_log/<case>/
  2. Copies the patched TCL script into the run directory
  3. Generates host.qsub in the run directory
  4. Removes stale session.lock if present
  5. Runs via docker exec: vcf -fmode DPV -batch -f <patched.tcl> -y "make; run_main"
  6. Parses listproofs output to determine PASS/FAIL
  7. Writes structured log and summary report.md
"""

import argparse
import json
import os
import re
import signal
import subprocess
import traceback
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

STATUS_SUCCESS     = "VERIFICATION SUCCESSFUL"
STATUS_FAILED      = "VERIFICATION FAILED"
STATUS_TIMEOUT     = "EXECUTION TIMEOUT"
STATUS_OTHER_ERROR = "OTHER ERROR"

DOCKER_CONTAINER = "eda-hector"

# 宿主机路径 → docker内部路径映射
HOST_TO_DOCKER = {
    "/home/zhangyang/workspace/eda": "/home/eda",
    "/home/zhangyang/workspace/c_rtl": "/home/c_rtl",
}

def to_docker_path(host_path: str) -> str:
    """Convert host path to docker internal path."""
    for host_prefix, docker_prefix in HOST_TO_DOCKER.items():
        if str(host_path).startswith(host_prefix):
            return str(host_path).replace(host_prefix, docker_prefix, 1)
    return str(host_path)


# ── TCL patching ─────────────────────────────────────────────────────────────

def patch_tcl_rtl_files(tcl_text: str, rtl_files: list[str]) -> str:
    rtl_lines = "\n".join(f"        {f}" for f in rtl_files)

    def _replace_vcs_block(m: re.Match) -> str:
        block = m.group(0)
        cleaned_lines = []
        for line in block.splitlines():
            stripped = line.strip()
            if stripped.endswith(".sv") or stripped.endswith(".v"):
                continue
            cleaned_lines.append(line)
        cleaned = "\n".join(cleaned_lines).rstrip()
        return cleaned + "\n" + rtl_lines + "\n"

    patched = re.sub(
        r'(vcs\s.*?compile_design\s+impl)',
        _replace_vcs_block,
        tcl_text,
        flags=re.DOTALL,
    )
    return patched


# ── Result parsing ────────────────────────────────────────────────────────────

def parse_hector_status(output: str, timed_out: bool) -> str:
    if timed_out:
        return STATUS_TIMEOUT

    proven     = re.findall(r'Proof\s+\S+:\s+PROVEN', output)
    failed     = re.findall(r'Proof\s+\S+:\s+FAILED', output)
    all_proven = bool(re.search(
        r'All\s+\d+\s+proof\s+obligations?\s+proven', output, re.I
    ))

    if failed:
        return STATUS_FAILED
    if all_proven or (proven and not failed):
        return STATUS_SUCCESS
    if "Error" in output or "ERROR" in output:
        return STATUS_OTHER_ERROR
    return STATUS_OTHER_ERROR


# ── Per-case runner ───────────────────────────────────────────────────────────

def run_one_case(
    case_name: str,
    case_info: dict,
    timeout:   int,
    workers:   int,
    hector_log_dir: Path,
) -> tuple[str, str]:

    # ── Per-case run directory ──
    run_dir  = hector_log_dir / case_name
    run_dir.mkdir(parents=True, exist_ok=True)
    log_path = hector_log_dir / f"hector_{case_name}.log"

    # ── 1. Read and patch TCL ──
    tcl_src = Path(case_info["tcl_script"])
    if not tcl_src.exists():
        err = f"TCL script not found: {tcl_src}"
        log_path.write_text(f"[ERROR]\n{err}\n[STATUS]\n{STATUS_OTHER_ERROR}\n")
        return str(log_path.resolve()), STATUS_OTHER_ERROR

    tcl_text = tcl_src.read_text(errors="ignore")
    if case_info.get("rtl_files"):
        # 注入 docker 内部的绝对路径
        docker_rtl_files = [to_docker_path(f) for f in case_info["rtl_files"]]
        tcl_text = patch_tcl_rtl_files(tcl_text, docker_rtl_files)

    patched_tcl = run_dir / f"{case_name}_patched.tcl"
    patched_tcl.write_text(tcl_text)

    # ── 2. Generate host.qsub ──
    tmp_dir = f"/tmp/hector_qsub_{case_name}"
    os.makedirs(tmp_dir, mode=0o777, exist_ok=True)
    (run_dir / "host.qsub").write_text(
        f"1 | localhost | {workers} | {tmp_dir} | SSH | ssh\n"
    )

    # ── 3. Remove stale session.lock ──
    lock = run_dir / "vcst_rtdb" / "session.lock"
    if lock.exists():
        lock.unlink()

    # ── 4. Build command via docker exec ──
    docker_run_dir  = to_docker_path(str(run_dir.resolve()))
    docker_tcl_path = to_docker_path(str(patched_tcl.resolve()))

    vcf_cmd = (
        f"cd {docker_run_dir} && "
        f"vcf -fmode DPV -batch "
        f"-f {docker_tcl_path} "
        f"-y 'make; run_main'"
    )
    cmd = ["docker", "exec", DOCKER_CONTAINER, "bash", "-c", vcf_cmd]

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
            f.write("rtl_files:\n")
            for rf in case_info.get("rtl_files", []):
                f.write(f"  - {rf}\n")
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

        return str(log_path.resolve()), status

    except Exception:
        err_text = traceback.format_exc()
        with log_path.open("w", encoding="utf-8") as f:
            f.write(err_text)
            f.write("\n[STATUS]\n")
            f.write(f"{STATUS_OTHER_ERROR}\n")
        return str(log_path.resolve()), STATUS_OTHER_ERROR


# ── Report ────────────────────────────────────────────────────────────────────

def write_report(cases: dict, report_path: Path) -> None:
    lines = [
        "| Case | Top Impl | TCL Script | Log File | Status |",
        "| --- | --- | --- | --- | --- |",
    ]
    for name in sorted(cases):
        info = cases[name]
        lines.append(
            f"| {name} "
            f"| {info.get('top_impl', '')} "
            f"| {info.get('tcl_script', '')} "
            f"| {info.get('hector_log', '')} "
            f"| {info.get('status', STATUS_OTHER_ERROR)} |"
        )
    report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


# ── Main ──────────────────────────────────────────────────────────────────────

def main(timeout: int, thread: int, workers: int, info_json: str, log_dir: str) -> None:
    data  = json.loads(Path(info_json).read_text(encoding="utf-8"))
    cases: dict = data["cases"]

    out_dir        = Path(log_dir).resolve()
    hector_log_dir = out_dir / "hector_log"
    out_dir.mkdir(parents=True, exist_ok=True)
    hector_log_dir.mkdir(parents=True, exist_ok=True)

    with ThreadPoolExecutor(max_workers=max(1, thread)) as executor:
        future_to_name = {
            executor.submit(
                run_one_case, name, info, timeout, workers, hector_log_dir
            ): name
            for name, info in cases.items()
        }
        for future in as_completed(future_to_name):
            name = future_to_name[future]
            log_path, status = future.result()
            cases[name]["hector_log"] = log_path
            cases[name]["status"]     = status
            print(f"[{status}] {name}  ->  {log_path}")

    write_report(cases, out_dir / "report.md")
    print(f"\nReport written to: {out_dir / 'report.md'}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Run hector (vcf DPV) verification cases from analysis.json"
    )
    parser.add_argument("--timeout",   type=int, default=3600, metavar="SECONDS")
    parser.add_argument("--thread",    type=int, default=1,    metavar="N")
    parser.add_argument("--workers",   type=int, default=16,   metavar="N")
    parser.add_argument("--info_json", required=True, metavar="PATH")
    parser.add_argument("--log_dir",   required=True, metavar="DIR")
    args = parser.parse_args()
    main(args.timeout, args.thread, args.workers, args.info_json, args.log_dir)