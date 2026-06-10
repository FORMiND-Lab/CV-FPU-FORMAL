#!/bin/bash
#=============================================================================
# run_fp16.sh — FP16 Formal Verification (Hector DPV)
#
# Usage (inside EDA Docker container):
#   cd /home/eda
#   ./formal/scripts/run_fp16.sh <operation>
#
# Operations:
#   fmadd   — Fused Multiply-Add      (op_i=0, op_mod=0)
#   fmsub   — Fused Multiply-Sub      (op_i=0, op_mod=1)
#   fnmsub  — Negated Multiply-Add    (op_i=1, op_mod=0)
#   fnmadd  — Negated Multiply-Sub    (op_i=1, op_mod=1)
#   add     — Addition                (op_i=2, op_mod=0)
#   sub     — Subtraction             (op_i=2, op_mod=1)
#   mul     — Multiplication          (op_i=3)
#
# Examples:
#   ./formal/scripts/run_fp16.sh fmadd
#   ./formal/scripts/run_fp16.sh mul
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
    echo "  ./formal/scripts/run_fp16.sh <operation>"
    exit 1
fi

if ! command -v vcf &> /dev/null; then
    echo "[ERROR] vcf not found in PATH."
    exit 1
fi

# ---- Operation → TCL mapping ----
declare -A TCL_MAP=(
    ["fmadd"]="command_script_fp16_fmadd.tcl"
    ["fmsub"]="command_script_fp16_fmsub.tcl"
    ["fnmsub"]="command_script_fp16_fnmsub.tcl"
    ["fnmadd"]="command_script_fp16_fnmadd.tcl"
    ["add"]="command_script_fp16_add.tcl"
    ["sub"]="command_script_fp16_sub.tcl"
    ["mul"]="command_script_fp16_mul.tcl"
)

# ---- Usage ----
usage() {
    echo "Usage: $0 <operation> [workers]"
    echo ""
    echo "Operations:"
    echo "  fmadd    — Fused Multiply-Add      (op_i=0, op_mod=0)"
    echo "  fmsub    — Fused Multiply-Sub      (op_i=0, op_mod=1)"
    echo "  fnmsub   — Negated Multiply-Add    (op_i=1, op_mod=0)"
    echo "  fnmadd   — Negated Multiply-Sub    (op_i=1, op_mod=1)"
    echo "  add      — Addition                (op_i=2, op_mod=0)"
    echo "  sub      — Subtraction             (op_i=2, op_mod=1)"
    echo "  mul      — Multiplication          (op_i=3)"
    echo ""
    echo "Examples:"
    echo "  $0 fmadd        # default 16 workers"
    echo "  $0 mul 8        # 8 workers"
    exit 1
}

# ---- Single run ----
run_op() {
    local op="$1"
    local tcl="${TCL_MAP[$op]}"
    local tcl_path="$TCL_DIR/$tcl"
    local run_dir="$RUN_DIR/fp16_$op"
    local tmp_dir="/tmp/hector_qsub_fp16_$op"

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
    echo " Hector DPV: FP16 $op"
    echo " TCL:       $tcl"
    echo " Run dir:   $run_dir"
    echo " Tmp dir:   $tmp_dir"
    echo " Workers:   $WORKERS"
    echo "============================================================"

    vcf -f "$tcl_path" -fmode DPV

    echo ""
    echo "============================================================"
    echo " Done ($op). Artifacts in: $run_dir"
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
    echo "ERROR: Unknown operation '$OP'."
    usage
fi
