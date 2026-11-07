# CDNA5-M1 performance model

Status: **bring-up performance model**. Numbers below derive from
`spec/ISA.md`, `spec/UARCH.md` and `rtl/`; simulator/Yosys values are cited,
planning budgets are labelled and never presented as measured. The
**0.1 TFLOP/s MXFP4 at 100 MHz** headline is a *datapath peak*; sustained
throughput is lower (§2.6).

The design is one WGP-equivalent slice: 1 CU, 2 x SIMD32, one 16x16x32 WMMA
core, 4 KB LDS, 1 KB I$, one 1-D TDM and a 128-bit AXI4 master. There is no
L2, no cache model and no multi-wave latency hiding in v1.

## 1. Configuration used for all arithmetic

| Parameter | Value | Source |
|---|---|---|
| `clk` | 100 MHz (10 ns) | `spec/UARCH.md`, `constraints/wmma.sdc` |
| Process / corner | Sky130 HD, `tt_025C_1v80`, 1.8 V | `coresmith/.pdk/sky130A` |
| SIMD32 instances | 2 per CU (one WGP slice) | `rtl/wgp.v` |
| Lanes per SIMD | 32 (wave32) | `spec/ISA.md` |
| Vector FP4 MAC per lane/cycle | 8 (`V_DOT8_I32_IU4`) | `rtl/simd32.v` |
| Vector INT8 MAC per lane/cycle | 4 (`V_DOT4_I32_IU8`) | `rtl/simd32.v` |
| Matrix tile | 16x16x32 MXFP4, 512 MAC/cycle | `rtl/wmma.v` |
| Matrix accumulators | 256 x int32 | `rtl/wmma.v` |
| LDS | 4 KB, 32 banks x 32 rows x 32 bit | `rtl/lds.v` |
| LDS ports | 2 lane ports + 1 linear (32-word) port | `rtl/lds.v` |
| Global memory | AXI4, 128-bit, INCR8 (128 B) | `rtl/axi_master.v` |
| VGPR / SGPR | 16 VGPR/lane, 32 SGPR/wave | `rtl/cdna5_m1_defs.vh` |
| Instruction issue | one instruction in flight per SIMD | `rtl/simd32.v` FSM |

## 2. Peak arithmetic

### 2.1 Matrix engine (MXFP4)

One `S_WMMA` is `C[16][16] += A[16][32] x B[32][16]` with FP4 (E2M1) inputs
and int32 accumulators:

```
MACs per WMMA   = 16 x 16 x 32 = 8192 MAC
FLOPs per WMMA  = 8192 x 2 FLOP/MAC = 16384 FLOP
Compute time    = 16 cycles -> 512 MAC/cycle
Peak            = 512 FP4 MAC/cycle x 2 FLOP x 100 MHz = 102.4 GFLOP/s
```

This is the 0.1 TFLOP/s headline (1024 FLOP/cycle). Note that 512 MAC/cycle requires 2 K-slices
(2 k values) x 256 output elements (16x16) per cycle; the RTL computes exactly
that in `S_COMP` (`rtl/wmma.v:228-243`).

### 2.2 Vector FP4 dot8 (`V_DOT8_I32_IU4`)

```
2 SIMD x 32 lanes x 8 MAC x 2 FLOP x 100 MHz = 1024 FLOP/cycle = 102.4 GFLOP/s
```

Each lane carries a combinational 8-way E2M1 dot product
(`v_dot8_fp4`). This is the same 102.4 GFLOP/s datapath peak as the matrix
engine, but it is reached only if both SIMDs issue a dot8 every cycle.

### 2.3 Vector INT8 dot4 (`V_DOT4_I32_IU8`)

```
2 SIMD x 32 lanes x 4 MAC x 2 OP x 100 MHz = 512 OP/cycle = 51.2 GOPS
```

### 2.4 Vector INT32 (`V_ADD_I32` / `V_MUL_I32` family)

```
2 SIMD x 32 lanes x 1 OP x 100 MHz = 64 OP/cycle = 6.4 GOPS
```

All VALU ops are single-issue per SIMD; the 6.4 GOPS figure is the integer
datapath width x clock, not the instruction retirement rate.

### 2.5 Memory and transport bandwidth

| Resource | Formula | Ideal |
|---|---|---|
| LDS, one port | 32 banks x 32 bit = 128 B/cycle | 12.8 GB/s |
| LDS, all three ports | arbitration grants one port/cycle | 12.8 GB/s aggregate |
| AXI4 master | 128 bit = 16 B/beat; 1 beat/cycle | 1.6 GB/s |
| AXI4 burst | INCR8 = 8 beats = 128 B | 128 B per transaction |
| TDM | 32 words (128 B) per block, <=256 words | AXI-limited |
| I$ preload | 1 KB = 8 x 128 B blocks = 64 beats | 640 ns ideal |

