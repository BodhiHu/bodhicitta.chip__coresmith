#!/usr/bin/env bash
# Copyright (c) 2026 CDNA5-M1 project.
# SPDX-License-Identifier: MIT
#
# Build and run the AI operator model + ROCm/HIP/HSA examples.
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
cd "$HERE"
cmake -S sim -B sim/build >/tmp/m1sim_cmake.log 2>&1
cmake --build sim/build -j4 >/tmp/m1sim_build.log 2>&1
cmake -S rocm -B rocm/build >/tmp/m1rocm_cmake.log 2>&1
cmake --build rocm/build -j4 >/tmp/m1rocm_build.log 2>&1
./sim/build/run_operators
for x in hip_saxpy hip_gemm hip_softmax hip_flash_attention hsa_demo; do
  "./rocm/build/$x"
done
