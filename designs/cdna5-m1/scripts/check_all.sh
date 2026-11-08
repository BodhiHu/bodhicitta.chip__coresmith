#!/usr/bin/env bash
# Copyright (c) 2026 CDNA5-M1 project.
# SPDX-License-Identifier: MIT
#
# One-command reproduction of the current RTL/operator evidence.
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
cd "$HERE"
./scripts/check_sfu.sh
./scripts/check_softmax.sh
./scripts/check_wgp_softmax.sh
./scripts/check_top_softmax.sh
./scripts/check_wmma_top.sh
./scripts/run_operators.sh
echo "ALL CHECKS PASSED"