The LDS number is per-port raw bandwidth; `rtl/lds.v` grants lane port 0 >
lane port 1 > linear port, so the three ports are **not** additive. A bank
conflict on a lane port sets `conflictN`; `simd32` turns that into a wave
`error` rather than serialising (`rtl/simd32.v:447`). Software must keep the
contiguous `V_LDS_*` patterns.

### 2.6 Sustained vs peak: instruction issue and block occupancy

The peak numbers above assume one vector instruction per SIMD per cycle and a
WMMA compute block with no bubbles. The RTL does not do either. Taking the RTL
FSM as the contract:

* `simd32` retires one instruction every **4 cycles** in the common case:
  `S_FETCH` (1) + `S_FETCH_W` (1) + `S_DEC` (1) + `S_EXEC` (1). There is no
  fetch/execute overlap and no dual issue (`rtl/simd32.v:360-446`).
  Consequence: the vector datapath is idle 3 of 4 cycles, so the sustained
  vector peaks are **102.4/4 = 25.6 GFLOP/s** (dot8), **12.8 GOPS** (int8
  dot4) and **1.6 GOPS** (int32).
* A single WMMA takes **37 cycles** start-to-done in simulation with the
  unit-test setup (`rtl/wmma.v` + `rtl/lds.v`): 1 start cycle + 11 load
  (3+3+3+2 cycles for the four `S_LA` beats; each beat is a request cycle, a
  ready cycle and, for the first three, an `S_LW` bubble) + 16 compute + 9
  store (8 beats back-to-back after the first ready). The WGP adds >=2 idle
  cycles between MMA operations (`wmm_cool` in `rtl/wgp.v:275`). A
  single-buffered WMMA therefore sustains:

```
16384 FLOP / 37 cycles     = 442.8 FLOP/cycle
442.8 x 100e6              = 44.3 GFLOP/s   (42.0 with the 2-cycle cool-down)
```

  i.e. **well under half** the 102.4 GFLOP/s headline, before any software
  gaps.
* The two SIMDs share one WMMA and one TDM; matrix, TDM and global-memory work
  is serialised by the WGP (`rtl/wgp.v:263-303`), so peaks are not additive.

### 2.7 Per-block throughput summary

| Block | Metric | Nominal | Sustained (RTL duty) | Basis |
|---|---|---|---|---|
| WMMA | MXFP4 FLOP/s | 102.4 GFLOP/s | 44.3 GFLOP/s | 16 compute / 37 block cycles |
| SIMD32 VALU | FP4 dot8 | 102.4 GFLOP/s | 25.6 GFLOP/s | 4-cycle issue |
| SIMD32 VALU | int8 dot4 | 51.2 GOPS | 12.8 GOPS | 4-cycle issue |
| SIMD32 VALU | int32 | 6.4 GOPS | 1.6 GOPS | 4-cycle issue |
| LDS | 32-bit words | 32 words/cycle | 32 words/cycle | one port/cycle |
| LDS | bytes | 128 B/cycle | 128 B/cycle | 12.8 GB/s |
| AXI4 | bytes | 16 B/cycle | <16 B/cycle | 1 outstanding, arb cooldown |
| TDM | 128 B blocks | 1 block/128 B burst | AXI-limited | one outstanding |

## 3. Roofline for the 16x16x32 MXFP4 matmul

### 3.1 Work and bytes per tile

```
FLOPs  = 2 x 16 x 16 x 32               = 16384 FLOP
A      = 16 x 32 x 4 bit                = 256 B
B      = 32 x 16 x 4 bit                = 256 B
C      = 16 x 16 x 32 bit               = 1024 B
Bytes  = 256 + 256 + 1024               = 1536 B
AI     = 16384 / 1536                   = 10.67 FLOP/B
```

### 3.2 Balance points

* **AXI balance**: to saturate 1024 FLOP/cycle from global memory at
  16 B/cycle the kernel needs `1024/16 = 64 FLOP/B`. The 16x16x32 tile has
  only 10.67 FLOP/B, so a streaming kernel is deeply memory-bound.
* **LDS balance**: 1024 FLOP/cycle / 128 B/cycle = **8 FLOP/B**. The tile's
  10.67 FLOP/B is above 8, so LDS-resident operands are compute-bound in
  principle; the 16/37-cycle WMMA duty cycle then cuts it to 43%.

