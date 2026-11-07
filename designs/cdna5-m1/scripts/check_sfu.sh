#!/usr/bin/env bash
# Copyright (c) 2026 CDNA5-M1 project.
# SPDX-License-Identifier: MIT
#
# check_sfu.sh -- compile and run the self-checking SFU unit test.
#
#   scripts/check_sfu.sh
#
# Uses the OSS-CAD-Suite iverilog/vvp pinned by the CDNA5-M1 flow.  The
# testbench sweeps every exp2 and rcp input code, checks the numerical error
# limits, the start/busy valid-ready handshake, the one-cycle done pulse,
# the 4..8 cycle latency and synchronous reset, then prints PASS or FAIL.
set -euo pipefail

HERE=$(cd "$(dirname "$0")/.." && pwd)
cd "$HERE"

IVERILOG=${IVERILOG:-/opt/eda/oss-cad-suite/bin/iverilog}
VVP=${VVP:-/opt/eda/oss-cad-suite/bin/vvp}

if [ ! -x "$IVERILOG" ]; then
  echo "check_sfu: iverilog not found at $IVERILOG" >&2
  exit 1
fi
if [ ! -x "$VVP" ]; then
  echo "check_sfu: vvp not found at $VVP" >&2
  exit 1
fi

BUILD=${BUILD_DIR:-${TMPDIR:-/tmp}/cdna5_m1_sfu.$$}
mkdir -p "$BUILD"
trap 'rm -rf "$BUILD"' EXIT

VVP_FILE="$BUILD/tb_sfu.vvp"
LOG="$BUILD/tb_sfu.log"

echo "=== sfu unit simulation (Verilog-2005, iverilog) ==="
"$IVERILOG" -g2005 -Wall -Irtl -o "$VVP_FILE" rtl/sfu.v tb/tb_sfu.v

set +e
"$VVP" "$VVP_FILE" 2>&1 | tee "$LOG"
VVP_RC=${PIPESTATUS[0]}
set -e

echo "=== sfu check summary ==="
if [ "$VVP_RC" -ne 0 ]; then
  echo "FAIL: vvp exited with status $VVP_RC" >&2
  exit "$VVP_RC"
fi
if ! grep -qx "PASS" "$LOG"; then
  echo "FAIL: testbench did not print PASS" >&2
  exit 1
fi
grep -E "max (abs|rel) error|latency" "$LOG" || true
echo "PASS: scripts/check_sfu.sh"
