#!/bin/bash
#=============================================================================
# run_add_verify.sh — ADD 验证启动脚本 (Hector DPV)
#
# Usage (inside EDA Docker container):
#   cd /home/eda/cosim_ref/formal
#   ./scripts/run_add_verify.sh <precision>
#
# Precisions:
#   16  — FP16 ADD
#   32  — FP32 ADD
#   64  — FP64 ADD
#
# Examples:
#   ./scripts/run_add_verify.sh 16
#   ./scripts/run_add_verify.sh 64
#=============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORMAL_DIR="$(dirname "$SCRIPT_DIR")"
RUN_BASE="$FORMAL_DIR/run"
TCL_DIR="$FORMAL_DIR/tcl"
WORKERS="${HECTOR_WORKERS:-16}"

# ---- Usage ----
usage() {
    echo "Usage: $0 <precision>"
    echo ""
    echo "Precisions:"
    echo "  16  — FP16 ADD"
    echo "  32  — FP32 ADD"
    echo "  64  — FP64 ADD"
    echo ""
    echo "Examples:"
    echo "  $0 16"
    echo "  $0 64"
    exit 1
}

# ---- Validate input ----
PREC="${1:-}"
if [ -z "$PREC" ]; then
    echo "ERROR: No precision specified."
    usage
fi

case "$PREC" in
    16|32|64) ;;
    *)
        echo "ERROR: Unknown precision '$PREC'. Must be 16, 32, or 64."
        usage
        ;;
esac

RUN_DIR="$RUN_BASE/run_add${PREC}"
TCL_FILE="$TCL_DIR/command_script_add${PREC}.tcl"

# ---- Validate vcf ----
if ! command -v vcf &> /dev/null; then
    echo "[ERROR] vcf not found in PATH. Are you inside the EDA docker container?"
    exit 1
fi

# ---- Validate TCL file ----
if [ ! -f "$TCL_FILE" ]; then
    echo "[ERROR] TCL file not found: $TCL_FILE"
    exit 1
fi

# ---- Create run dir if not exists ----
if [ ! -d "$RUN_DIR" ]; then
    echo "[INFO] Creating run directory: $RUN_DIR"
    mkdir -p "$RUN_DIR"
fi

# ---- Generate host.qsub ----
TMP_DIR="/tmp/hector_qsub_add${PREC}"
mkdir -p "$TMP_DIR"
chmod 777 "$TMP_DIR"
cat > "$RUN_DIR/host.qsub" <<EOF
1 | localhost | ${WORKERS} | $TMP_DIR | SSH | ssh
EOF
echo "[INFO] Generated host.qsub with $WORKERS workers"

# ---- Remove stale session lock ----
if [ -f "$RUN_DIR/vcst_rtdb/session.lock" ]; then
    echo "[INFO] Removing stale session.lock"
    rm -f "$RUN_DIR/vcst_rtdb/session.lock"
fi

# ---- Enter run dir and launch vcf ----
cd "$RUN_DIR"

echo "============================================================"
echo " Hector DPV: FP${PREC} ADD"
echo " TCL:        $TCL_FILE"
echo " Run dir:    $RUN_DIR"
echo " Workers:    $WORKERS"
echo "============================================================"

HECTOR_RUN_DIR="$RUN_DIR" setup-hector-qsub.sh "$WORKERS"

vcf -fmode DPV -batch \
    -f "../../tcl/command_script_add${PREC}.tcl" \
    -y "make; run_main"

echo ""
echo "============================================================"
echo " Done (FP${PREC} ADD). Artifacts in: $RUN_DIR"
echo "============================================================"
