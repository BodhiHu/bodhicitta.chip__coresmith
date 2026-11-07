# CDNA5-M1 — Product Requirements Document

| Field | Value |
|---|---|
| Product | CDNA5-M1, 0.1 TFLOP/s MXFP4 accelerator |
| Document | PRD, version 0.1 (architecture baseline) |
| Date | 2026-11-07 |
| Status | Approved as the architecture baseline; RTL bring-up exists, P&R and silicon are pending |
| Related | `spec/ISA.md`, `spec/UARCH.md`, `spec/FRD.md`, `spec/SAD.md` |

## 1. Purpose

This PRD defines *what* the CDNA5-M1 must be and *why*. It fixes the product
positioning, the headline performance target, the interface set, the
technology, and the deliberately narrow scope of the first silicon
bring-up. Numeric, testable requirements live in `spec/FRD.md`; the structural
answer lives in `spec/SAD.md`.

## 2. Product vision

**Bring a real CDNA5 execution model to an open, reproducible Sky130
accelerator slice — one work-group processor, one compute unit, two SIMD32s,
and a 16x16x32 MXFP4 matrix core that lands 0.1 TFLOP/s at 100 MHz.**

CDNA5 is AMD's datacenter AI architecture: wave32 execution, SGPR/VGPR split,
EXEC-masked vector ALU, LDS scratchpad, WMMA matrix cores, and a Tensor Data
Mover. Today, programming that model requires a datacenter GPU. The CDNA5-M1
makes the *same program shape* executable in Verilog-2005 RTL on the open
SkyWater Sky130 PDK, with one CU (2 of a WGP's 4 SIMD32s) and 1/80 of a full
WGP's LDS capacity (4 KB vs 320 KB), using free EDA tools (Icarus Verilog,
Yosys, OpenROAD).

The M1 is a **bring-up vehicle**, not a datacenter product and not a claim of
binary compatibility with gfx-class CDNA5 hardware. Its value is that the
whole stack — ISA contract, assembler, kernels, RTL, DV, synthesis — is small
enough to be audited, simulated, and taped out, while preserving the
architectural invariants (wave32, EXEC mask, VGPR/SGPR split, LDS bank
structure, WMMA semantics, TDM staging) that a scaled CDNA5-derived design
must get right.

## 3. Target market and users

| Segment | Need | How the M1 serves it |
|---|---|---|
| Open-silicon / academic tape-out | A small, complete, synthesizable AI accelerator with open PDK | Single-clock Verilog-2005 core, ~340 k cells, Sky130 |
| AI accelerator bring-up teams | De-risk wave32 + matrix-core + DMA dataflow before scaling | 1 CU, 2 SIMD32, WMMA, TDM, AXI4, CSR launch |
| MXFP4 numerics research | Experiment with FP4 quantization/block scaling on real RTL | MXFP4 E2M1 decode in RTL; exact int32 accumulation; software E8M0 scaling |
| Compiler / ISA tooling | A frozen, documented target for assembler and codegen work | Frozen 32-bit encoding, `sw/asm.py`, self-checking kernels |
| Edge inference prototyping | Low-power, low-frequency, deterministic accelerator model | 100 MHz, ≤1 W target, small LDS, AXI4 128-bit memory |

Non-goals: datacenter training/inference, HBM, multi-WGP scaling, real
CDNA5 binary compatibility, or replacing any AMD product.

## 4. Product overview

The CDNA5-M1 is one **WGP** containing one **CU** (half a CDNA5 WGP):

* **2 x SIMD32**, each executing one wave32 at a time, EXEC-masked, with a
  private SGPR file (32 x 32-bit), VGPR file (16 per lane), VCC and SCC.
* **4 KB LDS** organised as 32 banks x 32 rows x 32-bit, with two lane ports
  (one per SIMD) and one linear port (WMMA, TDM). Conflict-free patterns only.
* **WMMA matrix core**: fixed `C[16][16] (int32) = A[16][32] (MXFP4) x B[32][16] (MXFP4)`,
  512 FP4 MAC/cycle, 16-cycle compute phase, 256 int32 C words in LDS.
* **TDM**: 1-D contiguous tensor copies from 128-byte-aligned global memory to
  32-word-aligned LDS, in 32-word units (bring-up subset of the CDNA5 5-D TDM).