### 3.3 Roofline cases

| Case | Global bytes per tile | AI (FLOP/B) | Roofline at 1.6 GB/s |
|---|---|---|---|
| A, B, C all streamed | 1536 | 10.67 | 17.1 GFLOP/s |
| A, B resident in LDS, C streamed | 1024 | 16.0 | 25.6 GFLOP/s |
| A/B/C resident in LDS (compute roof) | 0 | infinite | 102.4 peak / 44.3 sustained |
| K-blocked, C resident, K=32*Tk | 512*Tk | 32*Tk/(Tk+2) | -> 51.2 GFLOP/s, capped at 44.3 |
| A reused r times across N-tiles | 256 + 1280*r | 16384*r/(256+1280*r) | -> 12.8 FLOP/B = 20.5 GFLOP/s |

Keeping C in LDS and accumulating over K raises the effective AI towards 32
FLOP/B, i.e. an AXI roofline of `1.6 GB/s x 32 = 51.2 GFLOP/s`; the 37-cycle
WMMA block then caps the real number at 44.3 GFLOP/s. In other words the M1
can be balanced at **well under half the headline** if (and only if)
software keeps the C tile and operands in the 4 KB LDS; otherwise the AXI
link caps it at 17-26 GFLOP/s.

### 3.4 LDS traffic of one WMMA

```
A + B load = 4 beats x 128 B      = 512 B
C store    = 8 beats x 128 B      = 1024 B
Total      = 1536 B over 37 cycles = 41.5 B/cycle average
                                      = 4.15 GB/s = 32.4% of one LDS port
```

Streaming A/B during compute would need `512/16 = 32 B/cycle` and the C store
needs 64 B/cycle; both fit under 128 B/cycle, so the 37-cycle block needs
double buffering, not a wider LDS (C 1 KB + 2 x A/B 512 B = 2 KB fits 4 KB).

### 3.5 Capacity check for a blocked GEMM

A 16x16 C tile costs 1 KB, A/B tiles 256 B each; double buffering is
`2 x 512 + 2 x 1024 = 3 KB`, leaving 1 KB in the 4 KB LDS for scales and
spills. A 32x32 C tile needs 4 KB alone and does not fit; the practical tile
is 16x16 (16x32 with single-buffered C loses overlap).

## 4. Comparison with CDNA5 MI455X

| Property | MI455X (CDNA5) | CDNA5-M1 | Ratio |
|---|---|---|---|
| WGP count | 256 | 1 WGP slice (1 CU) | 1/256 |
| Matrix throughput | 40.26 PF MXFP4 | 0.1024 TF | 1/393164 |
| Clock | 2.4 GHz | 100 MHz | 1/24 |
| FLOP/cycle per WGP | 65536 | 1024 (whole M1) | 1/64 |
| Matrix cores per WGP | 2 | 1 | 1/2 |
| FP4 MAC/cycle per WGP | 32768 | 512 | 1/64 |

Derivation of the MI455X per-WGP number:

```
40.26e15 FLOP/s / 256 WGP = 157.2656e12 FLOP/s/WGP
157.2656e12 / 2.4e9       = 65527 FLOP/cycle/WGP  (spec rounds to 65536)
```

The M1 executes 1024 FLOP/cycle of matrix work (512 MAC x 2), so:

* **per-cycle**: 1024 / 65536 = **1/64 of one MI455X WGP**;
* **absolute at nominal clocks**: 102.4e9 / 157.2656e12 = **1/1536**;
* relative to a hypothetical 1/8-WGP slice at 100 MHz
  (`65536 x 100e6 / 8 = 0.8192 TFLOP/s`): the M1 is 1/8 of that slice.

Reconciliation of the "1/128" shorthand: 65536 / 512 = 128, i.e. the shorthand
compares the M1's **512 MAC/cycle** against the WGP's **65536 FLOP/cycle**,
mixing MACs with FLOPs. Under the same x2 FLOP/MAC convention used for the
0.1 TFLOP/s headline, the per-cycle ratio is 1/64 and the absolute ratio at
the nominal clocks is 1/1536. The "1/128" figure is kept here only as the
MAC-vs-FLOP shorthand; do not use it in a customer-facing throughput claim.

Relative to the real part: 1/256 of the WGP count, 1/64 of the per-cycle
matrix width and 1/24 of the clock (256 x 64 x 24 = 393216; the 40.26 PF
rounding explains the 393164 in the table).

## 5. Engineering deviations that change performance

