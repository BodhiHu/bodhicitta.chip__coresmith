#!/usr/bin/env bash
# Copyright (c) 2026 CDNA5-M1 project.
# SPDX-License-Identifier: MIT
#
# run_pnr.sh -- OpenROAD P&R for a block (wmma|simd32) on the CoreSmith Sky130 PDK.
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
cd "$HERE"
BLOCK=${1:-wmma}
CORESMITH=$(cd "$HERE/../.." && pwd)
export PDK_ROOT=${PDK_ROOT:-$CORESMITH/.pdk}
OPENROAD_BIN=${OPENROAD_BIN:-openroad}
UTILIZATION=${UTILIZATION:-0.35}

case "$BLOCK" in
  wmma)   DESIGN=wmma;   NETLIST=syn/wmma/wmma_netlist.v ;;
  simd32) DESIGN=simd32; NETLIST=syn/simd32/simd32_netlist.v ;;
  tdm)    DESIGN=tdm;    NETLIST=syn/tdm/tdm_netlist.v ;;
  *) echo "run_pnr.sh supports wmma|simd32|tdm" >&2; exit 2 ;;
esac
if [ ! -f "$NETLIST" ]; then
  echo "Missing netlist $NETLIST -- run scripts/synth.sh $BLOCK first" >&2
  exit 1
fi
mkdir -p "pnr/$BLOCK"
export DESIGN NETLIST SDC="constraints/$BLOCK.sdc" OUT_DIR="pnr/$BLOCK" UTILIZATION
echo "=== OpenROAD P&R: $DESIGN (100 MHz, util $UTILIZATION) ==="
"$OPENROAD_BIN" -no_init -exit scripts/pnr.tcl 2>&1 | tee "pnr/$BLOCK/pnr.log"
