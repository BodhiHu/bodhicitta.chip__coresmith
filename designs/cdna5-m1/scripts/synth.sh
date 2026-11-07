#!/usr/bin/env bash
# Copyright (c) 2026 CDNA5-M1 project.
# SPDX-License-Identifier: MIT
#
# synth.sh -- Yosys Sky130 synthesis for the M1 blocks and chip top.
# Uses exactly the PDK/liberty pinned by coresmith/scripts/pdk-version.env.
#
#   scripts/synth.sh wmma|simd32|wgp|top
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
cd "$HERE"

CORESMITH=$(cd "$HERE/../.." && pwd)
PDK_ROOT=${PDK_ROOT:-$CORESMITH/.pdk}
LIB=$PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
export PATH=/opt/eda/oss-cad-suite/bin:${PATH}

if [ ! -f "$LIB" ]; then
  echo "Missing Sky130 Liberty: $LIB" >&2
  echo "Run coresmith setup (see ../SETUP.md) or set PDK_ROOT." >&2
  exit 1
fi

BLOCK=${1:-wmma}
case "$BLOCK" in
  wmma)   TOP=wmma;    SRCS="rtl/wmma.v" ;;
  simd32) TOP=simd32;  SRCS="rtl/simd32.v" ;;
  wgp)    TOP=wgp;     SRCS="rtl/wgp.v rtl/simd32.v rtl/lds.v rtl/wmma.v rtl/tdm.v" ;;
  top)    TOP=cdna5_m1_top; SRCS="rtl/cdna5_m1_top.v rtl/command_processor.v rtl/axi_lite_slave.v rtl/axi_master.v rtl/wgp.v rtl/simd32.v rtl/lds.v rtl/wmma.v rtl/tdm.v" ;;
  *) echo "unknown block '$BLOCK' (wmma|simd32|wgp|top)" >&2; exit 2 ;;
esac

mkdir -p "syn/$BLOCK"
cat > "syn/$BLOCK/synth.ys" <<EOF
read_verilog -Irtl $SRCS
hierarchy -top $TOP
synth -top $TOP -flatten
dfflibmap -liberty $LIB
abc -liberty $LIB
opt_clean
stat
write_verilog -noattr syn/$BLOCK/${TOP}_netlist.v
write_json syn/$BLOCK/${TOP}_netlist.json
EOF

echo "=== Yosys synth: $TOP (Sky130 tt_025C_1v80, 100 MHz target) ==="
yosys -s "syn/$BLOCK/synth.ys" 2>&1 | tee "syn/$BLOCK/yosys.log"
