# CDNA5-M1 — operator contracts and reference plan

| Field | Value |
|---|---|
| Document | Operator contracts, revision 1.1 (2026-11-07) |
| Covers | GEMM (MXFP4 exact int32; FP16/BF16), Softmax (stable, row-wise), FlashAttention |
| Applies to | `sim/` (C++ functional/cycle model), `rocm/examples/`, `rtl/` |
| Related | `spec/ISA.md`, `spec/UARCH.md`, `spec/SAD.md`, `spec/AI_SCOPE.md`, `spec/ROCM_COMPAT.md` |
| Status | **IMPL** = runs and is checked (name the target); **MODEL** = implemented in `sim/` only; **SPEC** = frozen contract, implementation pending; **TARGET** = needs a datapath that does not exist |

**Measurement policy.** Figures marked *(measured)* are from an executed run,
naming the target: `tb_wmma`/`tb_wmma_top` (RTL simulation, in
`doc/PERFORMANCE.md` and `spec/FRD.md`) or `sim/run_operators` and
`rocm/build/hip_*` (C++ model, 2026-11-07). **Model cycles are not silicon and
not RTL**; they come from the same cost model but a different implementation.
Everything else is analytic, labelled "≈", with its assumption stated.

## 1. Conventions and cost primitives

Wave32 (32 lanes), 2 SIMD32 per CU, one wave per SIMD, one PC per wave. Issue
is **1 instruction per 4 cycles per SIMD** (`doc/PERFORMANCE.md` §2.6) — this,
not arithmetic, dominates softmax-style operators. LDS: 32 banks x 32 rows x
32 b, one 32-word (128 B) grant per cycle, 2 lane ports + 1 linear port, lane
conflicts aborting the wave. Global: AXI4 128-bit, INCR8, one outstanding.
Kernarg: flat 4 B-field blob at `ARG_PTR`; `s0=wg_id`, `s1=arg_ptr`,
`s2=lds_base=0`, `s3=wg_size`, `s4=lane_base=0`.

| Primitive | Cost (cycles) | Basis |
|---|---|---|
| SIMD instruction issue; LDS 32-word grant | 4 / 1 | Structural RTL FSM; `rtl/lds.v` |
| AXI4 128 B block = 1 AR/AW + 8 beats + ~2 cooldown; TDM chunk = 1 block + 1 LDS row | ≈11 | Assumption, consistent with the 1.1–1.2 GB/s sustained estimate in FRD PERF-005 |
| WMMA 16x16x32: unit test 11+16+9+1 = **37** (measured); spec cadence 7+16+8+1 = 32; compute window 16 | 37 / 32 / 16 | `tb_wmma`; `spec/UARCH.md`; FRD PERF-004; `spec/ISA.md` 0x15 |
| SFU op: 16-bit serialized `exp2`/`rcp`, 4-cycle latency, 1 command / 5 cycles | 4 / 5 | `rtl/sfu.v`, `tb_sfu` (measured) |
| Model FP16 tile `M*N*K` (multiple of 16): `M*N*K/128 + 8` | formula | `sim/m1_sim.hpp` `wmma_f16` (model, not RTL) |

Derived peaks at 100 MHz: 16 cycles → **102.4 GFLOP/s**; 32 → 51.2; 37 → 44.3.

## 2. GEMM — MXFP4 operands, exact int32 accumulation

### 2.1 Contract

```
C[i][j] = sum_{k=0..31} dec(A[i][k]) * dec(B[k][j])          (exact int32)
dec(x)  : E2M1 -> {0,1,2,3,4,6,8,12} with sign               (x2 of nominal)
y[i][j] = (C[i][j] / 4) * 2^(eA + eB - 254)                  (software epilogue)
```

* `A` is `16 x 32`, `B` is `32 x 16`, `C` is `16 x 16`; one `S_WMMA` per tile
  computing `C = A*B` — the core does **not** accumulate (`spec/SAD.md` §14).
  Operands are packed nibbles, two FP4 per byte, low nibble first, 32-word
  aligned: 1,024 elements in 128 words, which is what makes 16 cycles possible.
