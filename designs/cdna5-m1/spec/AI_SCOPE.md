# CDNA5-M1 — AI-only chip scope

| Field | Value |
|---|---|
| Document | AI scope statement, revision 1.0 (2026-11-07) |
| Applies to | `rtl/cdna5_m1_top.v` and the RTL hierarchy under `rtl/` |
| Normative inputs | `spec/ISA.md`, `spec/UARCH.md`, `spec/SAD.md`, `project/arch/prd_spec.md` (PRD rev 1.0), `project/arch/sad_spec.md` (SAD rev 1.0) |
| Status vocabulary | **IMPL** = implemented and simulated in `rtl/`; **SPEC** = frozen contract, RTL pending; **TARGET** = roadmap item, not frozen and not implemented; **OUT** = out of scope for this chip |

This document is the scope contract. If a block, instruction, CSR, pin, or
software path is not listed as IMPL/SPEC/TARGET here, it is OUT. Where this
document and the ISA/RTL disagree, the RTL is authoritative for behaviour and
this document is authoritative for scope.

## 1. Scope statement

CDNA5-M1 is an **AI-only** accelerator. It implements one compute slice of the
CDNA5 execution model and nothing else: one Work-Group Processor (WGP) with one
Compute Unit (CU), two SIMD32 units (`wave32`, 32 lanes each, 16 VGPR/lane,
32 SGPR/wave), one WGP-shared 16x16x32 MXFP4 matrix core (WMMA, 512 MAC/cycle,
102.4 GFLOP/s at 100 MHz), a 4 KB banked Local Data Share (LDS), a 1 KB
host-preloaded instruction RAM (I$), a 1-D Tensor Data Mover (TDM), one
128-bit AXI4 master, and one 32-bit AXI4-Lite host CSR slave — single clock,
100 MHz, single 1.8 V supply, Sky130 HD.

**All graphics, video, display, raster, texture, and media-codec blocks and
ISA are removed and out of scope.** "Removed" is meant in six concrete senses,
each of which is checkable against the RTL:

1. **No block.** No rasterizer, render backend, texture unit, display
   controller, video decoder/encoder, or media engine exists in `rtl/`.
2. **No instruction.** No graphics, texture, export, ray-tracing, or media
   opcode decodes to a functional unit (see §7).
3. **No state.** No graphics register, context, queue, or memory format exists
   in the CSR map (§7 of `spec/SAD.md`, 12 registers).
4. **No pin.** The 581 functional signal bits are `clk`, `rst_n`, `irq`, AXI4,
   and AXI4-Lite only — no pixel clock, no display serialiser, no video port,
   no sensor/ISP interface.
5. **No compiler path.** No graphics or media language front end, no shader
   stage, no image/surface type in the software model.
6. **No verification obligation.** None of the DV benches target graphics or
   media behaviour; adding one would be a scope change (§10).

## 2. Removed graphics / video / display / media scope

