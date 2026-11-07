#!/usr/bin/env bash
# Copyright (c) 2026 CDNA5-M1 project.
# SPDX-License-Identifier: MIT
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
IV=/opt/eda/oss-cad-suite/bin/iverilog
VVP=/opt/eda/oss-cad-suite/bin/vvp
cd "$HERE"
"$IV" -g2005-sv -o /tmp/tb_softmax_engine.vvp \
  rtl/sfu.v rtl/softmax_engine.v tb/tb_softmax_engine.v
"$VVP" /tmp/tb_softmax_engine.vvp | tee /tmp/tb_softmax_engine.log
grep -q "PASS: softmax_engine" /tmp/tb_softmax_engine.log
echo "PASS: scripts/check_softmax.sh"
