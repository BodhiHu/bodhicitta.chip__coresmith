#!/usr/bin/env bash
# Copyright (c) 2026 CDNA5-M1 project.
# SPDX-License-Identifier: MIT
#
# regress.sh -- run the three self-checking bring-up tests.
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
cd "$HERE"
export PATH=/opt/eda/oss-cad-suite/bin:${PATH}

fail=0
run() {
  local name=$1; shift
  echo "=== $name ==="
  if iverilog -g2005-sv -Irtl -o "/tmp/${name}.vvp" "$@" && vvp "/tmp/${name}.vvp"; then
    :
  else
    fail=1
  fi
}

run tb_wmma rtl/lds.v rtl/wmma.v tb/tb_wmma.v
run tb_top  rtl/*.v tb/tb_top.v
run tb_wmma_top rtl/*.v tb/tb_wmma_top.v

if [ "$fail" -ne 0 ]; then
  echo "REGRESSION FAILED"
  exit 1
fi
echo "REGRESSION PASSED"