* The x2 decode makes every product exact, so the hardware result is **4x** the
  nominal FP4 product (x2 from A, x2 from B); the consumer divides by 4 and
  applies block scales, so no rounding occurs anywhere on chip. `K = 32` is
  exactly one MX block, so a tile spans one `eA` and one `eB`: one
  `2^(eA+eB-254)` multiply per output, not a per-element scale table — the
  reason 32-deep K tiling is the contract.

### 2.2 Tile shape and LDS budget

| LDS region | Words | Bytes | Content |
|---|---|---|---|
| `0x000` A, `0x100` B | 128 | 512 | `A[16][32]` and `B[32][16]` packed FP4, 32-word aligned |
| `0x200` C | 256 | 1024 | `C[16][16]` int32 |
| `0x600`–`0xFFF` A'/B' + scratch | 640 | 2560 | second stage (double buffer), second C tile, spills |
| **used** | **384** | **1536** | 1.5 KB of 4 KB (2 KB with a second A/B stage) |

A 16x16 C tile costs 1 KB and A/B 256 B each, so double-buffered A/B plus one C
fits in 2 KB; a 32x32 C tile (4 KB alone) does **not** fit, so 16x16 is the tile.

### 2.3 Reference plan

1. Host stages packed `A` and `B` in global memory (128 B aligned) and writes
   the kernarg blob: M, N, K, pointers, `eA`/`eB`.
2. `S_TDM_COPY` A and B (2 chunks each, 32-word aligned), then `S_WMMA` with
   the A/B/C word bases.
3. Epilogue in SIMD: `V_LDS_LD` the 256 C words (8 x 32), divide by 4, multiply
   by `2^(eA+eB-254)`; across K blocks software adds partials (exact int32) in
   LDS/VGPR (the core does not accumulate) and `V_MEM_ST`s eight 128 B blocks.

### 2.4 Cycle estimates

| Case | Cadence (cycles) | GFLOP/s | Basis |
|---|---|---|---|
| Compute window only / LDS-resident at spec cadence | 16 / 32 | 102.4 / 51.2 | Peak spec; UARCH, FRD PERF-004 |
| Back-to-back, measured `tb_wmma` block | **37** (measured, RTL) | 44.3 | RTL simulation |
| 64x64x64 on the C++ model | **512** (measured, model) | 102.40 effective | `sim/run_operators`, exact (`max_err=0`) |
| K-streamed: TDM (44) + WMMA (37), mutually exclusive / with C writeback (+120) | ≈81 / ≈201 | ≈20.2 / ≈8.2 | Analytic; FR-024 serialises WMMA and TDM |
| Full chip, one tile, START→IRQ (launch + I$ preload included) | **996** (measured, RTL) | ≈1.6 | `tb_wmma_top`, FRD PERF-008 |

The 64x64x64 model run moves 16 KB of int32 results and is shaped like the peak
(1024 FLOP/cycle); it validates **numerics**, not a sustainable hardware rate. The 996-cycle RTL run is the measured full-chip anchor and is not a steady
state: it includes the 8-block I$ preload and launch handshake.

### 2.5 Numerical tolerance

* **Bit-exact int32** against the integer model; `C` cannot overflow
  (`|C| <= 32 x 12 x 12 = 4608`). The 64x64x64 model run reports `max_err = 0`.
* The epilogue needs the **same order**, `(C/4) * 2^(eA+eB-254)`: power-of-two
  multiplies are exact in fp32 while normal, and an fp64 reference must agree to
  `rtol <= 1e-6`. No NaN/Inf/saturation, no FP4 denormal, no flush-to-zero;
  `eA`/`eB` of 0 or 255 are reserved by OCP MX and rejected.

## 3. GEMM — FP16/BF16 (MODEL, not RTL)

### 3.1 Contract and status

```
C[i][j] = sum_k A[i][k] * B[k][j]      A, B: IEEE binary16 (subnormals, no FTZ)
C: fp32 accumulator, rounded to fp16 (RN) on store
```

