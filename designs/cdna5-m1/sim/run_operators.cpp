// Copyright (c) 2026 CDNA5-M1 project.
// SPDX-License-Identifier: MIT
//
// run_operators.cpp -- run GEMM, Softmax and FlashAttention on the M1
// functional/cycle model and check them against CPU references.
#include "m1_sim.hpp"

#include <cmath>
#include <cstdio>
#include <random>
#include <algorithm>
#include <vector>

namespace {

int g_fail = 0;

void check(bool ok, const char* what, double err, double tol) {
  std::printf("  %-34s %s (err=%.3e, tol=%.1e)\n", what, ok ? "PASS" : "FAIL", err, tol);
  if (!ok) ++g_fail;
}

std::vector<float> fp4_values(std::mt19937& rng, size_t n) {
  static const float mags[8] = {0.f, 0.5f, 1.f, 1.5f, 2.f, 3.f, 4.f, 6.f};
  std::uniform_int_distribution<int> pick(0, 15);
  std::vector<float> v(n);
  for (size_t i = 0; i < n; ++i) {
    const int code = pick(rng);
    v[i] = (code & 8) ? -mags[code & 7] : mags[code & 7];
  }
  return v;
}

void test_gemm() {
  std::printf("GEMM 64x64x64 MXFP4 (exact int32)\n");
  const int M = 64, N = 64, K = 64;
  std::mt19937 rng(1234);
  const auto A = fp4_values(rng, size_t(M) * K);
  const auto B = fp4_values(rng, size_t(K) * N);
  const uint64_t c0 = m1::current_device().cycles;
  auto r = m1::gemm_fp4(M, N, K, A, B);
  const uint64_t cycles = m1::current_device().cycles - c0;
  bool ok = true;
  int max_err = 0;
  for (int i = 0; i < M; ++i) {
    for (int j = 0; j < N; ++j) {
      int32_t ref = 0;
      for (int k = 0; k < K; ++k) {
        ref += int32_t(m1::fp4_to_i8(m1::float_to_fp4(A[i * K + k]))) *
               int32_t(m1::fp4_to_i8(m1::float_to_fp4(B[k * N + j])));
      }
      max_err = std::max(max_err, std::abs(ref - r.C[i * N + j]));
      if (ref != r.C[i * N + j]) ok = false;
    }
  }
  check(ok, "C == CPU exact FP4 reference", max_err, 0);
  const double gflops = 2.0 * M * N * K / double(cycles) * 100e6 / 1e9;
  std::printf("  cycles=%llu  model_effective=%.2f GFLOP/s @100MHz\n",
              (unsigned long long)cycles, gflops);
}

void test_softmax() {
  std::printf("Softmax 8 rows x 128 cols (FP16)\n");
  std::mt19937 rng(99);
  std::normal_distribution<float> dist(0.f, 4.f);
  std::vector<float> x(8 * 128);
  for (auto& v : x) v = dist(rng);
  const uint64_t c0 = m1::current_device().cycles;
  auto r = m1::softmax_f16(8, 128, x);
  const uint64_t cycles = m1::current_device().cycles - c0;
  check(r.max_abs_err < 2e-3, "row sums = 1 / reference", r.max_abs_err, 2e-3);
  for (int row = 0; row < 8; ++row) {
    double s = 0.0;
    for (int c = 0; c < 128; ++c) s += r.Y[row * 128 + c];
    if (std::fabs(s - 1.0) > 3e-3) { ++g_fail; std::printf("  row sum FAIL %.4f\n", s); }
  }
  std::printf("  cycles=%llu\n", (unsigned long long)cycles);
}

void test_attention() {
  std::printf("FlashAttention seq=32 dim=16 causal (FP16)\n");
  const int seq = 32, dim = 16;
  std::mt19937 rng(7);
  std::normal_distribution<float> dist(0.f, 0.5f);
  std::vector<float> q(seq * dim), k(seq * dim), v(seq * dim);
  for (auto& x : q) x = dist(rng);
  for (auto& x : k) x = dist(rng);
  for (auto& x : v) x = dist(rng);
  const uint64_t c0 = m1::current_device().cycles;
  auto r = m1::flash_attention_f16(seq, dim, q, k, v, true);
  const uint64_t cycles = m1::current_device().cycles - c0;
  check(r.max_abs_err < 2e-2, "O == CPU float reference", r.max_abs_err, 2e-2);
  std::printf("  cycles=%llu\n", (unsigned long long)cycles);
}

}  // namespace

int main() {
  std::printf("CDNA5-M1 operator bring-up on the functional/cycle model\n");
  test_gemm();
  test_softmax();
  test_attention();
  if (g_fail) {
    std::printf("OPERATORS FAILED (%d checks)\n", g_fail);
    return 1;
  }
  std::printf("OPERATORS PASSED\n");
  return 0;
}