* **1 KB instruction RAM** (256 x 32-bit, two read ports) preloaded by the
  command processor from `KERNEL_PC`; production CDNA5 has a 64 KB I$ per WGP.
* **Command processor (CP)**: AXI4-Lite CSR slave, launch sequencer, I$
  preload, STATUS/IRQ generation, 64-bit cycle counter.
* **AXI4 128-bit master**: INCR8 bursts, one outstanding transaction,
  1.6 GB/s peak at 100 MHz.

### 4.1 CDNA5 derivation

| Property | CDNA5 WGP (reference) | CDNA5-M1 | Rationale |
|---|---|---|---|
| SIMD32 per WGP | 4 (2 CUs) | 2 (1 CU) | Smallest slice that keeps the WGP hierarchy |
| Wave size | 32 | 32 | Invariant |
| Resident waves per SIMD | up to 16 | 1 | Bring-up scheduler simplicity |
| VGPRs per lane | up to 1024 | 16 | Area; parameterisable |
| SGPRs per wave | 128 | 32 | Area; parameterisable |
| LDS per WGP | 320 KB | 4 KB | Bring-up SRAM budget |
| I$ per WGP | 64 KB | 1 KB preload | No cache/miss handling |
| TDM | 5-D descriptors, bounds checks, multicast | 1-D contiguous copy | Bring-up data movement only |
| Matrix core | WMMA 16x16xK, F16/BF16/FP8/FP4 | fixed 16x16x32 MXFP4, int32 C | Target headline format |
| ISA encoding | gfx-class | fixed 32-bit subset | Not binary compatible |

The M1 preserves the CDNA5 *execution* concepts it derives from: wave32, one
PC per wave, EXEC mask, SALU/VALU split, SGPR/VGPR split, LDS bank structure,
WGP-level matrix core, TDM-style bulk staging, and a command-processor launch
path. It scales down the counts and replaces caches/dispatch with a CSR-driven
preload model.

## 5. Headline targets

All performance figures are **specified** at 100 MHz unless labelled otherwise.
Status: S = specified, M = measured (RTL simulation), P = planned (not yet
measured).

| ID | Metric | Target | Derivation | Status |
|---|---|---|---|---|
| T-01 | Clock | 100 MHz (10.0 ns) | Sky130 sign-off target | S |
| T-02 | Matrix MXFP4 peak | **102.4 GFLOP/s** (0.1024 TFLOP/s) | 8192 MAC / 16 cyc = 512 MAC/cyc; 2 FLOP/MAC | S |
| T-03 | Vector FP4 peak (`V_DOT8`) | **102.4 GFLOP/s** | 2 SIMD x 32 lanes x 8 MAC/cyc | S |
| T-04 | INT8 peak (`V_DOT4`) | **51.2 GOPS** | 2 SIMD x 32 lanes x 4 MAC/cyc; 2 ops/MAC | S |
| T-05 | Matrix sustained (single core) | 51.2 GFLOP/s | 8192 MAC / 32-cycle WMMA cadence | P |
| T-06 | AXI4 memory bandwidth | 1.6 GB/s peak | 128-bit x 100 MHz | S |
| T-07 | LDS bandwidth | 12.8 GB/s | 32 words/cycle x 4 B | S |
| T-08 | I$ fetch bandwidth | 400 MB/s per SIMD port | 32-bit x 100 MHz | S |
| T-09 | Core area | ≤ 6.0 mm² | ~340 k cells, Sky130 | P |
| T-10 | Die area | ≤ 16 mm² (4.0 x 4.0 mm) | Pad-limited bring-up die | P |
| T-11 | Active power | ≤ 1.0 W at 1.8 V, 100 MHz, TT/25C | OpenROAD/OpenSTA estimate | P |
| T-12 | Standby power | ≤ 50 mW | Clock-gated idle | P |

**Peak vs sustained.** The 0.1 TFLOP/s headline is the peak rate of the
execution window: 512 FP4 MAC/cycle in the WMMA COMPUTE phase, or one
`V_DOT8` per EXEC cycle in the vector path. In the bring-up RTL the WMMA
load/store phases are serialised (32-cycle cadence, ~51.2 GFLOP/s for one
core) and the SIMD scalar pipeline issues one instruction per 4 cycles, so
sustained vector throughput is ~25.6 GFLOP/s. These sustained numbers are
specified and tracked in the FRD; they are not claimed as headline numbers.