* Tile `16 x 16 x 16` on the model (`wmma_f16`, `M*N*K/128 + 8` cycles):
  `A` = 128 words (512 B), `B` = 128 words, `C` fp32 = 256 words (1 KB); A/B
  single-buffered plus C fits 2 KB. BF16 uses the same path, but the model
  implements FP16 rounding only.
* **MODEL only**: `sim/m1_sim.hpp` states it — "the production RTL implements
  MXFP4; this model is the FP16/BF16 datapath used by Softmax/FlashAttention
  bring-up". No FP16 operand path exists in `rtl/` (opcodes 0x2F/0x34–0x37
  decode as no-ops), so nothing here runs on RTL v1.

### 3.2 Reference plan

TDM stages A/B as packed halves into LDS, the model's FP16 tile multiplies with
fp32 accumulators, and the epilogue applies bias/scale, rounds to fp16 and
stores 128 B blocks. On RTL this plan is blocked at step one: no FP16 tile.

### 3.3 Tolerance

Accumulator vs fp64 reference: `|err| <= 2^-20 * sqrt(K) * sum_k |a_k b_k|` with
the reduction order fixed by the tile shape; stored fp16: `<= 1 ulp`,
`atol <= 2^-24` for subnormals. These are RTL-port targets; the model's evidence
is the passing runs in §6.

## 4. Softmax — stable, row-wise

### 4.1 Contract

```
m   = max_i x_i
l   = sum_i exp2( (x_i - m) * log2(e) )
y_i = exp2( (x_i - m) * log2(e) ) / l           sum_i y_i = 1
p_i = exp2( (x_i - m) * log2(e) )               (unnormalised form)
```

The row max is subtracted first: that is the stability requirement, and it
bounds `p_i` to `(0, 1]` so a fixed-point path cannot overflow. Two output forms
are contractual: normalised `y` (one reciprocal per row) and `(p, l)`, which
FlashAttention uses to divide once at the end. `N` is runtime; the kernel takes
32 elements per chunk, one per lane.

### 4.2 Implementations

| Variant | Datapath | Accuracy (measured where stated) | Status |
|---|---|---|---|
| **M1 — model FP16** | `m1::softmax_row`: FP16 rows in LDS, `sfu_exp2_row`/`sfu_rcp_row` | 8x128: row-sum error **1.716e-3** (tolerance 2e-3), 3,168 cycles *(model)*; the HIP example reports 4.5e-4 | **IMPL (model)** |
| **S1 — fixed point (Q16.16 in, Q0.23 `p`, int32 `l`)** | SIMD32 int + 256-entry exp2 LUT in LDS + Newton reciprocal | `rtol <= 5e-6` target (LUT ≈1.5e-6, Q0.23 1.2e-7, reciprocal 2^-20) | **SPEC** — RTL path, not written |
| **S2 — SFU 16-bit fixed point** | `rtl/sfu.v` `exp2`/`rcp` (Q4.12→Q0.12, Q1.15) | exp2 max abs 3.53e-4, rcp max rel 2.51e-4 *(measured over all codes)* | **IMPL block**, not integrated; 1 op / 5 cycles |

The SFU is **serialized**: 32 lanes' `exp2` is 32 x 5 = 160 cycles, so for a
full wave the LUT sequence (≈15 instructions ≈60 cycles per 32-element chunk)
is faster. The SFU earns its area on the per-row reciprocal and scalar control;
the LUT path remains the RTL reference.

### 4.3 Tile shape and LDS budget (S1)

| Region | Words | Bytes |
|---|---|---|
| exp2 LUT, 256 entries x Q0.23 int32 | 256 | 1024 |
| Row tile + `p` staging, 8 rows x 32 int32 each | 512 | 2048 |
| scratch (masks, reciprocal seeds) | 128 | 512 |
| **used** | **896** | **3584** (512 B free) |

One wave processes 8 rows of 32; a 64-row tile needs 2 KB of row storage and
drops `p` staging, so the 8-row tile is the reference.

