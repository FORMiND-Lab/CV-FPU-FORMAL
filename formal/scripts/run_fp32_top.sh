#!/bin/bash
#=============================================================================
# run_fp32_top.sh — FP32 Formal Verification for fpu_top_wrap_fp32
#
# Runs Hector DPV proofs comparing fpu_top_wrap_fp32 (fpnew_top-based
# implementation) against the SoftFloat C++ spec model.
#
# Usage (inside EDA Docker container):
#   cd /home/eda
#   ./formal/scripts/run_fp32_top.sh <operation>
#
# Operations (top-wrapper TCLs):
#   add     — Addition                (op_i=2, op_mod=0)  [READY]
#   sub     — Subtraction             (op_i=2, op_mod=1)  [TODO]
#   mul     — Multiplication          (op_i=3)             [TODO]
#   fmadd   — Fused Multiply-Add      (op_i=0, op_mod=0)  [TODO]
#   fmsub   — Fused Multiply-Sub      (op_i=0, op_mod=1)  [TODO]
#   fnmsub  — Negated Multiply-Add    (op_i=1, op_mod=0)  [TODO]
#   fnmadd  — Negated Multiply-Sub    (op_i=1, op_mod=1)  [TODO]
#
# Examples:
#   ./formal/scripts/run_fp32_top.sh add
#   ./formal/scripts/run_fp32_top.sh add 8
#=============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORMAL_DIR="$(dirname "$SCRIPT_DIR")"
PROJ_DIR="$(dirname "$FORMAL_DIR")"
TCL_DIR="$FORMAL_DIR/tcl"
RUN_DIR="$FORMAL_DIR/run"
WORKERS="${HECTOR_WORKERS:-16}"

# ---- Validate working directory ----
CURRENT_DIR="$(pwd)"
if [ "$CURRENT_DIR" != "$PROJ_DIR" ]; then
    echo "ERROR: Must run from project root."
    echo "  cd $PROJ_DIR"
    echo "  ./formal/scripts/run_fp32_top.sh <operation>"
    exit 1
fi

if ! command -v vcf &> /dev/null; then
    echo "[ERROR] vcf not found in PATH."
    exit 1
fi

# ---- Operation → TCL mapping (top wrapper) ----
# Only ADD is active for the initial top-wrapper proof.
# Other operations will be added in subsequent commits
# (per top_migration_plan.md Phase 7 / Commit 4-5).
declare -A TCL_MAP=(
    ["add"]="command_script_fp32_add_top.tcl"
    # ["sub"]="command_script_fp32_sub_top.tcl"
    # ["mul"]="command_script_fp32_mul_top.tcl"
    # ["fmadd"]="command_script_fp32_fmadd_top.tcl"
    # ["fmsub"]="command_script_fp32_fmsub_top.tcl"
    # ["fnmsub"]="command_script_fp32_fnmsub_top.tcl"
    # ["fnmadd"]="command_script_fp32_fnmadd_top.tcl"
)

# ---- Usage ----
usage() {
    echo "Usage: $0 <operation> [workers]"
    echo ""
    echo "Operations (top wrapper):"
    echo "  add      — Addition                (op_i=2, op_mod=0) [READY]"
    echo ""
    echo "Planned (TCL not yet created):"
    echo "  sub      — Subtraction             (op_i=2, op_mod=1)"
    echo "  mul      — Multiplication          (op_i=3)"
    echo "  fmadd    — Fused Multiply-Add      (op_i=0, op_mod=0)"
    echo "  fmsub    — Fused Multiply-Sub      (op_i=0, op_mod=1)"
    echo "  fnmsub   — Negated Multiply-Add    (op_i=1, op_mod=0)"
    echo "  fnmadd   — Negated Multiply-Sub    (op_i=1, op_mod=1)"
    echo ""
    echo "Examples:"
    echo "  $0 add          # default 16 workers"
    echo "  $0 add 8        # 8 workers"
    exit 1
}

# ---- Single run ----
run_op() {
    local op="$1"
    local tcl="${TCL_MAP[$op]}"
    local tcl_path="$TCL_DIR/$tcl"
    local run_dir="$RUN_DIR/fp32_top_$op"
    local tmp_dir="/tmp/hector_qsub_fp32_top_$op"

    if [ ! -f "$tcl_path" ]; then
        echo "[ERROR] TCL file not found: $tcl_path"
        exit 1
    fi

    mkdir -p "$run_dir" "$tmp_dir"
    chmod 777 "$tmp_dir"

    # Generate per-proof host.qsub
    cat > "$run_dir/host.qsub" <<EOF
1 | localhost | ${WORKERS} | $tmp_dir | SSH | ssh
EOF

    cd "$run_dir"

    echo "============================================================"
    echo " Hector DPV: FP32 $op (top wrapper — fpnew_top)"
    echo " TCL:       $tcl"
    echo " Run dir:   $run_dir"
    echo " Tmp dir:   $tmp_dir"
    echo " Workers:   $WORKERS"
    echo "============================================================"

    vcf -f "$tcl_path" -fmode DPV

    echo ""
    echo "============================================================"
    echo " Done ($op top). Artifacts in: $run_dir"
    echo "============================================================"

    cd "$PROJ_DIR"
}

# ---- Main ----
OP="${1:-}"
WORKERS="${2:-${HECTOR_WORKERS:-16}}"

if [ -z "$OP" ]; then
    echo "ERROR: No operation specified."
    usage
fi

if [ -n "${TCL_MAP[$OP]:-}" ]; then
    run_op "$OP"
else
    echo "ERROR: Unknown operation '$OP' (or TCL not yet created for top wrapper)."
    usage
fi
