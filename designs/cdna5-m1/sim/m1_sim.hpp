// Copyright (c) 2026 CDNA5-M1 project.
// SPDX-License-Identifier: MIT
//
// m1_sim.hpp -- functional/cycle model of the CDNA5-M1 AI accelerator.
//
// The model mirrors the RTL microarchitecture: 4 KB LDS (32 banks x 32 rows),
// a 16x16x32 MXFP4 WMMA core (512 MAC/cycle), a 1-D TDM, a serialized SFU,
// and the same FP4 E2M1 decode.  It is used by the operator/ROCm bring-up to
// run GEMM, Softmax and FlashAttention at sizes that are too slow for an
// iverilog full-chip run, while keeping the same data layout and cycle costs.
#ifndef M1_SIM_HPP
#define M1_SIM_HPP

#include <cstdint>
#include <cstddef>
#include <vector>
#include <string>

namespace m1 {

constexpr int kLdsWords = 1024;   // 4 KB
constexpr int kMemWords = 1 << 20; // 4 MB global
constexpr int kWave = 32;
constexpr int kSimd = 2;

// E2M1 decode, scaled by 2 exactly as the RTL: {0,1,2,3,4,6,8,12}.
int8_t fp4_to_i8(uint8_t nibble);
// Nearest E2M1 encoding of a float (sign + magnitude).
uint8_t float_to_fp4(float v);
float fp4_to_float(uint8_t nibble);

// IEEE binary16 helpers.
uint16_t float_to_f16(float v);
float f16_to_float(uint16_t v);

struct Device {
  std::vector<uint32_t> mem;
  std::vector<uint32_t> lds;
  uint64_t cycles = 0;
  uint64_t wmma_ops = 0;
  uint64_t macs = 0;
  uint32_t mem_next = 0;

  Device();

  // Global memory allocation, word-granular (returns a word offset).
  uint32_t alloc_words(size_t words);
  void write_words(uint32_t off, const std::vector<uint32_t>& words);
  std::vector<uint32_t> read_words(uint32_t off, size_t words) const;
  void write_bytes(uint32_t off, const void* src, size_t bytes);
  void read_bytes(uint32_t off, void* dst, size_t bytes) const;
  void write_f16(uint32_t word_off, size_t index, float v);
  float read_f16(uint32_t word_off, size_t index) const;
  void write_f32(uint32_t word_off, size_t index, float v);
  float read_f32(uint32_t word_off, size_t index) const;

  // LDS
  void lds_clear();
  void lds_write_words(uint32_t dst_word, const std::vector<uint32_t>& words);
  std::vector<uint32_t> lds_read_words(uint32_t src_word, size_t words) const;

  // TDM: 1-D contiguous global -> LDS, 128-byte blocks.
  void tdm_copy(uint32_t src_word, uint32_t dst_word, uint32_t words);

  // WMMA 16x16x32 MXFP4 -> int32; A/B/C are LDS word addresses.
  // C = A*B (or C += A*B when accumulate).  Costs 16 cycles.
  void wmma_fp4(uint32_t a_word, uint32_t b_word, uint32_t c_word,
                bool accumulate = false);

  // Reconfigurable FP16 matrix tile (M,N multiples of 16, K multiple of 16).
  // The production RTL implements MXFP4; this model is the FP16/BF16 datapath
  // used by Softmax/FlashAttention bring-up.  Costs M*N*K/128 + 8 cycles.
  void wmma_f16(uint32_t a_word, uint32_t b_word, uint32_t c_word,
                int M, int N, int K, bool accumulate = false);

  // Serialized SFU operations over FP16 rows in LDS (one 16-bit lane/cycle).
  void sfu_exp2_row(uint32_t word_off, int n);
  void sfu_rcp_row(uint32_t word_off, int n);

  // Row-wise stable softmax over an FP16 row in LDS.
  void softmax_row(uint32_t in_word, uint32_t out_word, int n);
};

Device& current_device();

// ------------------------------------------------------------------ operators
//
// All matrices are row-major.  FP4 inputs are quantized to E2M1; FP4 GEMM
// accumulates exactly in int32 (matching the RTL matrix core).  FP16 GEMM /
// Softmax / FlashAttention use the model's FP16 datapath.
struct GemmResult {
  std::vector<int32_t> C;   // FP4 exact integer result
  uint64_t cycles;
  uint64_t macs;
};

GemmResult gemm_fp4(int M, int N, int K,
                    const std::vector<float>& A,
                    const std::vector<float>& B);

struct SoftmaxResult {
  std::vector<float> Y;
  uint64_t cycles;
  double max_abs_err;
};

SoftmaxResult softmax_f16(int rows, int cols, const std::vector<float>& X);

struct AttentionResult {
  std::vector<float> O;  // seq x dim
  uint64_t cycles;
  double max_abs_err;
};

// Single-head self-attention with FP16 Q/K/V, seq and dim multiples of 16,
// seq <= 32 (one 16x32 score tile per query block).  Causal mask optional.
AttentionResult flash_attention_f16(int seq, int dim,
                                    const std::vector<float>& Q,
                                    const std::vector<float>& K,
                                    const std::vector<float>& V,
                                    bool causal = false);

}  // namespace m1

#endif  // M1_SIM_HPP
