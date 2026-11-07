#!/usr/bin/env bash
# Copyright (c) 2026 CDNA5-M1 project.
# SPDX-License-Identifier: MIT
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
IV=/opt/eda/oss-cad-suite/bin/iverilog
VVP=/opt/eda/oss-cad-suite/bin/vvp
cd "$HERE"
"$IV" -g2005-sv -Irtl -o /tmp/tb_wmma_top.vvp \
  rtl/cdna5_m1_top.v rtl/command_processor.v rtl/axi_lite_slave.v \
  rtl/axi_master.v rtl/wgp.v rtl/simd32.v rtl/lds.v rtl/wmma.v \
  rtl/tdm.v rtl/sfu.v rtl/softmax_engine.v tb/tb_wmma_top.v
"$VVP" /tmp/tb_wmma_top.vvp | tee /tmp/tb_wmma_top.log
grep -q "PASS tb_wmma_top" /tmp/tb_wmma_top.log
echo "PASS: scripts/check_wmma_top.sh"