| Removed function | CDNA5-class implementation | M1 disposition | Consequence |
|---|---|---|---|
| Graphics command front end, draw/dispatch, graphics queues | MEC/ME, ring buffers, per-context queues | Removed. The CP is a fixed-function launch FSM: `CONTROL.START` → 1 KB I$ preload → grid of 1..8 workgroups | No command processor firmware, no ring, no context switch |
| Primitive assembly, tessellation, geometry/vertex/hull/domain stages | IA/VGT/PA, parameter cache | Removed | No vertex buffers, no index fetch, no clipping |
| Rasterizer, scan conversion, depth/stencil, render backend (ROP) | PA/SC/DB/CB | Removed | No render targets, no framebuffer, no MSAA resolve, no blend |
| Shader export, mask/export path (`EXP`, MRT) | CB/EXP | Removed | No colour export, no tile buffer |
| Texture address/data path, samplers, mip/aniso filtering, texture cache (TA/TD/TCP) | TA/TD/TCP + L1 texture cache | Removed. LDS is a scratchpad, not a texture cache; addressing is linear | No image/sampler objects, no swizzled formats, no bilinear |
| Display controller and PHYs (DCN, DisplayPort/HDMI) | DCN + PHY | Removed | No pixel clock, no CRTC, no plane, no vblank; the chip has exactly one clock |
| Video decode and encode (VCN/UVD) | VCN: JPEG, AVC/H.264, HEVC/H.265, VP9, AV1 | Removed — **JPEG, HEVC, and AV1 are explicitly out of scope**, as are all other codecs | No entropy decode, no motion compensation, no deblock/SAO, no film grain, no rate control |
| Video post-processing, scaling, colour management | VCN/MPC | Removed | No YUV, no colour space conversion, no scaler |
| Audio coprocessor (ACP) | ACP | Removed | No audio path |
| GPU virtual memory, per-process contexts, page tables, migration | GPUVM, MMU, SDMA | Removed. One flat 32-bit address space, one non-preemptible launch context | No SVM, no page faults, no unified memory |
| Graphics memory formats: tile swizzles, DCC/CMASK/FMASK, delta colour compression | TC-compatible/DCC | Removed. Memory is linear little-endian 32-bit words in 128 B blocks | Software must not assume any tiling |
| Ray tracing (BVH, ray-box/ray-tri), mesh/task shaders | RT cores, primitive shaders | Removed | No BVH state, no intersection hardware |
| Cross-engine semaphores/fences, GPU scheduler | Semaphores, HQD | Removed. The only synchronisation is launch completion (`STATUS.DONE` / `irq`) | No fine-grained fences |

### 2.1 Removed instruction classes

| ISA class | Examples | M1 status |
|---|---|---|
| Pixel/fragment and vertex shader ALU | `V_INTERP_*`, `EXP`, `V_MASK`, `V_CVT_PKRTZ` | OUT — no graphics wavefronts |
| Texture/sampler/image | `SAMPLE`, `IMAGE_LOAD/STORE/SAMPLE`, sampler/`s_*` descriptors | OUT |
| Export / render target | `EXP`, `S_ENDPGM` is a wave end, not an export | OUT (no MRT) |
| Ray tracing | `IMAGE_BVH_INTERSECT`, `RAY_*` | OUT |
| Wave64 graphics wavefronts | 64-lane gfx waves | OUT — wave32 only |
| Graphics LDS/GDS operations | `DS_*` graphics layouts, `ds_swizzle` | OUT; the M1 ISA has only `V_LDS_*` (0x30, 0x31, 0x38, 0x39) |
| Media/codec control | VCN/UVD register and command space | OUT |
| Display control | DCN register space | OUT |

The M1 ISA is a **32-bit fixed-format subset** (`spec/ISA.md`) that is not
binary compatible with any gfx-class CDNA5 encoding. Vector opcode space
`0x3B–0x3F` and scalar space `0x18–0x1F` are unallocated; nothing may be added
there without a spec revision (§10).

## 3. AI datapaths in scope