## 6. Interfaces

| Interface | Protocol | Width / rate | Role |
|---|---|---|---|
| `clk`, `rst_n` | Single clock, active-low **synchronous** reset | 100 MHz | Whole chip |
| Host control (`s_axil_*`) | AXI4-Lite slave | 32-bit data/address, 4 KB CSR window, full-word writes, OKAY responses | CSR programming and launch |
| Global memory (`m_axi_*`) | AXI4 master | 128-bit data, 32-bit address, INCR8 (128 B), one outstanding | Kernel image, data, results |
| `irq` | Level interrupt | Held until next START | Completion notification |

There is no second clock, no asynchronous reset, no tri-state, and no
external debug port in this phase.

## 7. Use cases

### UC-1 — Vector add (measured)
`C[i] = A[i] + B[i]` over 32 lanes: host writes CSRs, starts the kernel; the
wave loads A and B as 128-byte blocks (`V_MEM_LD`), adds (`V_ADD_I32`), and
stores C (`V_MEM_ST`). Acceptance: all 32 results correct, STATUS.DONE set,
IRQ seen. Measured in RTL simulation: PASS.

### UC-2 — MXFP4 matrix multiply (measured)
`C[16][16] = A[16][32] x B[32][16]` with MXFP4 E2M1 A/B: two `S_TDM_COPY`
descriptors stage 64-word A and B tiles into LDS; `S_WMMA` computes 256 int32
C words (A=1.0, B=2.0, K=32 => C=256); the wave copies C back with
`V_LDS_LD` / `V_MEM_ST`; software applies the E8M0 block scale and the
x4 integer-pipeline rescale. Acceptance: all 256 C words correct. Measured:
PASS (unit `tb_wmma` and full-chip `tb_wmma_top`).

### UC-3 — TDM tiling (measured as part of UC-2; multi-tile planned)
TDM stages 128-byte-aligned tensor blocks into 32-word-aligned LDS rows, so a
16x16x32 tile (A 512 B + B 512 B + C 1 KB = 2 KB) fits in the 4 KB LDS. A
production kernel would loop over K and tiles; the M1 brings up one tile.

## 8. Host programming model

1. Host loads the kernel image and data into global memory (AXI4 master target).
2. Host writes `KERNEL_PC`, `ARG_PTR`, `GRID_X`, `WG_SIZE`, `IRQ_EN`.
3. Host writes `CONTROL.START`; the CP preloads 1 KB of instructions into the
   I$, then launches workgroups.
4. Waves seed `s0=wg_id`, `s1=arg_ptr`, `s2=lds_base(0)`, `s3=wg_size`,
   `s4=lane_base(0)`, `PC=0`, `EXEC=(1<<wg_size)-1`, and run to `S_ENDPGM`.
5. CP sets `STATUS.DONE`, clears `BUSY`, increments `WAVE_DONE`, and raises
   `irq` if enabled.

Software deliverables: assembler (`sw/asm.py`), kernel images (`sw/*.s`,
`sw/*.hex`), and reference kernels. No C compiler, runtime, or OS is in scope.

## 9. Power, area, and technology goals

* PDK: SkyWater `sky130A`, standard-cell library `sky130_fd_sc_hd`,
  TT/25 C/1.80 V for characterisation.
* Tools: Icarus Verilog (functional DV), Yosys (synthesis), OpenROAD/OpenSTA
  (P&R, timing, power), Magic/netgen (DRC/LVS).
* Core area budget: ~340 k cells (SIMD 180 k, WMMA 90 k, LDS 30 k flops,
  TDM/I$/CP 25 k, AXI/CSR 15 k); target ≤ 6.0 mm².
* Die: ≤ 4.0 x 4.0 mm including pad ring (≤ 16 mm²).
* Power: ≤ 1.0 W active at 1.8 V/100 MHz, ≤ 50 mW standby.
* All area/power values are **planned**; synthesis is in progress under `syn/`
  with no completed area report. No silicon data exists and none is claimed.

