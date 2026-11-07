// Copyright (c) 2026 CDNA5-M1 project.
// SPDX-License-Identifier: MIT
//
// Standard HIP source: saxpy.  Compiled by g++ against the M1 HIP shim and
// executed serially on the host (source/API compatibility, not ROCm binary).
#include <hip/hip_runtime.h>

#include <cstdio>
#include <vector>

__global__ void saxpy(float* y, const float* x, float a, int n) {
  for (int i = 0; i < n; ++i) y[i] = a * x[i] + y[i];
}

int main() {
  const int n = 1024;
  std::vector<float> hx(n, 2.0f), hy(n, 1.0f);
  float *dx = nullptr, *dy = nullptr;
  if (hipMalloc(reinterpret_cast<void**>(&dx), n * sizeof(float)) != hipSuccess) return 1;
  if (hipMalloc(reinterpret_cast<void**>(&dy), n * sizeof(float)) != hipSuccess) return 1;
  hipMemcpy(dx, hx.data(), n * sizeof(float), hipMemcpyHostToDevice);
  hipMemcpy(dy, hy.data(), n * sizeof(float), hipMemcpyHostToDevice);
  hipLaunchKernelGGL(saxpy, dim3(1), dim3(1), 0, 0, dy, dx, 3.0f, n);
  hipMemcpy(hy.data(), dy, n * sizeof(float), hipMemcpyDeviceToHost);
  hipFree(dx);
  hipFree(dy);
  int errs = 0;
  for (int i = 0; i < n; ++i) if (hy[i] != 7.0f) ++errs;
  std::printf("%s hip_saxpy (n=%d, %d errors)\n", errs ? "FAIL" : "PASS", n, errs);
  return errs ? 1 : 0;
}
