#!/bin/bash
#=============================================================================
# run_hector.sh — Launch Hector DPV formal verification for FP32 FMA
#
# Usage (inside EDA Docker container):
#   cd /home/eda                      # project root
#   ./hector/scripts/run_hector.sh
#
# All intermediate files (logs, DBs) go into hector/run/.
#=============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HECTOR_DIR="$(dirname "$SCRIPT_DIR")"
PROJ_DIR="$(dirname "$HECTOR_DIR")"
RUN_DIR="$HECTOR_DIR/run"

# ---- Enforce working directory is project root ----
CURRENT_DIR="$(pwd)"
if [ "$CURRENT_DIR" != "$PROJ_DIR" ]; then
    echo "============================================================"
    echo " ERROR: Wrong working directory"
    echo "============================================================"
    echo " Current dir:  $CURRENT_DIR"
    echo " Required dir: $PROJ_DIR  (project root)"
    echo ""
    echo " Please run from project root:"
    echo "   cd $PROJ_DIR"
    echo "   ./hector/scripts/run_hector.sh"
    echo "============================================================"
    exit 1
fi

# ---- Check vcf is available ----
if ! command -v vcf &> /dev/null; then
    echo "[ERROR] vcf (VC Formal) not found in PATH."
    exit 1
fi

# ---- Ensure run directory exists ----
mkdir -p "$RUN_DIR"

echo "============================================================"
echo " Hector DPV: FP32 FMA Equivalence Checking"
echo "============================================================"
echo " Project dir:  $PROJ_DIR"
echo " Run dir:      $RUN_DIR"
echo "============================================================"

# ---- Run from hector/run/ so all artifacts stay there ----
cd "$RUN_DIR"

echo ""
echo "[INFO] Starting Hector DPV proof..."
echo ""

vcf -f ../tcl/command_script_fma32.tcl -fmode DPV

echo ""
echo "============================================================"
echo " Hector run complete."
echo " Artifacts in: $RUN_DIR"
echo "============================================================"