### 4.4 Reference plan (S1)

Per 32-element chunk (one element per lane), one SIMD:

```
V_LDS_LD v0,row_base ; V_SUB v1,v0,m ; V_CMP_GT+V_CNDMASK (clamp)      4 instr
V_SHR/V_AND (int part, 8-bit frac) ; V_LDS_LD_IDX x2 (LUT)           4
V_SUB,V_MUL,V_SHR,V_ADD (interp) ; V_SHR_B32 (2^xi)                  5
V_ADD l,l,p (row sum) ; V_LDS_ST p_base,p (store p)                  2
```

≈15 instructions → **≈60 cycles per 32-element chunk** for exp+sum. Row
reductions use an LDS butterfly (round `r = 0..4`: store, `addr = base +
4*(lane XOR 2^r)`, `V_LDS_LD_IDX`, combine) at 6 instructions per round, 30 per
reduction (≈120 cycles); pass A adds a reduction, pass C adds ≈12 instructions
for the reciprocal seed and Newton steps. Analytic row cost `T_row ≈
4*(24*N/32 + 72)` cycles: for `N = 1024`, ≈3,360 cycles/row (3.3 cycles per
element). This is issue-bound: no dual issue.

### 4.5 Tolerance

* M1 (model): row sums within 2e-3 of 1.0, per-element error below 1e-3 for
  FP16 rows (the passing run above).
* S1: `|y_i - y_i(ref)| <= 5e-6 * max(|y_i(ref)|, 1/N)` — a tolerance test, not
  a bit test, because of LUT interpolation and fixed-point rounding. Degenerate
  rows give `1/N`; `N = 1` gives 1.0; `N > 4096` is outside the contract.

## 5. FlashAttention

### 5.1 Contract

Per query block (`Br = 16` rows) and key block (`Bc = 16` keys, head dim `d`):

```
S  = Q K^T                        (16 x 16, exact when Q/K are FP4 -> int32)
p  = exp2((S - m) * log2e)        row-wise, m = row max
P  = quantize(p, FP4, per-row power-of-two scale)      (software)
O += P V                          (16 x d, exact int32 partials)
y  = O / l                        l = row sum of p, once per row
```

Two paths exist and must not be conflated:

* **Model path (IMPLEMENTED, measured).** `m1::flash_attention_f16`: FP16
  Q/K/V, `seq`/`dim` multiples of 16, `seq <= 32`, optional causal mask.
  Measured: seq=32, dim=16, causal — error **1.004e-3** vs a CPU float
  reference (tolerance 2e-2), **3,744 cycles** *(model)*.
* **FP4 path (SPEC).** `P` quantised to E2M1 with a per-row power-of-two scale;
  `QK^T`/`PV` exact int32. This is the RTL exactness story and is implemented
  nowhere yet; it cannot be checked against an unquantised reference.

### 5.2 Tile shape and LDS budget (FA-16-16-32, FP4 path)

| Region | Words | Bytes | Content |
|---|---|---|---|
| Q | 64 | 256 | `Q[16][32]` packed FP4 |
| K, V | 128 | 512 | `K[16][32]` in `K^T` layout, `V[16][32]` transposed |
| S, P | 288 | 1152 | `S[16][16]` int32 scores; `P[16][16]` packed FP4 + row scale |
| O | 512 | 2048 | `O[16][32]` int32 accumulator |
| **used** | **992** | **3968** | 128 B free — no scratch, no double buffer |

96.9 % of LDS. Accepted: K/V cannot double-buffer (TDM and WMMA already
serialise), `S` is reused for packed `P`, and `O` cannot be int16 without losing
the exact-integer contract. A Br=8 variant frees 1 KB for double buffering but
halves MMA utilisation. On RTL, `PV` needs `K = 32` with only 16 keys, so `P` is
zero-padded and half the `PV` MACs are wasted.

### 5.3 Reference plan

