#!/bin/bash
#=============================================================================
# run_directed.sh — Quick sanity check with directed test cases
#
# Usage (inside EDA Docker container):
#   cd /home/eda
#   ./formal/scripts/run_directed.sh [workers]
#
# Examples:
#   ./formal/scripts/run_directed.sh        # default 16 workers
#   ./formal/scripts/run_directed.sh 8      # 8 workers
#=============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORMAL_DIR="$(dirname "$SCRIPT_DIR")"
PROJ_DIR="$(dirname "$FORMAL_DIR")"
TCL_DIR="$FORMAL_DIR/tcl"
RUN_DIR="$FORMAL_DIR/run/fp32_directed"
TMP_DIR="/tmp/hector_qsub_fp32_directed"
WORKERS="${1:-${HECTOR_WORKERS:-16}}"

CURRENT_DIR="$(pwd)"
if [ "$CURRENT_DIR" != "$PROJ_DIR" ]; then
    echo "ERROR: Must run from project root."
    echo "  cd $PROJ_DIR"
    echo "  ./formal/scripts/run_directed.sh"
    exit 1
fi

if ! command -v vcf &> /dev/null; then
    echo "[ERROR] vcf not found in PATH."
    exit 1
fi

mkdir -p "$RUN_DIR" "$TMP_DIR"
chmod 777 "$TMP_DIR"

# Generate per-proof host.qsub
cat > "$RUN_DIR/host.qsub" <<EOF
1 | localhost | ${WORKERS} | $TMP_DIR | SSH | ssh
EOF

cd "$RUN_DIR"

echo "============================================================"
echo " Hector DPV: Directed Case Sanity Check (11 cases)"
echo " Run dir:    $RUN_DIR"
echo " Tmp dir:    $TMP_DIR"
echo " Workers:    $WORKERS"
echo "============================================================"

vcf -f ../../tcl/command_script_fp32_directed.tcl -fmode DPV

echo ""
echo "============================================================"
echo " Done. Artifacts in: $RUN_DIR"
echo "============================================================"