| Datapath | Function | Width / rate at 100 MHz | Status | Evidence |
|---|---|---|---|---|
| WMMA matrix core | `C[16][16] int32 = A[16][32] x B[32][16]`, MXFP4 E2M1 inputs, 16 compute cycles | 512 MAC/cycle = 1024 FLOP/cycle = **102.4 GFLOP/s** peak; 51.2 GFLOP/s at the 32-cycle cadence; 44.3 GFLOP/s at the measured 37-cycle block | IMPL | `tb_wmma`, `tb_wmma_top` PASS; `spec/ISA.md` 0x15; `spec/UARCH.md` |
| SIMD32 x2 — SALU/VALU | 32 lanes/instr, int32 wrap, bitwise, shifts, compare/select, EXEC mask | 2 x 32 ops/cycle peak; 1 instruction/4 cycles per SIMD → 16 ops/cycle sustained (1.6 GOPS) | IMPL | `tb_top` PASS (446 clocks START→IRQ) |
| SIMD32 — dot products | `V_DOT8_I32_IU4` (8 FP4-raw MAC/lane/cycle), `V_DOT4_I32_IU8` (4 int8 MAC/lane/cycle) | 102.4 GFLOP/s peak / 25.6 GFLOP/s sustained (dot8); 51.2 GOPS peak / 12.8 GOPS sustained (dot4) | IMPL | `rtl/simd32.v`; `doc/PERFORMANCE.md` §2.3–2.7. Not a KPI (`sad_spec` AD-18) |
| LDS | 4 KB, 32 banks x 32 rows x 32 bit, 2 lane ports + 1 linear 32-word port, conflict detection | 1 grant/cycle = 32 words = 128 B = **12.8 GB/s** aggregate | IMPL | `rtl/lds.v`; conflict aborts the wave (`STATUS.ERROR`) |
| TDM | 1-D contiguous global→LDS copy, 32-word (128 B) units, `len` multiple of 32 and ≤ 256 words | AXI-limited; 128 B per burst | IMPL | `rtl/tdm.v`; `tb_wmma_top` PASS. **5-D descriptors, bounds checks, multicast, LDS→DRAM: OUT** |
| I$ | 1 KB = 256 x 32-bit, two read ports, host/CP preload only | 1 word/port/cycle = 400 MB/s per SIMD; 4-cycle instruction interval | IMPL | `spec/SAD.md` §5.3. No misses, no refill, no cache |
| Command processor / dispatch | Launch FSM, CSR file, grid dispatch (1..8 workgroups), completion IRQ, 64-bit cycle counter | 1 launch at a time | IMPL | `spec/SAD.md` §7 |
| AXI4 master | 128-bit data, 32-bit address, INCR8 (128 B), one outstanding | 16 B/cycle = **1.6 GB/s** peak; ~1.1–1.2 GB/s expected sustained | IMPL | `rtl/axi_master.v`; no exclusive/atomic/unaligned |
| **SFU** — `exp2`, `rcp` (no `tanh`) | Serialized 16-bit fixed-point transcendental unit, one 16-bit command port | 1 command / 5 cycles, 4-cycle latency; 1,728 cells / 12,714 µm² (Yosys Sky130) for both ops | **IMPL** block, verified standalone (`tb_sfu` PASS); **not yet instantiated** in `wgp`/`simd32`, so no instruction executes it | `rtl/sfu.v`, `syn/sfu/`, `scripts/check_sfu.sh`; contract in §3.1 |
| **Softmax engine** — stable row-wise | Serialized LDS engine: max pass, SFU exp2 pass, sum, one divide, normalize pass | 4 LDS passes, one 16-bit element at a time; 5,622 cells / 39,035 µm², 304 `dfxtp` | **IMPL and wired**: `S_SOFTMAX` scalar command, WGP arbitration + LDS scalar port; full WGP path PASS (`tb_wgp_softmax`) | `rtl/softmax_engine.v`, `rtl/wgp.v`, `rtl/simd32.v`, `tb/tb_wgp_softmax.v`, `syn/softmax/` |
| Lane reduction network | wave32 all-reduce (max/add) used by Softmax | 5 rounds via an LDS butterfly (`V_LDS_LD_IDX`); no dedicated hardware | **SPEC** (software sequence) | `doc/OPERATORS.md` §4.4 |
| FP16/BF16 datapath | F16 vector ALU and FP16 matrix tile | Model: reconfigurable 16x16x16 tile, `M*N*K/128 + 8` cycles; RTL: none | **MODEL** (`sim/m1_sim.hpp` `wmma_f16`) / **TARGET** in RTL — opcodes 0x2F, 0x34–0x37 are reserved and decode as no-ops | `sim/`, `spec/ISA.md`; `spec/FRD.md` FR-010 |

### 3.1 SFU contract (IMPL block, verified)

`rtl/sfu.v` is a **serialized 16-bit fixed-point** unit, not a 32-lane FP32
unit. One command is accepted per 5 cycles (4-cycle latency) on a 16-bit port
with a `start`/`busy` valid-ready handshake and a one-cycle `done` pulse:

| Op | Format | Range | Accuracy, every input code (measured) |
|---|---|---|---|
| `exp2` | signed Q4.12 in → unsigned Q0.12 out, saturated | `x ∈ [-8, +8)`, `y ∈ [0, 4095/4096]` | max abs error **3.53e-4** (limit 2e-3) |
| `rcp` | unsigned Q1.15 in → unsigned Q1.15 out, saturated | `x ∈ [0.5, 2.0]` | max rel error **2.51e-4** (limit 1e-3) |