1. TDM `Q` once per query block (2 chunks); per key block, TDM `K` and `V`
   (4 chunks, ≈44 cycles), then `S_WMMA` `Q x K^T` (1 MMA, ≈37 cycles).
2. Softmax on the 16x16 `S` (2 lanes/row, 8 elements per lane, one in-row
   butterfly): ≈15 instructions per chunk, ≈480 cycles including reductions.
3. Quantise `p` to FP4 with a per-row power-of-two scale (≈96 cycles); `PV` as
   2 MMAs (columns 0–15 and 16–31, zero-padded K, ≈74).
4. Update `O` by exact int32 add (≈256 cycles; the online variant rescales when
   the max changes, same cost), then `O/l`, undo the row scale, store 8 blocks.

### 5.4 Cycle estimate

Per 16x16x32 block (analytic, FP4 path): ≈44 TDM + 37 QK + 480 softmax + 96
quantise + 74 PV + 256 O-update ≈ **990 cycles**; useful work 32,768 FLOP →
**≈33 FLOP/cycle ≈ 3.3 GFLOP/s**. Attention on M1 is integer-issue-bound, not
MMA-bound. The measured model run (FP16, seq=32, dim=16, causal, 3,744 cycles)
has a different shape, so cycles are not comparable one-for-one, but it confirms
that softmax and the O update dominate.

### 5.5 Tolerance

* Model path: output within 1e-3 absolute of the CPU float reference for the
  measured shape (tolerance 2e-2). Report the shape with the number; larger
  `seq`/`dim` are outside the model's current limit.
* FP4 path against a reference applying the **same** quantisation: bit-exact
  int32 for `QK^T`, the `PV` partials, and `O` before division. Against exact
  attention, E2M1's 3-bit magnitudes let one `P` element carry ≈25 % error; the
  target is `<= 5 %` relative L2 on `O` (target, not measured), and the
  quantised result must never be quoted as exact.

## 6. Mapping to M1 blocks and contract summary

| Operator | Target | Exactness | LDS | Status |
|---|---|---|---|---|
| GEMM FP4 | RTL: WMMA + LDS + SIMD epilogue + TDM/AXI; model: `gemm_fp4` | **exact int32** (C ≤ 4608) | 1.5 KB (2 KB double-buffered) | IMPL — RTL tile measured, 64³ model bit-exact |
| GEMM FP16 | model `wmma_f16` only | fp32 accumulate, RN to fp16 | 2 KB | MODEL — no RTL datapath |
| Softmax | model `softmax_row` + SFU; RTL SFU + LDS LUT (SPEC) | FP16: 2e-3 row-sum tolerance; fixed point: rtol 5e-6 | 3.5 KB (S1) | IMPL (model) / SPEC (RTL) |
| FlashAttention | model `flash_attention_f16`; FP4 path SPEC | FP16: 1e-3 abs vs float; FP4: exact except P | 3,968 B | IMPL (model) / SPEC (FP4) |
| SFU | `rtl/sfu.v`, verified standalone | exp2 3.53e-4 abs; rcp 2.51e-4 rel | — | IMPL block, **not integrated** |

## 7. Open items

1. **No measured operator throughput on RTL** beyond the 446/996-clock
   full-chip runs and the 37-cycle `tb_wmma` block; §2.4's analytic rows need
   instrumented RTL runs before being quoted as sustained.
2. **The SFU is not wired in**: it passes its unit test and synthesizes to 1,728
   cells, but no `wgp`/`simd32` instance exists, so `exp2`/`rcp` are reachable
   only through the model. No `tanh`, no FP32, no opcode.
3. **FP16 exists only in the model**, which says so; softmax and attention
   results must not be presented as RTL results. **No independent golden model**
   exists (`spec/SAD.md` R1): the model's reference is a second implementation,
   not an independent oracle.
4. **Range checks**: `|C| <= 4608` is safe, but Q0.23 `p`, int32 `l`, and the
   model's FP16 range must be re-checked if `N` exceeds 4,096, if `seq`/`dim`
   grow past 32/16, or if the producer's logit scale changes.