These are deliberate bring-up simplifications, not performance claims:

1. **Exact integer MXFP4 accumulation.** E2M1 is decoded to the integer
   sequence `{0,1,2,3,4,6,8,12}` (2x scale); products are therefore 4x the
   real product and the matrix/vector results are exact int32 until the
   consumer removes the 4x scale. There is no FP4 normalization/rounding and
   no denormal flush in hardware. The cost is that the x1/4 rescale and the
   E8M0 block-scale multiply are software work.
2. **E8M0 block scale in software.** MXFP4 semantics require one E8M0
   exponent per 32-element block. The M1 core accumulates the scaled
   integers; software applies `2^(e-127)` per block after the WMMA and sums
   partials. This is extra VALU/LDS traffic that is not in the 102.4
   GFLOP/s headline, and it grows with the number of K blocks.
3. **F16/FP32 vector ops are reserved.** `V_ADD_F16`, `V_MUL_F16`,
   `V_FMA_F16`, `V_CVT_F32_I32` and indexed LDS forms are in the ISA text but
   are not implemented in `rtl/simd32.v`: they hit the decode default and
   write 0. `spec/UARCH.md` mentions an `ENABLE_F16`/`fp16_lane` block; that
   file is stale relative to the RTL. Any F16 or FP32 kernel would be
   functionally wrong today.
4. **WMMA is C = A x B, not accumulate.** `spec/UARCH.md:145-148` records
   this known deviation. Software must add the new C to the old C in LDS;
   that doubles C traffic (read 1 KB + write 1 KB) unless the kernel keeps
   partials in VGPRs.
5. **1-D TDM, 4 KB LDS, 1 KB I$ and one wave per SIMD.** The CDNA5 5-D TDM,
   320 KB LDS, 64 KB I$ and multi-wave residency are replaced by bring-up
   subsets. Consequence: no latency hiding; every kernel is exposed to AXI
   latency and the I$ preload.
6. **128-bit AXI with one outstanding transaction.** The 1.6 GB/s ideal is a
   ceiling: `M_COOL/M_COOL2` adds cycles around every block transfer and the
   WGP arbiter serialises CP/SIMD/TDM (small-transfer examples in §6).
7. **Sky130 at 100 MHz, tt_025C_1v80.** No clock-tree, IR-drop or multi-corner
   derating is included; 100 MHz is a target, not a signoff result.

## 6. Measured numbers available today

The only measured performance data are the two full-chip simulations in `tb/`
(see `doc/VERIFICATION.md`):

| Simulation | End of sim | Data moved | Avg B/cycle | Note |
|---|---|---|---|---|
| `tb_top` vecadd | 485 cycles (4.85 us) | 1 KB I$ + 3 x 128 B = 1408 B | 2.9 B/cycle (0.29 GB/s) | latency-dominated; 10 AR + 1 AW bursts |
| `tb_wmma_top` | 1035 cycles (10.35 us) | 8 I$-blocks + 4 TDM + 8 C-blocks = 2560 B | 2.47 B/cycle (0.247 GB/s) | 12 AR + 8 AW bursts, 1 WMMA |

These are bring-up tests, not bandwidth benchmarks: small transfers over the
one-outstanding AXI link run at a few hundred MB/s, an order of magnitude
below the 1.6 GB/s ideal. Do not quote them as sustained bandwidth.

The CSR map already exposes `CYCLE_LO/CYCLE_HI` (0x24/0x28), `WAVE_DONE`
(0x2C) and `S_CSR_READ` for cycle counting. A cycle-accurate benchmark
sweeping K, tile count and TDM sizes is TODO.

## 7. Performance summary

* Datapath peak: **102.4 GFLOP/s MXFP4** (matrix and vector dot8 both hit it);
  sustained: **44.3 GFLOP/s** matrix, **25.6 GFLOP/s** FP4 dot8,
  12.8 GOPS int8 and 1.6 GOPS int32.
* Global-memory roofline for a 16x16x32 tile: **17.1-44.3 GFLOP/s** depending
  on C residency and K blocking; AXI 1.6 GB/s is the binding constraint.
* MI455X: **1/64 per-cycle**, **1/1536 absolute** (2.4 GHz vs 100 MHz); the
  "1/128" shorthand mixes MACs and FLOPs (§4).
* No PPA numbers exist yet: pre-fix `wmma` synthesis OOM'd, a post-fix run is
  in flight, and the LDS register array expands to ~3.3M cells; see
  `doc/BACKEND.md` for the measured attempts and the TODO placeholders.