Evidence: `tb/tb_sfu.v` sweeps every input code and checks the handshake,
`done`, latency and reset — **PASS** (`scripts/check_sfu.sh`); Yosys/Sky130
synthesis is 1,728 cells / 12,714 µm² (`syn/sfu/`). **Gaps:** the block is not
instantiated in `wgp`/`simd32`, so no ISA instruction reaches it; there is no
`tanh`, no FP32 form, no 32-lane vector form, and no opcode allocated for any
of them. Softmax therefore uses the SFU through the C++ model
(`m1::sfu_exp2_row`/`sfu_rcp_row`), the `softmax_engine` block wired through
`S_SOFTMAX` in the WGP, or the LDS-LUT sequence of
`doc/OPERATORS.md` §4.

## 4. Operator support

| Operator | Required M1 datapaths | Status on M1 | Contract |
|---|---|---|---|
| **GEMM, MXFP4 → exact int32** | WMMA + TDM + LDS + SIMD epilogue | **IMPL**: one 16x16x32 tile in RTL; 64x64x64 on the model is bit-exact (`max_err=0`), 512 cycles | `doc/OPERATORS.md` §2 |
| **GEMM, FP16/BF16 → FP32 accumulate** | model FP16 tile (`wmma_f16`) | **MODEL** only; no FP16 datapath in RTL, so it cannot run on `rtl/` | `doc/OPERATORS.md` §3 |
| **Softmax, stable row-wise** | model: FP16 rows + `sfu_exp2_row`; RTL: `softmax_engine` via `S_SOFTMAX` in WGP | **IMPL on the model** (8x128, row-sum err 1.716e-3 vs tol 2e-3, 3,168 cycles); **RTL full-WGP path PASS** (32 Q4.12, row sums 4064/4090) | `doc/OPERATORS.md` §4 |
| **FlashAttention** (`QK^T` → softmax → `PV`) | model FP16 tiles + softmax row + SFU | **IMPL on the model** (seq=32, dim=16, causal, err 1.004e-3 vs tol 2e-2, 3,744 cycles); no RTL FP16 path | `doc/OPERATORS.md` §5 |
| Elementwise / GEMV / reduction | SIMD32 VALU, `V_DOT8`/`V_DOT4` | **IMPL** | `spec/ISA.md` vector table |
| Convolution, pooling | Lowered to GEMM by software (im2col / direct) | **SPEC** via GEMM; **no dedicated conv block** | — |
| LayerNorm / RMSNorm | Needs `rsqrt` and FP32 reductions | **TARGET** — blocked: the SFU has only `exp2`/`rcp`, and there is no FP32 ALU | — |
| Any FP64 / TF32 / FP8 operator | — | **OUT** | — |

## 5. Memory hierarchy

| Level | Size | Latency | Bandwidth | Ports | Visibility |
|---|---|---|---|---|---|
| VGPR | 16 x 32 lanes x 32 b = 2 KB per SIMD | 1 cycle (write-back in EXEC) | 32 lanes/access | read/write per lane; no cross-lane | per-wave |
| SGPR / VCC / SCC / EXEC | 32 x 32 b + mask state per wave | 1 cycle | uniform | scalar | per-wave |
| LDS | 4 KB = 32 banks x 32 rows x 32 b | 1 cycle registered | 32 words/cycle = 12.8 GB/s aggregate (1 grant/cycle) | 2 lane (32 addr each) + 1 linear (32-word row) | per-WGP |
| I$ | 1 KB = 256 x 32 b | 1 cycle | 1 word/port/cycle, 2 ports | 2 read, 1 write (CP) | per-WGP |
| Global memory | system-defined | AXI latency + 128 B block | 1.6 GB/s peak, 1 outstanding | AXI4 128-bit INCR8 | chip-wide, flat 32-bit |
| Host CSR window | 4 KB (12 registers) | AXI4-Lite | 32-bit | 1 slave | host |

**Absent by design:** L1/L2/L3 data caches, texture/constant caches, 320 KB
LDS, 64 KB I$, MMU/page tables, SVM, atomics, coherent host mappings,
scratch/private memory (there is no per-thread spill space), and any
graphics-specific memory object or tiling format.

## 6. Data types

