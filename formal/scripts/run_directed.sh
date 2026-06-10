#!/bin/bash
#=============================================================================
# run_directed.sh — Quick sanity check with directed test cases
#
# Usage (inside EDA Docker container):
#   cd /home/eda
#   ./formal/scripts/run_directed.sh
#=============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORMAL_DIR="$(dirname "$SCRIPT_DIR")"
PROJ_DIR="$(dirname "$FORMAL_DIR")"
RUN_DIR="$FORMAL_DIR/run"

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

mkdir -p "$RUN_DIR"
cd "$RUN_DIR"

echo "============================================================"
echo " Hector DPV: Directed Case Sanity Check (11 cases)"
echo "============================================================"

vcf -f ../tcl/command_script_fp32_directed.tcl -fmode DPV

echo ""
echo "============================================================"
echo " Done. Artifacts in: $RUN_DIR"
echo "============================================================"
