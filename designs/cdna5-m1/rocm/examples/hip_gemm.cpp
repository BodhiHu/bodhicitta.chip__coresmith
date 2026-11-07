// Copyright (c) 2026 CDNA5-M1 project.
// SPDX-License-Identifier: MIT
//
// HIP host API + M1 device kernel: GEMM 64x64x64 MXFP4 through the M1 model.
#include <hip/hip_runtime.h>
#include "m1_sim.hpp"

#include <cstdio>
#include <vector>

__global__ void gemm_kernel(const float* A, const float* B, int32_t* C,
                            int M, int N, int K) {
  std::vector<float> a(A, A + size_t(M) * K);
  std::vector<float> b(B, B + size_t(K) * N);
  auto r = m1::gemm_fp4(M, N, K, a, b);
  for (size_t i = 0; i < r.C.size(); ++i) C[i] = r.C[i];
}

int main() {
  const int M = 64, N = 64, K = 64;
  static const float mags[8] = {0.f, 0.5f, 1.f, 1.5f, 2.f, 3.f, 4.f, 6.f};
  std::vector<float> A(size_t(M) * K), B(size_t(K) * N);
  for (size_t i = 0; i < A.size(); ++i) A[i] = mags[i % 8] * ((i % 3) ? 1 : -1);
  for (size_t i = 0; i < B.size(); ++i) B[i] = mags[(i * 3) % 8];
  float *dA = nullptr, *dB = nullptr;
  int32_t* dC = nullptr;
  hipMalloc(reinterpret_cast<void**>(&dA), A.size() * sizeof(float));
  hipMalloc(reinterpret_cast<void**>(&dB), B.size() * sizeof(float));
  hipMalloc(reinterpret_cast<void**>(&dC), size_t(M) * N * sizeof(int32_t));
  hipMemcpy(dA, A.data(), A.size() * sizeof(float), hipMemcpyHostToDevice);
  hipMemcpy(dB, B.data(), B.size() * sizeof(float), hipMemcpyHostToDevice);
  hipLaunchKernelGGL(gemm_kernel, dim3(1), dim3(1), 0, 0, dA, dB, dC, M, N, K);
  std::vector<int32_t> C(size_t(M) * N);
  hipMemcpy(C.data(), dC, C.size() * sizeof(int32_t), hipMemcpyDeviceToHost);
  int32_t max_err = 0;
  for (int i = 0; i < M; ++i)
    for (int j = 0; j < N; ++j) {
      int32_t ref = 0;
      for (int k = 0; k < K; ++k)
        ref += m1::fp4_to_i8(m1::float_to_fp4(A[i * K + k])) *
               m1::fp4_to_i8(m1::float_to_fp4(B[k * N + j]));
      max_err = std::max(max_err, std::abs(ref - C[i * N + j]));
    }
  hipFree(dA); hipFree(dB); hipFree(dC);
  std::printf("%s hip_gemm_m1 (64x64x64 FP4, max_err=%d)\n",
              max_err == 0 ? "PASS" : "FAIL", max_err);
  return max_err == 0 ? 0 : 1;
}