| Format | Bits | Where | Status | Notes |
|---|---|---|---|---|
| MXFP4 (E2M1) with E8M0 block scale | 4 + 8 (scale, software) | WMMA A/B, `V_DOT8` | **IMPL** (operands); scale in software | Decoded to the exact integer sequence `{0,1,2,3,4,6,8,12}` (±), i.e. x2 of the nominal magnitudes; product is x4 and is removed by the consumer |
| INT4 (two's complement) | 4 | `V_DOT8_I32_IU4` raw path | IMPL | Same datapath as MXFP4 raw nibbles |
| INT8 (two's complement) | 8 | `V_DOT4_I32_IU8` | IMPL | Peak 51.2 GOPS, sustained 12.8 GOPS |
| INT32 | 32 | ALU, accumulators, addressing | IMPL | Exact, wrap-around add; no saturation |
| FP16 (IEEE binary16) | 16 | Model FP16 tile + softmax rows | **MODEL** (`sim/`); **TARGET** in RTL (opcodes reserved) | Model rounds to nearest; no RTL datapath exists |
| BF16 | 16 | Model FP16 tile (same path) | **TARGET** | Same status as FP16; no BF16 rounding mode in the model |
| FP32 | 32 | Epilogue on the host; model internals | **OUT on die** | No FP32 ALU or FP32 SFU; the SFU is 16-bit fixed point |
| FP64 / TF32 / FP8 / FP6 | — | — | **OUT** | — |

Numeric rules that are frozen today:

* The integer path is **exact**: no rounding, no saturation, no NaN/Inf, no
  flush-to-zero. `int32` wrap-around is two's complement.
* A K=32 MXFP4 dot product cannot overflow int32: `|C| ≤ 32 x 12 x 12 = 4608`.
* Block scaling (E8M0, `2^(e-127)`) and the x1/4 rescale are **software**
  operations applied outside the MAC tree; the hardware never sees an exponent.
* Mixed-format arithmetic (e.g. FP4 x FP16) is **OUT**; there is no format
  promotion in hardware.

## 7. Block diagram (AI-only; no graphics blocks)

```
                    +-------------------------------------------------------------+
   clk, rst_n ----> | cdna5_m1_top                                                |
   AXI4-Lite  ----> | axi_lite_slave --> command_processor -------------> irq ----+--> host
   (host CSRs)      |                    | 12 CSRs, launch FSM                  |
                    |                    | 1 KB I$ preload (8 x 128 B)          |
                    |                    | 64-bit cycle counter                 |
                    |                    v wgp_start / grid / wg_size           |
   AXI4 128-bit <-->|  +------------------------------------------------------+  |
   (global memory)  |  | wgp: 1 CU, 2 x SIMD32 (wave32, 32 lanes, 16 VGPR/l)  |  |
                    |  |   +----------------+    +----------------+            |  |
                    |  |   | SIMD32 #0      |    | SIMD32 #1      |  I$ 1 KB   |  |
                    |  |   | SALU 32 SGPR   |    | SALU 32 SGPR   |  256x32,2R |  |
                    |  |   | VALU 32 lanes  |    | VALU 32 lanes  |  preload   |  |
                    |  |   | DOT8 FP4       |    | DOT8 FP4       |  only      |  |
                    |  |   | DOT4 INT8      |    | DOT4 INT8      |            |  |
                    |  |   +-------+--------+    +-------+--------+            |  |
                    |  |           | lane port 0          | lane port 1        |  |
                    |  |   +-------v----------------------v-------+            |  |
                    |  |   | LDS 4 KB, 32 banks x 32 rows x 32 b |<--+        |  |
                    |  |   | 2 lane ports + 1 linear 32-word port|   |        |  |
                    |  |   +------------------^------------------+   |        |  |
                    |  |            +---------+---------+    +--------+-----+  |  |
                    |  |            | WMMA 16x16x32   |    | SFU 16b IMPL |  |  |
                    |  |            | 512 FP4 MAC/cyc |    | exp2/rcp/tanh|  |  |
                    |  |            | int32 C         |    | 1 op/lane/cyc|  |  |
                    |  |            +-----------------+    +--------------+  |  |
                    |  |            +-----------------+                       |  |
                    |  |            | TDM 1-D         | 128 B blocks          |  |
                    |  |            +--------+--------+                       |  |
                    |  +---------------------+------------------------------+  |
                    |        mem_if: 128 B blocks, SIMD0 > SIMD1 > TDM        |
                    |  +---------------------v------------------------------+  |
                    |  | axi_master 128-bit, INCR8, one outstanding         |  |
                    |  +----------------------------------------------------+  |
                    +-------------------------------------------------------------+
   NOT PRESENT: rasterizer/ROP/depth-stencil, texture units, shader export,
                display controller/PHYs, video decode/encode (JPEG, HEVC,
                AVC, VP9, AV1), audio, ray tracing, GPU MMU, graphics queues.
```

## 8. Non-goals

1. **No graphics, video, display, raster, texture, or codec function** — at
   any level (block, ISA, state, pin, driver, model). This is the defining
   scope constraint, not a staging decision.
2. **No binary compatibility with CDNA5 `gfx` hardware.** The 32-bit encoding
   is a design contract, not an ABI (`spec/ISA.md`). See `spec/ROCM_COMPAT.md`
   for what source and runtime compatibility does and does not mean.
3. **No full CDNA5 WGP.** One CU, not two; one wave per SIMD, not 64 resident
   waves; 16 VGPR/lane, not 1024; no multi-wave latency hiding.
4. **No cache hierarchy, no L2, no MMU, no SVM, no atomics, no host
   coherence.** Data movement is explicit (TDM, `V_MEM_*`, `hipMemcpy`).
5. **No 5-D TDM**, no descriptors with bounds checks, no multicast, no
   LDS→DRAM direction.
6. **No hardware MXFP4 block scale** (E8M0 is software) and **no hardware
   accumulation across K** (`C = A*B` per operation; the epilogue adds).
7. **No F16/FP32 arithmetic in RTL v1**; the FP16/BF16 path is a target, not
   a claim.
8. **No preemption, no concurrent kernels, no multi-queue, no multi-GPU, no
   IPC, no cooperative launch, no device-side malloc.**
9. **No RAS features**: no ECC, no parity, no scrub, no error containment
   beyond `STATUS.ERROR` on an LDS bank conflict.
10. **No silicon claim.** Synthesis and P&R are incomplete; this document
    quotes only specifications and RTL-simulation results, never measured
    silicon PPA or sustained hardware throughput.
11. **Not a production CDNA5 replacement** and not a superset of any shipping
    AMD part; it is a scaled, verifiable bring-up of the AI subset.

## 9. How the scope is enforced

| Check | Evidence today | Status |
|---|---|---|
| No graphics/video pins | 581 functional bits: `clk`, `rst_n`, `irq`, AXI4 master (426), AXI4-Lite (152) | IMPL |
| No graphics CSR state | 12 registers at `0x00–0x30`, `ID = "CDN5"` (`spec/SAD.md` §7) | IMPL |
| No graphics opcodes | ISA decoder covers 0x00–0x17 and 0x20–0x3A; unallocated space decodes as NOP with no side effects | IMPL (no trap — see `spec/FRD.md` FR-019) |
| No graphics/media area | Planning budget ~340 k cells: 2x SIMD32 ~180 k, WMMA ~90 k, LDS ~30 k, TDM/I$/CP ~25 k, AXI/CSR ~15 k | Planned budget, not signoff |
| No graphics verification | 3 self-checking benches: `tb_wmma`, `tb_top` (vecadd), `tb_wmma_top` (TDM→LDS→WMMA→AXI4) | 3/3 PASS |
| AI operator coverage | `doc/OPERATORS.md` contracts; FP4 GEMM bit-exact on the model, Softmax/FlashAttention pass on the model, only the FP4 tile is RTL-simulated | Partial (RTL) / Model (all three) |

## 10. Change control

Adding any graphics, video, display, texture, or codec function — including a
single opcode or CSR — requires (a) a PRD change in the CoreSmith project DB,
(b) a revision of this document, and (c) an ISA/spec revision, because the
encoding is frozen for RTL (`spec/SAD.md` §12). Extending an AI datapath that
already appears here (SFU `tanh`/FP32 forms, FP16 in RTL) requires only the RTL
work and its verification evidence, but the status columns in §3, §4 and §6
must be updated in the same change.
