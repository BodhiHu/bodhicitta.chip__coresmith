// Copyright (c) 2026 CDNA5-M1 project.
// SPDX-License-Identifier: MIT
#include "m1_sim.hpp"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <stdexcept>

namespace m1 {

namespace {
constexpr float kFp4Mag[8] = {0.0f, 0.5f, 1.0f, 1.5f, 2.0f, 3.0f, 4.0f, 6.0f};

uint32_t pack_half(uint32_t lo, uint32_t hi) {
  return (lo & 0xffffu) | ((hi & 0xffffu) << 16);
}
uint32_t lo_half(uint32_t w) { return w & 0xffffu; }
uint32_t hi_half(uint32_t w) { return (w >> 16) & 0xffffu; }

void pack_fp4_matrix(const std::vector<float>& src, int rows, int cols,
                     std::vector<uint32_t>& words) {
  const int nibbles = rows * cols;
  words.assign((nibbles + 7) / 8, 0u);
  for (int r = 0; r < rows; ++r) {
    for (int c = 0; c < cols; ++c) {
      const int n = r * cols + c;
      const uint8_t q = float_to_fp4(src[r * cols + c]);
      words[n / 8] |= (uint32_t(q) << (4 * (n % 8)));
    }
  }
}

}  // namespace

int8_t fp4_to_i8(uint8_t nibble) {
  static const int8_t mag[8] = {0, 1, 2, 3, 4, 6, 8, 12};
  const int8_t v = mag[nibble & 7u];
  return (nibble & 8u) ? int8_t(-v) : v;
}

float fp4_to_float(uint8_t nibble) {
  const float v = kFp4Mag[nibble & 7u];
  return (nibble & 8u) ? -v : v;
}

uint8_t float_to_fp4(float v) {
  const bool neg = std::signbit(v);
  const float a = std::fabs(v);
  int best = 0;
  float best_err = 1e30f;
  for (int i = 0; i < 8; ++i) {
    const float err = std::fabs(a - kFp4Mag[i]);
    if (err < best_err) { best_err = err; best = i; }
  }
  return uint8_t(best | (neg ? 8 : 0));
}

uint16_t float_to_f16(float v) {
  uint32_t f;
  std::memcpy(&f, &v, sizeof(f));
  const uint32_t sign = (f >> 16) & 0x8000u;
  int32_t exp = int32_t((f >> 23) & 0xffu) - 127 + 15;
  uint32_t mant = f & 0x7fffffu;
  if (((f >> 23) & 0xffu) == 0xffu) {
    return uint16_t(sign | 0x7c00u | (mant ? 0x200u : 0u));
  }
  if (exp <= 0) {
    if (exp < -10) return uint16_t(sign);
    mant = (mant | 0x800000u) >> (1 - exp);
    return uint16_t(sign | (mant >> 13));
  }
  if (exp >= 31) return uint16_t(sign | 0x7c00u);
  return uint16_t(sign | (uint32_t(exp) << 10) | (mant >> 13));
}

float f16_to_float(uint16_t h) {
  const uint32_t sign = (uint32_t(h & 0x8000u)) << 16;
  uint32_t exp = (h >> 10) & 0x1fu;
  uint32_t mant = h & 0x3ffu;
  uint32_t f;
  if (exp == 0) {
    if (mant == 0) {
      f = sign;
    } else {
      exp = 127 - 15 + 1;
      while ((mant & 0x400u) == 0) { mant <<= 1; --exp; }
      mant &= 0x3ffu;
      f = sign | (exp << 23) | (mant << 13);
    }
  } else if (exp == 31) {
    f = sign | 0x7f800000u | (mant << 13);
  } else {
    f = sign | ((exp + 127 - 15) << 23) | (mant << 13);
  }
  float out;
  std::memcpy(&out, &f, sizeof(out));
  return out;
}

Device::Device() : mem(kMemWords, 0u), lds(kLdsWords, 0u) {}

uint32_t Device::alloc_words(size_t words) {
  if (mem_next + words > kMemWords) throw std::runtime_error("global memory full");
  const uint32_t off = mem_next;
  mem_next += uint32_t(words);
  return off;
}

void Device::write_words(uint32_t off, const std::vector<uint32_t>& words) {
  if (off + words.size() > mem.size()) throw std::runtime_error("global write OOB");
  std::copy(words.begin(), words.end(), mem.begin() + off);
}

std::vector<uint32_t> Device::read_words(uint32_t off, size_t words) const {
  if (off + words > mem.size()) throw std::runtime_error("global read OOB");
  return std::vector<uint32_t>(mem.begin() + off, mem.begin() + off + words);
}

void Device::write_bytes(uint32_t off, const void* src, size_t bytes) {
  if (off * 4 + bytes > mem.size() * 4) throw std::runtime_error("global write OOB");
  std::memcpy(reinterpret_cast<uint8_t*>(mem.data()) + off * 4, src, bytes);
}

void Device::read_bytes(uint32_t off, void* dst, size_t bytes) const {
  if (off * 4 + bytes > mem.size() * 4) throw std::runtime_error("global read OOB");
  std::memcpy(dst, reinterpret_cast<const uint8_t*>(mem.data()) + off * 4, bytes);
}

void Device::write_f16(uint32_t word_off, size_t index, float v) {
  const uint32_t h = float_to_f16(v);
  uint32_t& w = lds[word_off + index / 2];
  if (index & 1u) w = (w & 0xffffu) | (h << 16);
  else w = (w & 0xffff0000u) | h;
}

float Device::read_f16(uint32_t word_off, size_t index) const {
  const uint32_t w = lds[word_off + index / 2];
  return f16_to_float(uint16_t((index & 1u) ? hi_half(w) : lo_half(w)));
}

void Device::write_f32(uint32_t word_off, size_t index, float v) {
  std::memcpy(&lds[word_off + index], &v, sizeof(v));
}
float Device::read_f32(uint32_t word_off, size_t index) const {
  float v;
  std::memcpy(&v, &lds[word_off + index], sizeof(v));
  return v;
}

void Device::lds_clear() { std::fill(lds.begin(), lds.end(), 0u); }

void Device::lds_write_words(uint32_t dst_word, const std::vector<uint32_t>& words) {
  if (dst_word + words.size() > lds.size()) throw std::runtime_error("LDS write OOB");
  std::copy(words.begin(), words.end(), lds.begin() + dst_word);
}

std::vector<uint32_t> Device::lds_read_words(uint32_t src_word, size_t words) const {
  if (src_word + words > lds.size()) throw std::runtime_error("LDS read OOB");
  return std::vector<uint32_t>(lds.begin() + src_word, lds.begin() + src_word + words);
}

void Device::tdm_copy(uint32_t src_word, uint32_t dst_word, uint32_t words) {
  const uint32_t blocks = (words + 31u) / 32u;
  cycles += blocks + 2;
  for (uint32_t i = 0; i < words; ++i) lds[dst_word + i] = mem[src_word + i];
}

void Device::wmma_fp4(uint32_t a_word, uint32_t b_word, uint32_t c_word,
                      bool accumulate) {
  // A: 16 rows x 32 nibbles = 64 words; B: 32 rows x 16 = 64 words;
  // C: 16x16 int32 = 256 words.
  int32_t acc[256];
  if (accumulate) {
    for (int i = 0; i < 256; ++i) acc[i] = int32_t(lds[c_word + i]);
  } else {
    std::fill(acc, acc + 256, 0);
  }
  auto an = [&](int i, int k) {
    const int n = i * 32 + k;
    return fp4_to_i8(uint8_t((lds[a_word + n / 8] >> (4 * (n % 8))) & 0xf));
  };
  auto bn = [&](int k, int j) {
    const int n = k * 16 + j;
    return fp4_to_i8(uint8_t((lds[b_word + n / 8] >> (4 * (n % 8))) & 0xf));
  };
  for (int i = 0; i < 16; ++i)
    for (int j = 0; j < 16; ++j)
      for (int k = 0; k < 32; ++k)
        acc[i * 16 + j] += int32_t(an(i, k)) * int32_t(bn(k, j));
  for (int i = 0; i < 256; ++i) lds[c_word + i] = uint32_t(acc[i]);
  cycles += 16;
  ++wmma_ops;
  macs += 16ull * 16ull * 32ull;
}

void Device::wmma_f16(uint32_t a_word, uint32_t b_word, uint32_t c_word,
                      int M, int N, int K, bool accumulate) {
  std::vector<float> acc(size_t(M) * N);
  if (accumulate) {
    for (int i = 0; i < M; ++i)
      for (int j = 0; j < N; ++j) acc[size_t(i) * N + j] = read_f16(c_word, size_t(i) * N + j);
  }
  for (int i = 0; i < M; ++i) {
    for (int j = 0; j < N; ++j) {
      float s = 0.0f;
      for (int k = 0; k < K; ++k) {
        const float a = read_f16(a_word, size_t(i) * K + k);
        const float b = read_f16(b_word, size_t(k) * N + j);
        s += a * b;
      }
      acc[size_t(i) * N + j] += s;
    }
  }
  for (int i = 0; i < M; ++i)
    for (int j = 0; j < N; ++j) write_f16(c_word, size_t(i) * N + j, acc[size_t(i) * N + j]);
  cycles += uint64_t(M) * N * K / 128ull + 8;
  ++wmma_ops;
  macs += uint64_t(M) * N * K;
}

void Device::sfu_exp2_row(uint32_t word_off, int n) {
  for (int i = 0; i < n; ++i) {
    const float x = read_f16(word_off, i);
    write_f16(word_off, i, std::exp2(x));
    cycles += 1;
  }
  cycles += 8;
}

void Device::sfu_rcp_row(uint32_t word_off, int n) {
  for (int i = 0; i < n; ++i) {
    const float x = read_f16(word_off, i);
    write_f16(word_off, i, 1.0f / x);
    cycles += 1;
  }
  cycles += 8;
}

void Device::softmax_row(uint32_t in_word, uint32_t out_word, int n) {
  std::vector<float> x(n);
  float mx = -1e30f;
  for (int i = 0; i < n; ++i) { x[i] = read_f16(in_word, i); mx = std::max(mx, x[i]); }
  float sum = 0.0f;
  for (int i = 0; i < n; ++i) {
    x[i] = std::exp2((x[i] - mx) * 1.4426950408889634f);
    sum += x[i];
  }
  const float inv = 1.0f / sum;
  for (int i = 0; i < n; ++i) write_f16(out_word, i, x[i] * inv);
  cycles += uint64_t(n) * 3 + 12;  // max + exp + sum + rcp + mul, serialized SFU
}

Device& current_device() {
  static Device dev;
  return dev;
}

// ------------------------------------------------------------------ operators
GemmResult gemm_fp4(int M, int N, int K,
                    const std::vector<float>& A,
                    const std::vector<float>& B) {
  if (M % 16 || N % 16 || K % 32) throw std::runtime_error("gemm_fp4: tile multiple");
  if (A.size() != size_t(M) * K || B.size() != size_t(K) * N)
    throw std::runtime_error("gemm_fp4: shape");
  Device& dev = current_device();
  dev.lds_clear();
  std::vector<int32_t> C(size_t(M) * N, 0);
  const uint32_t a_word = 0, b_word = 64, c_word = 128;
  for (int m0 = 0; m0 < M; m0 += 16) {
    for (int n0 = 0; n0 < N; n0 += 16) {
      bool first = true;
      for (int k0 = 0; k0 < K; k0 += 32) {
        std::vector<float> at(16 * 32), bt(32 * 16);
        for (int i = 0; i < 16; ++i)
          for (int k = 0; k < 32; ++k)
            at[i * 32 + k] = A[size_t(m0 + i) * K + k0 + k];
        for (int k = 0; k < 32; ++k)
          for (int j = 0; j < 16; ++j)
            bt[k * 16 + j] = B[size_t(k0 + k) * N + n0 + j];
        std::vector<uint32_t> aw, bw;
        pack_fp4_matrix(at, 16, 32, aw);
        pack_fp4_matrix(bt, 32, 16, bw);
        dev.lds_write_words(a_word, aw);
        dev.lds_write_words(b_word, bw);
        if (first) { for (int i = 0; i < 256; ++i) dev.lds[c_word + i] = 0; first = false; }
        dev.wmma_fp4(a_word, b_word, c_word, true);
      }
      for (int i = 0; i < 16; ++i)
        for (int j = 0; j < 16; ++j)
          C[size_t(m0 + i) * N + n0 + j] = int32_t(dev.lds[c_word + i * 16 + j]);
    }
  }
  GemmResult r;
  r.C = C;
  r.cycles = dev.cycles;
  r.macs = dev.macs;
  return r;
}

SoftmaxResult softmax_f16(int rows, int cols, const std::vector<float>& X) {
  if (X.size() != size_t(rows) * cols) throw std::runtime_error("softmax: shape");
  Device& dev = current_device();
  dev.lds_clear();
  std::vector<float> Y(size_t(rows) * cols);
  for (int r = 0; r < rows; ++r) {
    for (int c = 0; c < cols; ++c) dev.write_f16(0, c, X[size_t(r) * cols + c]);
    dev.softmax_row(0, 128, cols);
    for (int c = 0; c < cols; ++c) Y[size_t(r) * cols + c] = dev.read_f16(128, c);
  }
  double max_err = 0.0;
  for (int r = 0; r < rows; ++r) {
    float mx = -1e30f;
    for (int c = 0; c < cols; ++c) mx = std::max(mx, X[size_t(r) * cols + c]);
    double sum = 0.0;
    for (int c = 0; c < cols; ++c) sum += std::exp2((X[size_t(r) * cols + c] - mx) * 1.4426950408889634);
    for (int c = 0; c < cols; ++c) {
      const double ref = std::exp2((X[size_t(r) * cols + c] - mx) * 1.4426950408889634) / sum;
      max_err = std::max(max_err, std::fabs(ref - Y[size_t(r) * cols + c]));
    }
  }
  SoftmaxResult r;
  r.Y = Y;
  r.cycles = dev.cycles;
  r.max_abs_err = max_err;
  return r;
}

AttentionResult flash_attention_f16(int seq, int dim,
                                    const std::vector<float>& Q,
                                    const std::vector<float>& K,
                                    const std::vector<float>& V,
                                    bool causal) {
  if (seq % 16 || dim % 16 || seq > 32) throw std::runtime_error("attention: seq%16, dim%16, seq<=32");
  if (Q.size() != size_t(seq) * dim || K.size() != size_t(seq) * dim ||
      V.size() != size_t(seq) * dim) throw std::runtime_error("attention: shape");
  Device& dev = current_device();
  dev.lds_clear();
  // LDS layout: Q(16xd) | K^T(d x seq) | V(seq x d) | S(16x seq) | O(16xd)
  const uint32_t q_word = 0;
  const uint32_t kt_word = uint32_t(16 * dim / 2);
  const uint32_t v_word = kt_word + uint32_t(dim * seq / 2);
  const uint32_t s_word = v_word + uint32_t(seq * dim / 2);
  const uint32_t o_word = s_word + uint32_t(16 * seq / 2);
  if (o_word + uint32_t(16 * dim / 2) > uint32_t(kLdsWords))
    throw std::runtime_error("attention: LDS budget");

  const float scale = 1.0f / std::sqrt(float(dim));
  std::vector<float> O(size_t(seq) * dim, 0.0f);
  for (int qb = 0; qb < seq; qb += 16) {
    for (int i = 0; i < 16; ++i)
      for (int d = 0; d < dim; ++d) dev.write_f16(q_word, size_t(i) * dim + d, Q[size_t(qb + i) * dim + d]);
    for (int k = 0; k < dim; ++k)
      for (int j = 0; j < seq; ++j) dev.write_f16(kt_word, size_t(k) * seq + j, K[size_t(j) * dim + k]);
    for (int j = 0; j < seq; ++j)
      for (int d = 0; d < dim; ++d) dev.write_f16(v_word, size_t(j) * dim + d, V[size_t(j) * dim + d]);

    dev.wmma_f16(q_word, kt_word, s_word, 16, seq, dim);
    // scale + causal mask + softmax
    for (int i = 0; i < 16; ++i) {
      for (int j = 0; j < seq; ++j) {
        float v = dev.read_f16(s_word, size_t(i) * seq + j) * scale;
        if (causal && j > qb + i) v = -1e4f;
        dev.write_f16(s_word, size_t(i) * seq + j, v);
      }
      dev.softmax_row(s_word + uint32_t(i * seq / 2), s_word + uint32_t(i * seq / 2), seq);
    }
    dev.wmma_f16(s_word, v_word, o_word, 16, dim, seq);
    for (int i = 0; i < 16; ++i)
      for (int d = 0; d < dim; ++d) O[size_t(qb + i) * dim + d] = dev.read_f16(o_word, size_t(i) * dim + d);
  }
  // CPU float reference
  double max_err = 0.0;
  for (int qi = 0; qi < seq; ++qi) {
    std::vector<float> s(seq), p(seq);
    float mx = -1e30f;
    for (int j = 0; j < seq; ++j) {
      if (causal && j > qi) { s[j] = -1e30f; continue; }
      float v = 0.0f;
      for (int d = 0; d < dim; ++d) v += Q[size_t(qi) * dim + d] * K[size_t(j) * dim + d];
      s[j] = v * scale;
      mx = std::max(mx, s[j]);
    }
    float sum = 0.0f;
    for (int j = 0; j < seq; ++j) {
      p[j] = (causal && j > qi) ? 0.0f : std::exp2((s[j] - mx) * 1.4426950408889634f);
      sum += p[j];
    }
    for (int d = 0; d < dim; ++d) {
      float v = 0.0f;
      for (int j = 0; j < seq; ++j) v += (p[j] / sum) * V[size_t(j) * dim + d];
      max_err = std::max(max_err, std::fabs(double(v) - O[size_t(qi) * dim + d]));
    }
  }
  AttentionResult r;
  r.O = O;
  r.cycles = dev.cycles;
  r.max_abs_err = max_err;
  return r;
}

}  // namespace m1
