#!/usr/bin/env python3
"""
Analyze hector (vcf DPV) TCL scripts and generate analysis.json.

For each TCL script, extracts ALL paths directly from the TCL:
  - top_impl  : RTL top module (from create_design -name impl -top <X>)
  - top_spec  : C++ wrapper top (from create_design -name spec -top <X>)
  - rtl_files : all .sv/.v files listed in the vcs block (absolute paths,
                resolved relative to the TCL file's directory)
  - spec_files: all .cpp/.c files listed in the cppan block
  - incdir    : all +incdir+ paths

No need to pass --rtl_dirs; all paths are parsed directly from the TCL.
"""

import re
import json
import argparse
from pathlib import Path


def resolve_path(p: str, tcl_dir: Path) -> str:
    """Resolve a path relative to the TCL file's directory."""
    resolved = (tcl_dir / p).resolve()
    return str(resolved)


def parse_tcl(tcl_path: str) -> dict:
    """
    Parse a hector TCL script and extract all relevant information.
    All relative paths are resolved against the TCL file's directory.
    """
    tcl_file = Path(tcl_path).resolve()
    tcl_dir  = tcl_file.parent
    text     = tcl_file.read_text(errors="ignore")

    # ── top_impl / top_spec ──
    top_impl, top_spec = "", ""
    m = re.search(r'create_design\s+.*?-name\s+impl.*?-top\s+(\S+)', text, re.DOTALL)
    if not m:
        m = re.search(r'create_design\s+.*?-top\s+(\S+).*?-name\s+impl', text, re.DOTALL)
    if m:
        top_impl = m.group(1)

    m = re.search(r'create_design\s+.*?-name\s+spec.*?-top\s+(\S+)', text, re.DOTALL)
    if not m:
        m = re.search(r'create_design\s+.*?-top\s+(\S+).*?-name\s+spec', text, re.DOTALL)
    if m:
        top_spec = m.group(1)

    # ── Extract vcs block ──
    rtl_files = []
    incdirs   = []
    vcs_match = re.search(r'vcs\s+(.*?)compile_design\s+impl', text, re.DOTALL)
    if vcs_match:
        vcs_block = vcs_match.group(1)
        for line in vcs_block.splitlines():
            line = line.strip().rstrip("\\").strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("+incdir+"):
                incdir = line[len("+incdir+"):]
                incdirs.append(resolve_path(incdir, tcl_dir))
            elif line.endswith(".sv") or line.endswith(".v"):
                rtl_files.append(resolve_path(line, tcl_dir))

    # ── Extract cppan block ──
    spec_files  = []
    cppan_match = re.search(r'cppan\s+(.*?)compile_design\s+spec', text, re.DOTALL)
    if cppan_match:
        cppan_block = cppan_match.group(1)
        for line in cppan_block.splitlines():
            line = line.strip().rstrip("\\").strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("-I"):
                pass  # include dirs, skip
            elif line.startswith("-D"):
                pass  # defines, skip
            elif line.endswith(".cpp") or line.endswith(".c"):
                spec_files.append(resolve_path(line, tcl_dir))

    return {
        "tcl_script": str(tcl_file),
        "tcl_dir":    str(tcl_dir),
        "top_impl":   top_impl,
        "top_spec":   top_spec,
        "rtl_files":  rtl_files,
        "incdirs":    incdirs,
        "spec_files": spec_files,
    }


def main(tcl_scripts: list[str], log_dir: str) -> None:
    cases: dict = {}

    for tcl_path in tcl_scripts:
        case_key        = Path(tcl_path).name
        cases[case_key] = parse_tcl(tcl_path)

    out_path = Path(log_dir) / "analysis.json"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps({"cases": cases}, indent=2))
    print(out_path)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Analyse hector TCL scripts and write analysis.json"
    )
    parser.add_argument(
        "--tcl_scripts", "-t",
        nargs="+", required=True, metavar="TCL_FILE",
        help="One or more hector TCL verification script paths",
    )
    parser.add_argument(
        "--log_dir", "-l",
        required=True, metavar="DIR",
        help="Directory where analysis.json will be written",
    )
    args = parser.parse_args()
    main(args.tcl_scripts, args.log_dir)