## 10. Deliverables and release criteria

| Milestone | Deliverable | Exit criterion | State |
|---|---|---|---|
| M0 | ISA, UARCH, PRD, FRD, SAD | Documents internally consistent | Done (this baseline) |
| M1 | `chip_top` RTL + assembler + 3 self-checking tests | All tests PASS | Done (measured) |
| M2 | Expanded DV: grid=8, wg_size<32, EXEC masking, error paths, AXI backpressure | Coverage targets met | Planned |
| M3 | Full-chip synthesis + STA | No latches; 100 MHz WNS ≥ 0 | In progress |
| M4 | Place-and-route + DRC/LVS | Clean GDS | Planned |
| M5 | Silicon | — | Out of scope for this phase |

Release criteria for M1: FR-001..FR-025 must-pass requirements satisfied as
specified in the FRD; PERF/TIME/AREA/PWR items either measured or explicitly
carrying a `[P]` plan with a measurement method.

## 11. Out of scope and known deviations

| ID | Out of scope / deviation | Impact |
|---|---|---|
| OOS-1 | F16 and FP32 vector arithmetic | Reserved; **not implemented** in bring-up RTL. Only integer/FP4 vector ops are usable. |
| OOS-2 | Per-lane coalesced VMEM, atomics, caches, L2 | Only 128-byte block VMEM and a 1 KB I$ preload exist |
| OOS-3 | LDS conflict replay/serialisation | Conflicts abort the wave with `ERROR` |
| OOS-4 | 5-D TDM, bounds checks, multicast, LDS<->DRAM direct | 1-D contiguous copies only, software-checked |
| OOS-5 | Multiple resident waves per SIMD, occupancy, barriers across waves | One wave per SIMD; `S_BARRIER` is a NOP |
| OOS-6 | Hardware MXFP4 block scale (E8M0) | Not implemented; software post-scales |
| OOS-7 | CDNA5 binary compatibility | Frozen custom 32-bit encoding |
| OOS-8 | WMMA accumulate (`C += A*B`) | RTL computes `C = A*B`; software adds prior C |
| OOS-9 | WMMA VGPR operands | M1 stages A/B/C through LDS |
| OOS-10 | Silicon performance/power | None measured; only RTL simulation exists |

## 12. Assumptions and risks

* **Assumption:** a 512-MAC combinational FP4 multiply-accumulate tree closes
  at 100 MHz in `sky130_fd_sc_hd`. Risk: high; timing closure is unproven and
  may force a pipelined WMMA (area/perf trade). Owner: backend.
* **Risk:** the ~340 k-cell budget is a planning estimate; full-chip synthesis
  has not produced an area/timing report yet.
* **Risk:** 4 KB LDS as flip-flops is area-expensive; early synthesis runs
  suggest the 3-port register array may expand well beyond the 30 k-flop
  budget, so an SRAM macro is the fallback for a production build.
* **Risk:** F16/FP32 being reserved limits numerics bring-up; a future
  revision may add packed F16 if area allows.
* **Risk:** the 1-D TDM subset does not exercise 5-D tiling; a multi-tile
  kernel is needed before claiming TDM scalability.
* **Constraint:** Verilog-2005 only; no SystemVerilog constructs in RTL.

## 13. Glossary

| Term | Meaning |
|---|---|
| WGP | Work-Group Processor: 2 CUs, 4 SIMD32 in full CDNA5; 1 CU here |
| CU | Compute Unit: half a WGP; 2 SIMD32 here |
| Wave | 32 work-items executing one instruction stream with one PC |
| EXEC | 32-bit per-lane execution mask |
| VGPR / SGPR | Vector (per-lane) / scalar (per-wave) general-purpose registers |
| LDS | Local Data Share: 4 KB banked scratchpad |
| WMMA | Wave Matrix Multiply-Accumulate; here fixed 16x16x32 MXFP4 |
| TDM | Tensor Data Mover; here 1-D contiguous copy engine |
| MXFP4 | OCP microscaling FP4, E2M1 element format with E8M0 block scale |
| GFLOP/s | 10^9 floating-point operations per second (2 per MAC) |
| GOPS | 10^9 integer operations per second (2 per MAC) |
