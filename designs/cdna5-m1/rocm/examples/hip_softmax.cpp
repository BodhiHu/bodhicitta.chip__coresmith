// Copyright (c) 2026 CDNA5-M1 project.
// SPDX-License-Identifier: MIT
//
// HIP host API + M1 device kernel: row-wise Softmax (8 x 128, FP16 model).
#include <hip/hip_runtime.h>
#include "m1_sim.hpp"

#include <cmath>
#include <cstdio>
#include <random>
#include <vector>

__global__ void softmax_kernel(const float* X, float* Y, int rows, int cols) {
  std::vector<float> x(X, X + size_t(rows) * cols);
  auto r = m1::softmax_f16(rows, cols, x);
  for (size_t i = 0; i < r.Y.size(); ++i) Y[i] = r.Y[i];
}

int main() {
  const int rows = 8, cols = 128;
  std::mt19937 rng(42);
  std::normal_distribution<float> dist(0.f, 3.f);
  std::vector<float> X(size_t(rows) * cols);
  for (auto& v : X) v = dist(rng);
  float *dX = nullptr, *dY = nullptr;
  hipMalloc(reinterpret_cast<void**>(&dX), X.size() * sizeof(float));
  hipMalloc(reinterpret_cast<void**>(&dY), X.size() * sizeof(float));
  hipMemcpy(dX, X.data(), X.size() * sizeof(float), hipMemcpyHostToDevice);
  hipLaunchKernelGGL(softmax_kernel, dim3(1), dim3(1), 0, 0, dX, dY, rows, cols);
  std::vector<float> Y(X.size());
  hipMemcpy(Y.data(), dY, Y.size() * sizeof(float), hipMemcpyDeviceToHost);
  double max_err = 0.0;
  for (int r = 0; r < rows; ++r) {
    double sum = 0.0;
    for (int c = 0; c < cols; ++c) sum += Y[r * cols + c];
    max_err = std::max(max_err, std::fabs(sum - 1.0));
  }
  hipFree(dX); hipFree(dY);
  std::printf("%s hip_softmax_m1 (8x128, row-sum err=%.3e)\n",
              max_err < 3e-3 ? "PASS" : "FAIL", max_err);
  return max_err < 3e-3 ? 0 : 1;
}
