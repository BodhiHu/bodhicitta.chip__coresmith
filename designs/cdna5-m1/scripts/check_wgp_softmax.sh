#!/usr/bin/env bash
# Copyright (c) 2026 CDNA5-M1 project.
# SPDX-License-Identifier: MIT
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
IV=/opt/eda/oss-cad-suite/bin/iverilog
VVP=/opt/eda/oss-cad-suite/bin/vvp
cd "$HERE"
"$IV" -g2005-sv -Irtl -o /tmp/tb_wgp_softmax.vvp \
  rtl/wgp.v rtl/simd32.v rtl/lds.v rtl/wmma.v rtl/tdm.v \
  rtl/sfu.v rtl/softmax_engine.v tb/tb_wgp_softmax.v
"$VVP" /tmp/tb_wgp_softmax.vvp | tee /tmp/tb_wgp_softmax.log
grep -q "PASS: wgp softmax path" /tmp/tb_wgp_softmax.log
echo "PASS: scripts/check_wgp_softmax.sh"
