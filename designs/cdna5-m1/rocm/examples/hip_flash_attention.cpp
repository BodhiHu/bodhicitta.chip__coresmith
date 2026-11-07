// Copyright (c) 2026 CDNA5-M1 project.
// SPDX-License-Identifier: MIT
//
// HIP host API + M1 device kernel: causal FlashAttention seq=32, dim=16.
#include <hip/hip_runtime.h>
#include "m1_sim.hpp"

#include <cmath>
#include <cstdio>
#include <random>
#include <vector>

__global__ void attention_kernel(const float* Q, const float* K, const float* V,
                                 float* O, int seq, int dim) {
  std::vector<float> q(Q, Q + size_t(seq) * dim);
  std::vector<float> k(K, K + size_t(seq) * dim);
  std::vector<float> v(V, V + size_t(seq) * dim);
  auto r = m1::flash_attention_f16(seq, dim, q, k, v, true);
  for (size_t i = 0; i < r.O.size(); ++i) O[i] = r.O[i];
}

int main() {
  const int seq = 32, dim = 16;
  std::mt19937 rng(5);
  std::normal_distribution<float> dist(0.f, 0.5f);
  std::vector<float> Q(size_t(seq) * dim), K(size_t(seq) * dim), V(size_t(seq) * dim);
  for (auto& x : Q) x = dist(rng);
  for (auto& x : K) x = dist(rng);
  for (auto& x : V) x = dist(rng);
  float *dQ = nullptr, *dK = nullptr, *dV = nullptr, *dO = nullptr;
  const size_t bytes = Q.size() * sizeof(float);
  hipMalloc(reinterpret_cast<void**>(&dQ), bytes);
  hipMalloc(reinterpret_cast<void**>(&dK), bytes);
  hipMalloc(reinterpret_cast<void**>(&dV), bytes);
  hipMalloc(reinterpret_cast<void**>(&dO), bytes);
  hipMemcpy(dQ, Q.data(), bytes, hipMemcpyHostToDevice);
  hipMemcpy(dK, K.data(), bytes, hipMemcpyHostToDevice);
  hipMemcpy(dV, V.data(), bytes, hipMemcpyHostToDevice);
  hipLaunchKernelGGL(attention_kernel, dim3(1), dim3(1), 0, 0, dQ, dK, dV, dO, seq, dim);
  std::vector<float> O(Q.size());
  hipMemcpy(O.data(), dO, bytes, hipMemcpyDeviceToHost);
  auto ref = m1::flash_attention_f16(seq, dim, Q, K, V, true);
  double max_err = 0.0;
  for (size_t i = 0; i < O.size(); ++i) max_err = std::max(max_err, std::fabs(double(O[i] - ref.O[i])));
  hipFree(dQ); hipFree(dK); hipFree(dV); hipFree(dO);
  std::printf("%s hip_flash_attention_m1 (seq=32 dim=16, err=%.3e)\n",
              max_err < 1e-3 ? "PASS" : "FAIL", max_err);
  return max_err < 1e-3 ? 0 : 1;
}
