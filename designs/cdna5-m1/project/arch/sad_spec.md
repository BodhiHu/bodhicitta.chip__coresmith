# SAD — CDNA5-M1 0.1 TFLOP/s MXFP4 AI Accelerator on Sky130

| Field | Value |
|---|---|
| Product | CDNA5-M1, 0.1 TFLOP/s MXFP4 accelerator (1 WGP / 1 CU / 2x SIMD32) |
| Document | System Architecture Document, revision 1.0 |
| Status | Architecture baseline; RTL bring-up exists, full-chip P&R and silicon are pending |
| Technology | SkyWater Sky130A, `sky130_fd_sc_hd`, `tt_025C_1v80`, 1.8 V, Yosys/OpenROAD |
| Deliverable class | Synthesizable Verilog-2005 soft IP (`chip_top`), verified by full-chip simulation |
| Authoritative inputs | PRD rev 1.0 (project DB), FRD rev 1.0 (project DB), `spec/ISA.md`, `spec/UARCH.md` |

**Requirement authority.** The PRD and FRD records in the CoreSmith project DB are the contract for this document. Every hard number below is cited with its originating requirement. Where the in-repo legacy prose (`spec/SAD.md`, `doc/PERFORMANCE.md`, README) conflicts with the PRD, the PRD wins; the known conflicts and their resolutions are recorded in "Requirement Corrections and Interpretations" under Architecture Decisions. Per-block cell and power splits in this document are **advisory planning estimates**, not hard constraints; the hard constraints are 500,000 logic cells, 4.0–8.0 mm² die, and 2 W (CON-4).

## System Overview

CDNA5-M1 is a single-clock, single-supply accelerator subsystem that preserves the CDNA5 execution model — wave32, one PC per wave, a 32-bit EXEC mask, SALU/VGPR split, SGPR/VGPR split, a banked Local Data Share (LDS), a WGP-level matrix core, and TDM-style bulk staging — while scaling the machine down to one Work-Group Processor (WGP) with one Compute Unit (CU), two SIMD32 units, a 4 KB LDS, a 1 KB host-preloaded instruction RAM, a 1-D Tensor Data Mover (TDM), and one WGP-shared 16x16x32 MXFP4 matrix core (WMMA). The chip is a Verilog-2005 design on the SkyWater Sky130 high-density library, clocked at 100 MHz from a single clock with an active-low synchronous reset, and attaches to a host through an AXI4-Lite CSR slave and to global memory through a 128-bit AXI4 master. The 0.1 TFLOP/s headline is the matrix datapath peak: 512 MXFP4 MAC/cycle x 2 FLOP/MAC x 100 MHz = 102.4 GFLOP/s (1.024e11 FLOP/s, FR-PERF-1), with one 16x16x32 MFMA issued every 16 cycles (FR-CORE-3, FR-PERF-1).

The architecture is **LDS-centric and cacheless**. The host preloads a 1 KB kernel image; the command processor (CP) fetches it into the instruction RAM; the TDM stages packed A/B tiles from global memory into LDS; the WGP-shared matrix core reads A/B from LDS and writes the int32 C tile back to LDS; the SIMD32 vector path reads results from LDS and stores them to global memory through AXI4. The central architectural problem is the PRD's sustained-throughput bound (FR-PERF-2: at least 90% of peak, i.e. >=92.16 GFLOP/s, with A/B operands fed from LDS). The legacy RTL's serialized matrix core (load, then compute, then store) achieves roughly 44.3 GFLOP/s; this SAD therefore **re-baselines the WMMA as a pipelined core** that overlaps the C-store of one operation with the operand-read and compute of the next, using ping-pong accumulator banks, so that the steady-state issue cadence is 16 cycles and the sustained bound is met. The 4 KB LDS, the 32-word linear port, and the 128-bit AXI4 feed make that schedule feasible: one MFMA consumes 128 operand words and produces 256 C words, i.e. 12 of the 16 available 32-word LDS grants per 16-cycle slot (75%), leaving 4 grants for the TDM and the SIMD lane ports. The design is a bring-up vehicle and soft-IP deliverable; it is not binary-compatible with gfx-class CDNA5 hardware.

### Block Partition

The block diagram stage must instantiate the following blocks. LDS and instruction RAM are **dedicated memory blocks** with their own ports and area budgets, not storage embedded in the WMMA, TDM, SIMD, or command processor (see Stateful Feedback S1 and S2).

| Block | Responsibility | Storage | Primary requirement owners | Advisory area estimate |
|---|---|---|---|---|
| `chip_top` | Boundary, AXI4/AXI4-Lite wiring, top memory arbiter, clock/reset distribution | — | FR-CLK-1, FR-MEM-4, FR-HOST-1 | glue |
| `axi_lite_slave` | AXI4-Lite to 32-bit CSR bridge, 4 KB window, OKAY responses | — | FR-HOST-1 | ~1 k cells |
| `command_processor` | CSR file, launch FSM, I$ preload, STATUS/IRQ, 64-bit cycle counter, WAVE_DONE accounting | CSR flops | FR-HOST-2, FR-HOST-3 | ~8 k cells |
| `axi_master` | AXI4 128-bit master, INCR8, one outstanding, 128 B block assembly | burst buffers | FR-MEM-4 | ~8 k cells |
| `mem_arb` (in `chip_top`) | Arbitration of CP preload vs WGP traffic; one outstanding transaction | grant/cooldown state | FR-MEM-4 | ~2 k cells |
| `wgp_ctrl` / `dispatch` | Workgroup dispatch, wave tracking, completion, LDS and WMMA/TDM arbitration | dispatch/mailbox flops | FR-EXEC-1, FR-EXEC-3 | ~8 k cells |
| `simd32` x2 | SALU/SGPR, VALU/VGPR, EXEC/VCC/SCC, PC, fetch/decode/execute, LDS/global/WMMA/TDM issue | VGPR/SGPR | FR-CORE-1, FR-CORE-2, FR-CORE-5 | ~180 k cells (estimate) |
| `lds` | 4 KB, 32 banks x 32 rows x 32 bits; 2 lane ports + 1 linear port; conflict detect | 32,768 flops | FR-MEM-1 | ~130–200 k cell-equivalents (excluded from logic cap) |
| `wmma` | 16x16x32 MXFP4 core, 512 MAC/cycle, 16-cycle cadence, int32 C | 2 x 256 int32 accumulator banks | FR-CORE-3, FR-CORE-4, FR-PERF-1, FR-PERF-2 | 126,245 cells measured + ~10–15 k pipelining |
| `tdm` | 1-D contiguous global-to-LDS copy, 32-word units | descriptor/beat state | FR-MEM-3 | ~4.5 k cells measured |
| `instruction_ram` (`i$`) | 1 KB = 256 x 32-bit, 2 read ports, 1 write port | 8,192 flops | FR-MEM-2 | ~30–50 k cell-equivalents (excluded from logic cap) |

The measured references from the PRD are: matrix core 126,245 cells / 1.218 mm², and TDM 10.1 mW after P&R at 100 MHz. The SIMD32, LDS, I$, CP, and AXI estimates are planning numbers and must be replaced by synthesis receipts; the design is not area-closed until then (CON-9).

### Hard Bounds and Traceability

| Bound | Value | Units | Originating requirement | Scope / note |
|---|---|---|---|---|
| Matrix peak throughput | 102.4 (1.024e11 FLOP/s) | GFLOP/s | FR-PERF-1, KPI-001 | 512 MAC/cycle x 2 FLOP/MAC x 100 MHz |
| Matrix sustained throughput | >=92.16 (9.216e10 FLOP/s) | GFLOP/s | FR-PERF-2, KPI-PERF-001, FRD PERF-002 | >=90% of peak, A/B fed from LDS |
| MFMA issue cadence | 16 | cycles/op | FR-PERF-1, PRD `mfma_cycles_per_op` | 8192 MAC per 16x16x32 operation |
| MAC rate | 512 | MAC/cycle | FR-CORE-3, FR-PERF-1 | 2 K-slices x 256 outputs |
| Clock | 100 | MHz | FR-CLK-1, CON-2 | single domain |
| LDS size / organization | 4096; 32 banks x 32 rows x 32 bits | bytes | FR-MEM-1, PRD `lds_*` | 2 lane ports + 1 linear port |
| LDS aggregate feed | 12.8 (32 words x 32 bits) | GB/s | PRD Speed & Feeds | one 32-word grant per cycle |
| Instruction RAM | 1024; 256 x 32-bit; 2 read ports | bytes | FR-MEM-2 | host-preloaded, no cache |
| AXI4 master | 128-bit data, 32-bit address, INCR8, 1 outstanding | — | FR-MEM-4 | 16 B/cycle = 12.8 Gbit/s = 1.6 GB/s |
| AXI4-Lite CSR | 32-bit data/address | — | FR-HOST-1 | 4 KB window, OKAY responses |
| Grid / workgroup | 1–8 workgroups; 1–32 work-items | — | FR-EXEC-1, PRD `max_*` | one workgroup = one wave32 |
| SIMD32 / wave | 2 SIMD32; wave32; 16 VGPR/lane; 32 SGPR/wave | — | FR-CORE-1, FR-CORE-2 | EXEC-masked |
| Logic cells | <=500,000 | cells | CON-4 | bulk LDS/I$ arrays excluded |
| Die area | 4.0–8.0 | mm² | CON-4 | including pad ring in a hardened build |
| Power | <=2 | W | CON-4 | 1.8 V, 100 MHz, tt_025C_1v80 |
| Acceptance run (informational) | 1,035 (~10.35 µs) | cycles | PRD Speed & Feeds, Q-2 | no formal latency budget fixed |

## HW/FW/SW Partitioning

There is **no programmable on-chip firmware processor**. The "command processor" is a fixed-function hardware FSM that sequences host commands; the only software is host-side and lives outside the chip. This is deliberate: at 100 MHz in 130 nm, a control CPU would add area and non-determinism for no functional benefit, and the bring-up scope requires only a single launch/complete handshake.

| Function | Implementation | Where | Rationale |
|---|---|---|---|
| MXFP4 matrix multiply-accumulate | Hardware | `wmma` | 512 MAC/cycle must be a dedicated datapath; area/power and determinism |
| Integer vector ALU, EXEC masking, VCC/SCC | Hardware | `simd32` x2 | CDNA5 execution-model invariant; 32-lane single-cycle ops |
| Instruction fetch/decode/execute, PC, branches | Hardware | `simd32` (per-wave FSM, no microcode) | One PC per wave; in-order execution; small ISA |
| Launch sequencing, I$ preload, STATUS/IRQ, cycle counter | Hardware FSM | `command_processor` | Fixed, latency-critical host handshake; no firmware image |
| Workgroup dispatch and completion | Hardware | `wgp_ctrl` | 1–8 workgroups, two SIMDs; deterministic |
| Global-to-LDS staging | Hardware | `tdm` | 1-D DMA; removes per-lane address work from the SIMDs |
| E8M0 shared block scale and x1/4 rescale | Software (host) | host + global memory | PRD FR-CORE-4 requires the scale outside the MAC tree; software cost is accepted |
| Cross-K accumulation (`C += A*B` across tiles) | Software (host/SIMD kernel) | LDS/global | Matrix core computes `C = A*B` (FR-CORE-3); accumulation is exact int32 addition outside the core |
| Operand packing and LDS layout | Software (assembler/kernel), frozen contract | host | The 16-cycle cadence depends on the packed A/B layout; the layout is specified, not discovered at runtime |
| LDS double-buffer scheduling | Software descriptor bases; hardware pipeline | kernel + `wmma` | Software picks A/B banks; the core pipelines reads/stores |
| Host polling / IRQ handling | Software | host | No runtime/OS in scope |

**Why this split.** The matrix and vector arithmetic is the only work that must run at wire speed; it is hardware. Everything that is control, scaling, tiling, or numerics policy is software because it changes per kernel and would otherwise bake policy into silicon. The TDM and CP are hardware because they are fixed, small, and sit on the critical launch/data path. F16/FP32 vector arithmetic is **not implemented** (CON-7, FR-CORE-5); reserving those opcodes keeps the VALU area bounded and the ISA frozen.

## System Flows

### Flow 1 — Host launch and instruction preload (AXI4-Lite -> CP -> AXI4 -> I$)

1. Host software places the 1 KB kernel image in global memory at `KERNEL_PC` (128-byte aligned) and the argument block at `ARG_PTR`.
2. Host writes `KERNEL_PC`, `ARG_PTR`, `GRID_X`, `GRID_Y` (=1), `GRID_Z` (=1), `WG_SIZE`, and `IRQ_EN` over AXI4-Lite, full-word writes only.
3. Host writes `CONTROL.START = 1`. The CP latches all launch parameters at this edge (FR-HOST-3), sets `STATUS.BUSY = 1` and `STATUS.DONE = 0`, and ignores further START writes while busy.
4. The CP issues eight AXI4 INCR8 reads from `KERNEL_PC` (8 x 128 B = 1 KB) through `mem_arb` and `axi_master`. Each 128 B burst is assembled into 32 words and written into `instruction_ram` (256 words total). No host-visible I$ port is required; the 11-register CSR map is unchanged.
5. The CP pulses `wgp_start` with `grid`, `wg_size`, and `arg_ptr`.
6. `wgp_ctrl` sets `pending = GRID_X` and dispatches workgroup 0 to SIMD0, then workgroup 1 to SIMD1 when free. Each wave seeds `s0=wg_id`, `s1=arg_ptr`, `s2=lds_base=0`, `s3=wg_size`, `s4=lane_base=0`, `PC=0`, and `EXEC=(1<<WG_SIZE)-1` (FR-EXEC-1).
7. Each SIMD fetches its first instruction from its own I$ read port and begins execution. The two read ports are independent, so both SIMDs may fetch in the same cycle.

Timing note: the I$ preload is 64 AXI beats; at the 16 B/cycle AXI ceiling it is at least 64 cycles of data plus arbitration and latency. No host-visible latency budget is fixed (Q-2); this is an architectural, not contractual, number.

### Flow 2 — TDM staging: global memory -> LDS

1. A wave executes `S_TDM_COPY`, whose descriptor (in SGPRs) gives the source global byte address, the destination LDS word address, and the word count (`len`, a multiple of 32 and <=256).
2. The TDM requests the LDS linear port and the top memory arbiter. The source must be 128-byte aligned; the LDS destination must be 32-word aligned (FR-MEM-3).
3. For each 32-word chunk the TDM issues one 128-byte AXI4 INCR8 read (8 beats x 16 B). The AXI master assembles the beats into 32 words; the TDM writes one LDS row (32 words, one per bank) through the linear port.
4. Steps repeat for `len/32` chunks. A 16x16x32 A tile is 256 B (2 chunks) and B is 256 B (2 chunks); the wave's TDM calls therefore move 4 chunks.
5. On completion the TDM signals the issuing wave. Because the wave is in-order, the following `S_WMMA` cannot read LDS until the TDM completion is visible; the WGP-level arbiter serializes TDM and WMMA linear-port ownership (no read/write race through the port).
6. No bounds checks, no 5-D descriptors, no multicast, and no LDS-to-DRAM direction are implemented (CON-6). Software guarantees the range and alignment.

### Flow 3 — Pipelined MXFP4 matrix compute and C writeback

1. A wave executes `S_WMMA` with a descriptor giving the A, B, and C LDS word bases (all 32-word aligned): A is 64 packed words (16x32 FP4), B is 64 packed words (32x16 FP4), C is 256 int32 words (16x16).
2. The WGP accepts one descriptor per 16-cycle slot into a one-deep descriptor queue; the SIMD may issue the next `S_WMMA` while the core is busy. The core is shared by both SIMDs and processes exactly one operation at a time (FR-CORE-3).
3. **Compute:** 16 cycles, 2 K-slices x 256 outputs per cycle = 512 MAC/cycle. The core streams A/B from LDS at 8 words/cycle average (4 grants of 32 words per slot) using the packed FP4 layout; each output accumulates 32 products exactly in int32 (FR-CORE-4).
4. **C store:** after the 16th compute cycle, the 256 int32 results are read from the accumulator bank and written to LDS in 8 grants of 32 words. In steady state this store overlaps the next operation's compute; ping-pong accumulator banks prevent the next operation from overwriting the bank being read out.
5. **Steady-state LDS budget per 16-cycle slot:** 4 operand grants + 8 C-store grants = 12 of 16 possible grants (75% of the 32-word linear port), leaving 4 grants for the TDM and lane ports. This is what makes the 16-cycle cadence and the >=90% sustained bound feasible.
6. The wave later reads C from LDS with `V_LDS_LD` (32 words per instruction) and stores it to global memory with `V_MEM_ST` (128-byte blocks). Software applies the E8M0 shared block scale and the x1/4 integer rescale outside the MAC tree (FR-CORE-4).
7. Drain: the last operation's C store takes 8 cycles after its compute; over a sequence of N operations the amortized cadence is 16 + 8/N cycles, which is within the 17.78-cycle average allowed by the 90% bound for N >= 2.

### Flow 4 — 32-lane vector add path (KPI-FUNC-001)

1. The wave executes `V_MEM_LD v0, ss0`: lane i loads word i of a 128-byte-aligned global block, so 32 lanes fill a VGPR in one instruction.
2. A second `V_MEM_LD v1, ss1` loads B.
3. `V_ADD_I32 v2, v0, v1` executes 32 lanes in one cycle; writes are EXEC-masked per lane (FR-CORE-2).
4. `V_MEM_ST ss2, v2` stores the 128-byte C block to global memory.
5. `S_ENDPGM` retires the wave. All 32 results must be exact; `STATUS.DONE=1`; the level IRQ is asserted when `IRQ_EN[0]=1`.
6. Measured reference: the existing full-chip vector-add run completes in 446 clocks from START to IRQ (485 from reset release). No latency budget is fixed (Q-2).

### Flow 5 — Completion, WAVE_DONE, STATUS, IRQ

1. `S_ENDPGM` pulses the SIMD's `done`. `wgp_ctrl` marks the SIMD free and decrements `pending`.
2. Each retired workgroup increments a completion event counter; this counter is the architectural `WAVE_DONE` value (FR-EXEC-3: completion of a workgroup is counted in WAVE_DONE).
3. When `pending == 0` and both SIMDs are idle, the WGP pulses `wgp_done`.
4. The CP sets `STATUS.DONE=1`, clears `STATUS.BUSY`, publishes the retired-workgroup count in `WAVE_DONE`, and drives `irq = IRQ_EN[0]` as a level that is held until the next START.
5. `STATUS.ERROR` is sticky until the next launch. An LDS bank conflict aborts the offending wave, sets ERROR, clears BUSY, and does not assert IRQ.
6. The host polls `STATUS`/`WAVE_DONE` or takes the level IRQ, then reads `CYCLE_LO`/`CYCLE_HI` for bookkeeping. The cycle counter is free-running.

### Flow 6 — Multi-tile host loop (software recurrence)

1. Host (or the kernel) tiles a GEMM into 16x16 C tiles and K-blocks of 32.
2. TDM stages A/B for block k+1 into the alternate LDS banks while the WMMA computes block k (software-selected descriptor bases; the core pipeline overlaps the port traffic).
3. The core computes `C = A*B` per block; the kernel accumulates partial C in LDS/global with exact int32 addition and applies the E8M0 scale per 32-element block.
4. When all K-blocks for a tile are done, the SIMD reads C and stores it to global; the host reaps completion via STATUS/IRQ.
5. This loop lives in software by design: the hardware imposes no tiling policy, and the 4 KB LDS (A/B double buffer + C + scratch = 2 KB used, 2 KB free) bounds the practical tile to 16x16 (a 32x32 C tile alone would not fit).

## Stateful Feedback and Semantic Contracts

The datapath is **not** purely feed-forward. LDS and the instruction RAM are shared read/write stores with different writers and readers; the LDS port arbiter is history-dependent; and the host launch/completion handshake is a closed loop. There are no checksums, entropy state, cryptographic state, compression/decompression, or reconstruction loops in this design. The stateful elements are enumerated below; S1 and S2 are **bulk persistent stores whose writers differ from their readers** and must be dedicated memory blocks.

| ID | State | Size | Owner / updater | Consumers | Bulk store? | Tolerance |
|---|---|---|---|---|---|---|
| S1 | LDS contents | 4 KB (32,768 bits) | TDM, WMMA, SIMD32 | WMMA, SIMD32 | **Yes — dedicated `lds` block** | Exact |
| S2 | Instruction RAM | 1 KB (8,192 bits) | Command processor | SIMD0, SIMD1 | **Yes — dedicated `instruction_ram` block** | Exact |
| S3 | VGPR file | 16,384 bits per SIMD | SIMD32 | SIMD32 | Bulk, single-block owner | Exact |
| S4 | SGPR/VCC/SCC/EXEC/PC | 1,024 + wave state | SIMD32 | SIMD32 | No | Exact |
| S5 | WMMA accumulator banks / pipeline | 16,384 bits (2 x 256 x 32) | WMMA | WMMA, LDS | Bulk, single-block owner | Exact |
| S6 | TDM descriptor and beat state | few words | TDM | TDM, AXI master | No | Exact |
| S7 | AXI outstanding/ordering state | few words | `axi_master` | TDM, CP, SIMD | No | Exact |
| S8 | LDS port arbitration state | credits/priority | `wgp_ctrl` / LDS arbiter | all LDS masters | No | Exact cycle behavior / throughput bound |
| S9 | Launch, CSR, completion state | CSR flops | Command processor | Host | No | Exact |
| S10 | Grid dispatch state | few words | `wgp_ctrl` | SIMD, CP | No | Exact |
| S11 | Host software scale/accumulate loop | global memory | Host software | Host software | Off-chip | Exact integer / defined float policy |

### S1 — LDS (bulk persistent store; dedicated memory block)

- **Owns / updates / consumes.** Writers: `tdm` (A/B tiles), `wmma` (C tile), `simd32` (`V_LDS_ST`, indexed stores). Readers: `wmma` (A/B), `simd32` (`V_LDS_LD`, indexed loads). The physical array is owned by the dedicated `lds` block; no other block embeds LDS storage.
- **Semantic value to preserve.** The exact 32-bit word image at the frozen byte-address map: 32 banks x 32 rows; `bank = addr[6:2]`, `row = addr[11:7]`; the linear port addresses one 32-word row across all banks (`row = addr[9:5]`). A packed A tile is 64 words at a 32-word-aligned base; B is 64 words; C is 256 int32 words. A conflict-free lane access has 32 distinct banks. The A/B packing order and the 32-word alignment are part of the contract; changing them changes the WMMA beat schedule.
- **Golden-model trace point.** Word-exact LDS snapshots at (a) after the TDM copies A/B and before `S_WMMA`, (b) after the WMMA C store, and (c) after any SIMD LDS store. The reference model must reproduce the packed nibble order, the bank/row map, and the int32 C values.
- **Tolerance.** Exact equality. No rounding, no saturation, no denormal behavior in the LDS path.
- **Integration/validation DV.** Full-chip TDM->LDS->WMMA->AXI4 matmul with all 256 C words compared byte-exactly (KPI-CORR-001); LDS bank/row mapping test; bank-conflict test (must set `STATUS.ERROR` and abort the wave); simultaneous lane-port and linear-port arbitration test; a multi-tile double-buffer test.
- **Dedicated memory block — required.** 4 KB = 32,768 bits, writers (TDM/WMMA/SIMD) differ from readers (WMMA/SIMD), so it must be its own memory subsystem with its own area budget and request/response ports. It must **not** be embedded in the WMMA, TDM, or SIMD32. Implementation must be 32 physical banks with per-bank 32:1 read muxes; a flat 1024-word x 32-bit multi-port flop array is **rejected** (it elaborates to ~3.3M cells in the current RTL and cannot meet the 4–8 mm² die budget).

### S2 — Instruction RAM (bulk persistent store; dedicated memory block)

- **Owns / updates / consumes.** Writer: `command_processor` (8 x 128-byte preload). Readers: `simd32` #0 and `simd32` #1 fetch ports (two read ports, FR-MEM-2).
- **Semantic value to preserve.** Exactly the 256 x 32-bit image fetched from `KERNEL_PC`; word `i` of the image is I$ word `i`. The wave PC starts at word 0; branch offsets are signed 11-bit word offsets relative to the next PC (the frozen ISA). The I$ is a preload RAM, not a cache: no misses, no refills, no coherence.
- **Golden-model trace point.** The 256-word I$ image after preload, compared word-exact to the kernel image; the first-fetch PC of each wave (0) and the retired PC stream.
- **Tolerance.** Exact equality.
- **Integration/validation DV.** Preload of a full 1 KB image and execution of a kernel that exercises every instruction class; a branch-loop kernel that proves the PC/offset semantics; concurrent fetch by both SIMDs; a preload followed immediately by START (no stale words).
- **Dedicated memory block — required.** 1 KB = 8,192 bits, writer (CP) differs from readers (SIMD0/SIMD1); it must be its own memory block with a write port and two read ports. A banked register-file implementation is expected; the I$ must not be embedded in the CP or either SIMD.

### S3 — VGPR file (bulk state, single-block owner)

- **Owns / updates / consumes.** The `simd32` block owns, writes (VALU, LDS/global loads, WMMA C readback), and reads (VALU operands) its own 16 VGPRs per lane x 32 lanes x 32 bits = 16,384 bits.
- **Semantic value to preserve.** Per-lane values; writes are gated by the 32-bit EXEC mask; inactive lanes write nothing; VGPRs are undefined at wave launch and must be initialized by software before use.
- **Golden-model trace point.** The VGPR image after each vector instruction in a directed test, per lane, with the EXEC mask applied.
- **Tolerance.** Exact equality (int32 wrap for `V_ADD_I32`, low 32 bits for `V_MUL_I32`).
- **Integration/validation DV.** Directed per-opcode tests with a reference model for all EXEC masks, including EXEC=0 and partial masks; the 32-lane vector add; register read-after-write and write-after-read hazards.
- **Bulk flag.** 16 Kbit >= 2 Kbit, but the writer and reader are the same block (`simd32`). It stays inside the SIMD as its register file; it is not a cross-block store and must not be hoisted into a separate chip-level memory. Synthesis must use a per-lane register-file structure; a flat array with global write-enable expansion is a known synthesis blow-up risk.

### S4 — SGPR / VCC / SCC / EXEC / PC (wave state)

- **Owns / updates / consumes.** `simd32` owns and updates (SALU, compares, `S_SET_EXEC`, branches); the same block consumes. VCC is per-lane (32 bits), SCC is per-wave; EXEC is 32 bits; PC is an 8-bit word index.
- **Semantic value to preserve.** The seeded launch state (`s0..s4`, PC=0, EXEC=(1<<WG_SIZE)-1), the SALU results, the branch decision, and the EXEC mask must be identical on every run. One PC per wave; no divergence reconvergence stack.
- **Golden-model trace point.** The SGPR/VCC/SCC/EXEC/PC state after each scalar/control instruction; the branch history.
- **Tolerance.** Exact equality.
- **Integration/validation DV.** Branch/loop kernel; `S_CMP`/`S_CBRANCH_SCC`; EXEC masking of a vector store; a workgroup with `WG_SIZE<32` (untested in the legacy RTL).
- **Bulk flag.** No.

### S5 — WMMA accumulator banks and pipeline state

- **Owns / updates / consumes.** The `wmma` block owns two 256 x int32 accumulator banks (16,384 bits) and the descriptor/beat pipeline. It updates them during the compute phase and reads the completed bank during the C store.
- **Semantic value to preserve.** Each C word is the exact int32 sum of 32 products, using the E2M1 decode `{0,1,2,3,4,6,8,12}` (the x2 integer representation of the E2M1 magnitudes 0, 0.5, 1, 1.5, 2, 3, 4, 6) with sign applied. The hardware result is 4x the nominal FP4 product because both operands carry the x2 factor; the consumer removes the x4. No E8M0 block scale is applied inside the MAC tree (FR-CORE-4). `C = A*B` per operation; cross-operation accumulation is software.
- **Golden-model trace point.** All 256 int32 C words after each MFMA, plus the per-cycle accumulator state for the pipeline test; the op-to-op issue timestamps for the sustained-throughput test.
- **Tolerance.** Exact equality. The E8M0 scale is an exact power-of-two exponent operation applied after the core; if a reference chooses floating-point for the scale, the comparison must define a tolerance, but the hardware contract is integer-exact.
- **Integration/validation DV.** The unit WMMA test (A=1.0 code 2, B=2.0 code 4, K=32 => C=256 in the x4 integer pipeline); the full-chip 16x16x32 matmul (KPI-CORR-001); the back-to-back MFMA sustained test (KPI-PERF-001); a test that forces the ping-pong bank switch and proves no C corruption.
- **Bulk flag.** 16 Kbit, but the writer and reader are both `wmma`; it stays inside the core. The *cross-block* C store is the LDS write covered by S1.

### S6 — TDM descriptor and beat state

- **Owns / updates / consumes.** `tdm` owns the source address, LDS destination, remaining word count, beat counter, and burst-in-progress flag; the `axi_master` consumes the beat stream.
- **Semantic value to preserve.** The copy is 1-D contiguous; the source is 128-byte aligned; the destination is 32-word aligned; `len` is a multiple of 32 and <=256 words; each 128-byte burst writes exactly one 32-word LDS row; no reordering across chunks (chunk n lands before chunk n+1).
- **Golden-model trace point.** The per-chunk global address/LDS address pairs and the LDS image after the copy; the AXI AR/ R beat trace (address, length, last).
- **Tolerance.** Exact equality.
- **Integration/validation DV.** The 64-word A and 64-word B copies followed by WMMA; a 256-word maximum-length copy; a misaligned/invalid descriptor test (software contract: behavior is undefined; the bring-up must not silently corrupt other LDS rows); TDM vs WMMA linear-port arbitration.
- **Bulk flag.** No.

### S7 — AXI4 outstanding and ordering state

- **Owns / updates / consumes.** `axi_master` owns the outstanding-transaction flag, burst beat counter, and read/write data buffers; the CP (I$ preload), TDM, and SIMD (`V_MEM_*`) consume the completed blocks.
- **Semantic value to preserve.** At most one outstanding transaction (FR-MEM-4); INCR8 (8 beats of 16 B = 128 B); 128-byte-aligned address; the write data/strb and the read data returned in order; `RLAST`/`WLAST` at the eighth beat; `BRESP`/`RRESP` are OKAY in the bring-up. With one outstanding transaction there is no ID reordering.
- **Golden-model trace point.** The AXI transaction trace: AR/AW address and length, beat count, `RLAST`/`WLAST` position, and the assembled 128-byte block.
- **Tolerance.** Exact equality for data and addresses; protocol compliance is a separate checker obligation.
- **Integration/validation DV.** AXI VIP or protocol checker on all full-chip tests; back-pressure on `RREADY`/`WREADY`; a write followed by a read of the same block; the I$ preload's 8 back-to-back bursts (serialized by the one-outstanding rule).
- **Bulk flag.** No.

### S8 — LDS port arbitration (history-dependent)

- **Owns / updates / consumes.** The LDS arbiter in `wgp_ctrl` owns the per-cycle grant, the priority state, and (in the pipelined baseline) reservation credits; the SIMD lane ports, the WMMA linear port, and the TDM linear port consume grants.
- **Semantic value to preserve.** The arbitration policy must guarantee the WMMA 12 grants per 16-cycle slot (4 operand + 8 C store) when it is running back-to-back, and the TDM at least 2 grants per 16 cycles at full AXI rate; the remaining grants serve the lane ports. The grant sequence must be deterministic for a given request sequence; no master may starve. The physical array serves one 32-word access per cycle (12.8 GB/s aggregate, PRD Speed & Feeds).
- **Golden-model trace point.** A per-cycle grant trace (master ID, address, read/write) over a sustained MFMA window; the measured grant count per 16-cycle window; the achieved FLOP/s (KPI-PERF-001).
- **Tolerance.** The functional data must be exact; the *schedule* is judged by the throughput bound (>=92.16 GFLOP/s) and by absence of starvation, not by exact cycle-by-cycle equality with the model.
- **Integration/validation DV.** Sustained back-to-back MFMA test with counters for grants per master; a mixed SIMD+TDM+WMMA stress test; a starvation test that holds the linear port busy; the LDS conflict path; a gate-level or post-P&R timing check of the arbiter at 100 MHz.
- **Bulk flag.** No, but it is a genuinely history-dependent state machine (credits/priority) whose behavior determines whether FR-PERF-2 is met. It must be specified, not left to ad-hoc priority.

### S9 — Launch, CSR, and completion state

- **Owns / updates / consumes.** `command_processor` owns CONTROL, STATUS, KERNEL_PC, ARG_PTR, GRID_X/Y/Z, WG_SIZE, IRQ_EN, CYCLE_LO/HI, and WAVE_DONE; the host reads/writes them over AXI4-Lite.
- **Semantic value to preserve.** Launch parameters are latched at `CONTROL.START` and define the launched grid (FR-HOST-3). `STATUS.BUSY` is set at launch and cleared at completion; `STATUS.DONE` is set once per launch; `STATUS.ERROR` is sticky until the next launch; `WAVE_DONE` counts retired workgroups (FR-EXEC-3); `IRQ` is a level held until the next START and asserted only when `IRQ_EN[0]=1`; `CYCLE_LO/HI` is a free-running 64-bit counter. Reset values: all zero except `GRID_X/Y/Z=1` and `WG_SIZE=32` as specified in the register map.
- **Golden-model trace point.** The CSR readback after each host write, the STATUS/IRQ timeline at completion, and the final WAVE_DONE value for GRID_X = 1..8.
- **Tolerance.** Exact equality for all CSR values and for the WAVE_DONE count. The cycle counter is informational; no latency bound is fixed (Q-2).
- **Integration/validation DV.** CSR reset-value and readback test; a START-while-busy test; an IRQ_EN=0/1 test; a GRID_X=8 test that checks WAVE_DONE=8 and DONE=1; a STATUS.ERROR test via an LDS conflict.
- **Bulk flag.** No.

### S10 — Grid dispatch state

- **Owns / updates / consumes.** `wgp_ctrl` owns `pending` (workgroups not yet dispatched/retired), the SIMD busy/idle flags, and the per-wave `wg_id`; the SIMDs consume the launch seeds, and the CP consumes `wgp_done`.
- **Semantic value to preserve.** GRID_X workgroups are launched exactly once each; SIMD0 receives the first free slot, then SIMD1; a SIMD executes one wave at a time; `wgp_done` asserts only when `pending==0` and both SIMDs are idle; `STATUS.ERROR` is the OR of the SIMD errors (or the LDS conflict event).
- **Golden-model trace point.** The dispatch trace (cycle, wg_id, SIMD) and the retirement trace; the final WAVE_DONE.
- **Tolerance.** Exact equality for the count and for the per-workgroup results; the dispatch order is SIMD0-first and must be deterministic.
- **Integration/validation DV.** GRID_X = 1, 2, and 8; WG_SIZE = 1, 31, 32; a mix of vector and matrix workgroups; a wave that errors while another is running.
- **Bulk flag.** No.

### S11 — Host software scale and accumulate loop

- **Owns / updates / consumes.** Host software owns the E8M0 block scales, the x1/4 rescale, and the cross-K accumulation in global memory/LDS; the hardware does not see or store the scale state.
- **Semantic value to preserve.** For every 32-element MXFP4 block, the scale is `2^(e-127)` (E8M0), applied once; the integer C is divided by 4 (the x2 operand decode squared) and multiplied by the A and B block scales; accumulation across K blocks is exact integer addition before the final scale, or a defined float order if the consumer converts early. The validation reference must implement the identical order.
- **Golden-model trace point.** The final global C image after scaling, compared to the software reference; the per-block scale values used.
- **Tolerance.** Exact if the reference stays integer and uses exponent arithmetic; a defined tolerance (and a defined accumulation order) if the reference converts to float. The PRD's acceptance criterion is byte-exact int32 C for KPI-CORR-001, so the reference must match the integer path exactly.
- **Integration/validation DV.** A trusted Python golden model (missing today — see Risk R1) that models the E2M1 decode, the packed layout, the int32 accumulation, the x4 rescale, and the E8M0 scale; end-to-end comparison of the final C image.
- **Bulk flag.** The scale table/partial sums live in global memory or host memory, not in a chip block; they are software state.

## Technology Rationale

### PDK and standard-cell library

Sky130A with `sky130_fd_sc_hd` at `tt_025C_1v80` (1.8 V, 25 C) is fixed by CON-1 and is the only open, signoff-capable PDK available for this run. The high-density library is the right choice at 100 MHz: the design is register- and memory-dominated, and area, not raw speed, is the binding constraint. The high-speed (`sky130_fd_sc_hs`) library would improve the 512-MAC combinational path but costs area and is not the stated target; it remains a fallback only if the pipelined WMMA cannot close at 100 MHz. The 10 ns period is generous for control and 32-bit integer logic; the risk is the matrix core's 512-MAC-per-cycle datapath and the wide memory muxing, not the clock.

### Memory technology

The PRD fixes the LDS and I$ as flop arrays in this run (CON-5) and excludes bulk memories from the 500,000-cell logic cap, while allowing Sky130 1R1W SRAM macros in production (Q-1). Flop arrays give the multi-port flexibility the LDS needs (two lane ports plus a linear port) and avoid a macro-generation flow in this run, but they are area-expensive. The architecture therefore mandates a **physically banked** implementation: 32 banks of 32 rows x 32 bits, each bank with a 32:1 read mux per port and a single write port. This is the difference between an estimated ~130–200k cell-equivalents and the current flat RTL's ~3.3M cells. The instruction RAM is similarly banked and port-minimized. If the banked flop arrays still miss the 4–8 mm² die budget after synthesis, the fallback is a production SRAM macro (4 x 1 KB 1RW banks plus external arbitration for the LDS, and a 2R1W macro or two 1R1W macros for the I$), which is an explicit open item (Q-1) and a requirement change, not a silent substitution.

### Clocking and reset

A single 100 MHz clock and an active-low **synchronous** reset are fixed by FR-CLK-1 and CON-2. The single domain removes CDC, asynchronous FIFOs, and synchronizers, and the synchronous reset maps directly to Sky130 flop D inputs without a reset tree. Reset must be held for at least two clocks and released synchronously; all state is defined at reset except the LDS, I$, and VGPR contents, which software initializes or the CP preloads. No latches and no tri-states are permitted (FR-RTL-1); clock gating, if used for power, is inserted by the backend as ICG cells, not written in RTL.

### Interfaces

AXI4 at 128 bits, 32-bit address, INCR8 bursts, one outstanding transaction (FR-MEM-4) is the right point: 128 bits matches a 32-word LDS row and a 128-byte global block, so one burst fills one row and one alignment rule covers both sides; one outstanding transaction keeps the master small and deterministic. A 256-bit master would double the pin/port width for no benefit at the 12.8 Gbit/s feed, and a 64-bit master would halve the feed and make the 1.6 GB/s ceiling unreachable. AXI4-Lite at 32 bits is sufficient for the 11-register CSR set; full-word writes are the contract (WSTRB ignored) and all responses are OKAY.

### Numerics

MXFP4 E2M1 is decoded to the integer sequence `{0,1,2,3,4,6,8,12}` (the x2 representation of the nominal magnitudes), so the products and the K=32 accumulation are exact integer arithmetic with no rounding, no saturation, and no denormal handling. The E8M0 shared block scale and the x1/4 rescale are applied by software outside the MAC tree, exactly as FR-CORE-4 requires. This is a deliberate simplification: it makes the core small and exactly verifiable, at the cost of software post-processing. F16/FP32 vector arithmetic is out of scope (CON-7, FR-CORE-5) and those opcodes are reserved, not trapped.

### Alternatives considered

| Alternative | Why rejected |
|---|---|
| `sky130_fd_sc_hs` | Larger cells for speed the 100 MHz target does not need; not the stated library (CON-1). Fallback only if timing fails. |
| 256-bit AXI4 | Doubles pins/ports and buffers; the feed is already 12.8 Gbit/s and the LDS row is 32 words. |
| 64-bit AXI4 | Halves the 1.6 GB/s ceiling and the 128-byte block alignment fit. |
| Multiple outstanding AXI transactions | Adds ID/reorder buffers and area; the workload is latency-tolerant and the TDM is 1-D. One outstanding is the PRD contract. |
| OpenRAM SRAM macros in this run | CON-5 forbids OpenRAM generation; Q-1 is open; flop arrays keep the run self-contained. Production fallback. |
| Dual clock / async reset | No need at 100 MHz; adds CDC and reset complexity (FR-CLK-1). |
| Cache hierarchy / L2 | Out of scope; 1 KB preload I$ and explicit TDM staging are sufficient and deterministic. |
| 5-D TDM with bounds/multicast | Out of scope (CON-6); the 1-D copy covers the bring-up dataflow. |
| Binary-compatible CDNA5 ISA | Not a goal (CON-8); the frozen 32-bit subset is smaller and verifiable. |
| A control CPU / firmware | Area and non-determinism for no benefit; the CP is a fixed FSM. |
| Serialized (non-pipelined) WMMA | Fails FR-PERF-2: the measured 37-cycle block yields ~44.3 GFLOP/s, far below 92.16 GFLOP/s. |

## Architecture Decisions

**AD-1 — One WGP, one CU, two SIMD32, one wave per SIMD.**
- *Decision:* Instantiate exactly one WGP containing one CU with two SIMD32 units; each SIMD executes one wave32 (32 work-items) with one PC and a 32-bit EXEC mask; 16 VGPRs per lane, 32 SGPRs per wave, VCC and SCC.
- *Rationale:* FR-CORE-1/2 and FR-EXEC-1 fix this; one wave per SIMD keeps the scheduler trivial and the register files small.
- *Alternatives:* Two CUs/four SIMD32 (area), multiple resident waves per SIMD (scheduler and register-file area), 64-wide wave (breaks the CDNA5 invariant).

**AD-2 — One WGP-shared MXFP4 matrix core, 16x16x32, 512 MAC/cycle, 16-cycle cadence.**
- *Decision:* A single WMMA shared by both SIMDs; fixed `C[16][16] int32 = A[16][32] x B[32][16]`; 2 K-slices x 256 outputs per cycle = 512 MAC/cycle; 16 compute cycles; one operation at a time.
- *Rationale:* FR-CORE-3 and FR-PERF-1; sharing halves the matrix area and matches the PRD's explicit "the two SIMD32 units do not each own a matrix core".
- *Alternatives:* Per-SIMD matrix cores (2x area), a larger 32x32 tile (LDS capacity and routing), a smaller tile (fails the FLOP/cycle target).

**AD-3 — Pipelined WMMA with ping-pong accumulator banks and overlapped C store.**
- *Decision:* Overlap the C store of operation *i* with the operand read and compute of operation *i+1*; use two 256 x int32 accumulator banks; keep a one-deep descriptor queue; target a steady-state 16-cycle issue cadence with a drain of 8 cycles for the last store.
- *Rationale:* FR-PERF-2 requires >=92.16 GFLOP/s (an average cadence <=17.78 cycles). The legacy serialized core (load 11 + compute 16 + store 9 + handshake = 37 cycles) yields ~44.3 GFLOP/s and **fails** the requirement. The pipelined schedule uses 12 of 16 LDS grants per slot and fits.
- *Alternatives:* Serialized core (fails FR-PERF-2), a full 1 KB C staging buffer with a 256-word parallel copy (area and mux cost), a 2-cycle bubble schedule (16/18 = 88.9%, fails), a wider LDS port (area).

**AD-4 — Packed MXFP4 operand layout in LDS.**
- *Decision:* A and B are stored as packed 4-bit elements: A = 64 words (16x32), B = 64 words (32x16), both 32-word aligned; two FP4 per byte, low nibble first; C = 256 int32 words.
- *Rationale:* 1,024 operand elements must be read in 16 cycles; unpacked 32-bit elements would need 1,024 words (32 cycles) and make the cadence impossible. The packed layout is 128 words = 4 grants.
- *Alternatives:* Unpacked elements (fails throughput and LDS capacity), a separate MXFP4 unpack cache (area, redundant).

**AD-5 — Banked LDS with three logical ports and one 32-word grant per cycle.**
- *Decision:* 4 KB as 32 banks x 32 rows x 32 bits; two lane ports (one per SIMD) and one linear port (WMMA/TDM); the physical array serves one 32-word access per cycle (12.8 GB/s aggregate); the arbiter reserves 12 grants per 16-cycle slot for the WMMA and >=2 for the TDM, leaving the rest for lane ports.
- *Rationale:* FR-MEM-1 and the PRD's 32 words/cycle x 32 bits feed; the reservation is what makes FR-PERF-2 provable. A flat multi-port array is not synthesizable within the die budget.
- *Alternatives:* Three independent full-width ports (area), a wider 64-word port (area, no need), round-robin without reservation (can starve the WMMA and miss the KPI).

**AD-6 — LDS map with A/B double buffering.**
- *Decision:* Freeze the LDS byte map: A0/A1 at 0x000/0x100, B0/B1 at 0x200/0x300, C at 0x400-0x7FF, scratch at 0x800-0xFFF (total 2 KB used, 2 KB free).
- *Rationale:* A/B ping-pong plus C fits in 2 KB; double buffering lets the TDM fill the next tile while the core computes the current one; the map is a software contract the kernel and the WMMA descriptors share.
- *Alternatives:* Single-buffered A/B (serializes TDM and compute, hurts sustained), a 32x32 C tile (4 KB alone, does not fit).

**AD-7 — Exact int32 MXFP4 accumulation; scale outside the MAC tree.**
- *Decision:* Decode E2M1 to `{0,1,2,3,4,6,8,12}` with sign; accumulate exactly in int32; hardware output is 4x the nominal FP4 product; software applies the x1/4 rescale and the E8M0 block scale.
- *Rationale:* FR-CORE-4 requires exact int32 and forbids the scale inside the MAC tree; exact integer arithmetic is small and byte-exactly verifiable.
- *Alternatives:* In-core exponent scaling (area, rounding, and a larger golden-model surface), FP32 accumulation (area, not the PRD format).

**AD-8 — `C = A*B` per operation; cross-K accumulation in software.**
- *Decision:* The core computes `C = A*B` and writes the C tile to LDS. Cross-operation accumulation (`C += A*B`) is done by software with exact int32 addition (SIMD or host).
- *Rationale:* FR-CORE-3 states `C = A*B`; a hardware accumulate would require a C read per operation (8 more LDS grants) and break the 16-cycle cadence.
- *Alternatives:* Hardware accumulate from LDS (8 extra grants, fails the cadence), an internal C register file across operations (area; still needs initialization and a drain).

**AD-9 — 1-D TDM only, global-to-LDS, 32-word units.**
- *Decision:* A contiguous copy engine with 128-byte-aligned global source, 32-word-aligned LDS destination, `len` a multiple of 32 and <=256 words, no bounds checks, no multicast, no LDS-to-DRAM.
- *Rationale:* CON-6 and FR-MEM-3; the 32-word unit matches the linear LDS port and the INCR8 burst exactly.
- *Alternatives:* 5-D descriptor engine (out of scope, area), scatter/gather (out of scope), a per-lane load path (more SIMD work, less efficient).

**AD-10 — AXI4 128-bit master, INCR8, one outstanding transaction.**
- *Decision:* 128-bit data, 32-bit address, 8-beat INCR bursts of 128 B, 4-bit ID tied to 0, one outstanding transaction, `BRESP`/`RRESP` treated as OKAY in the bring-up.
- *Rationale:* FR-MEM-4; 128 B aligns with the LDS row, the TDM chunk, and the 128-byte global rule; one outstanding keeps the master area and determinism.
- *Alternatives:* 256/64-bit data (see Technology Rationale), multiple outstanding (area, no workload need), unaligned bursts (breaks the LDS/TDM alignment contract).

**AD-11 — AXI4-Lite 32-bit host CSR slave, 4 KB window, 11 registers.**
- *Decision:* 32-bit data and address; decode the low 12 address bits into a 4 KB window; implement CONTROL, STATUS, KERNEL_PC, ARG_PTR, GRID_X, GRID_Y, GRID_Z, WG_SIZE, IRQ_EN, CYCLE (as CYCLE_LO/CYCLE_HI), and WAVE_DONE; full-word writes only; OKAY responses; unimplemented offsets read 0.
- *Rationale:* FR-HOST-1; the 32-bit address width follows the PRD parameter `axi_addr_width_bits=32`; splitting CYCLE into two 32-bit registers preserves the single 64-bit CSR without a 64-bit bus.
- *Alternatives:* 8-bit Lite address (not the PRD parameter), a 64-bit CSR data bus (area), a command queue (out of scope), an I$ CSR aperture (adds registers not in the frozen map).

**AD-12 — CP preloads the 1 KB I$ from global memory at KERNEL_PC.**
- *Decision:* The host places the kernel image in global memory; on START the CP issues 8 x 128-byte AXI reads from `KERNEL_PC` and writes all 256 words to the I$. The wave PC starts at I$ word 0, so `KERNEL_PC` is a global byte address, not a code offset.
- *Rationale:* FR-HOST-2 says the command processor preloads the I$; the 11-register CSR set has no I$ data port, so a global-memory image is the only path that preserves the frozen CSR map. This interprets the PRD's "host preloads the I$" as the host preparing the image and the CP performing the preload.
- *Alternatives:* A CSR I$ write aperture (new registers, outside FR-HOST-1), a host-driven DMA into the I$ (needs a second master or a CSR aperture).

**AD-13 — Launch parameters latched at START; WAVE_DONE counts retired workgroups.**
- *Decision:* Latch `KERNEL_PC`, `ARG_PTR`, `GRID_X/Y/Z`, `WG_SIZE`, `IRQ_EN` at `CONTROL.START`; set BUSY, clear DONE; on completion set DONE, clear BUSY, increment WAVE_DONE **per retired workgroup**, and drive a level IRQ when enabled.
- *Rationale:* FR-HOST-2/3 and FR-EXEC-3. The legacy RTL counts one per launch, which is a deviation from FR-EXEC-3 and must be corrected in the new baseline.
- *Alternatives:* Count per launch (fails FR-EXEC-3), a pulse IRQ (the PRD says level).

**AD-14 — Grid = GRID_X workgroups, GRID_Y/Z reserved at 1.**
- *Decision:* `GRID_X` = 1..8 is the workgroup count; `GRID_Y` and `GRID_Z` are reserved and must be written 1; the total is X*Y*Z with only X>1 supported. `WG_SIZE` = 1..32; `EXEC = (1<<WG_SIZE)-1`; one workgroup = one wave32; SIMD0-first dispatch.
- *Rationale:* FR-EXEC-1 and the PRD's 1–8 workgroup range; the 2-D/3-D grid is not required by the acceptance tests and reserving Y/Z keeps the CSR map complete without a 3-D scheduler.
- *Alternatives:* A full 3-D grid scheduler (area, untested), ignoring Y/Z entirely (breaks the CSR contract).

**AD-15 — Single 100 MHz clock, active-low synchronous reset, Verilog-2005.**
- *Decision:* One clock domain; `rst_n` sampled on `posedge clk`, held >=2 clocks; every register is `always @(posedge clk)`; no latches, no tri-states, no SystemVerilog.
- *Rationale:* FR-CLK-1, FR-RTL-1, CON-2; the open Yosys/OpenROAD flow is the signoff flow (CON-3).
- *Alternatives:* Async reset (no need, harder timing), multiple clocks (CDC cost), SystemVerilog (tool and contract violation).

**AD-16 — Banked flop-array memories; SRAM macros are a production option only.**
- *Decision:* Implement the LDS as 32 physical banks and the I$ as a banked 256-entry memory, each with per-bank read muxes; no flat multi-port arrays; no OpenRAM in this run.
- *Rationale:* CON-5 fixes flop arrays for the run; the flat LDS currently elaborates to ~3.3M cells and cannot meet the die budget; banked structures reduce the read-mux cost by an order of magnitude. Production may map to Sky130 1R1W macros (Q-1).
- *Alternatives:* Flat arrays (infeasible area), SRAM macros now (violates CON-5 / Q-1), a smaller LDS (breaks the tile capacity).

**AD-17 — LDS conflict policy: detect and abort, do not replay.**
- *Decision:* A lane port that presents two addresses in the same bank with different rows is not served; the SIMD raises a sticky ERROR, the wave aborts, the WGP reports error, the CP sets STATUS.ERROR and clears BUSY without IRQ. Only conflict-free access patterns are supported.
- *Rationale:* FR-MEM-1 says conflict-free only; replay/serialization hardware is out of scope and would complicate the arbiter.
- *Alternatives:* Bank-conflict replay (area and latency), silent serialization (unbounded latency), ignoring conflicts (silent corruption).

**AD-18 — No vector FP4/INT8 dot-product performance target; V_DOT8 is not a KPI.**
- *Decision:* The authoritative performance requirements are the matrix peak (FR-PERF-1) and the LDS-fed matrix sustained bound (FR-PERF-2). No vector dot-product FLOP/s bound is adopted. If the legacy ISA/RTL retains `V_DOT4`/`V_DOT8`, they are compatibility extras, not requirements; the vector path of record is the 2x SIMD32 integer ALU (32 lanes per SIMD per cycle, ~6.4 Gops/s at 100 MHz for single-cycle integer ops, derived from FR-CORE-5).
- *Rationale:* PRD Q-3 states no vector FP4/INT8 dot rate is specified; FR-CORE-5 scopes the non-matrix path to integer vector operations; FR-EXEC-2's ISA list contains no dot-product class. The FRD item PERF-002 previously claimed a 102.4 GFLOP/s vector-dot8 bound; that was a generated claim inconsistent with the PRD and has been corrected at its source to the FR-PERF-2 sustained-matrix bound.
- *Alternatives:* Keeping the vector-dot8 bound (fabricates a requirement and drives unrequested hardware), deleting PERF-002 entirely (loses the sustained bound, which is required).

**AD-19 — The deliverable is soft IP; the functional interface is not narrowed for the shuttle.**
- *Decision:* Keep `chip_top`'s full-width AXI4 master (128-bit data, 32-bit address) and AXI4-Lite host slave as the functional contract. Do not serialize, pin-mux, or narrow these interfaces to fit the OPENFRAME 44-pad frame. The shuttle wrapper, if requested, is a separate hardened integration layer outside `chip_top`.
- *Rationale:* The PRD specifies a synthesizable implementation verified in full-chip simulation, not a hardened pad-limited part; the user did not request an MPW wrapper. Narrowing AXI4 would break the 128-byte burst / 32-word LDS-row alignment contract and the 1.6 GB/s feed.
- *Alternatives:* A 44-pad serialized wrapper (changes the functional interface and throughput; requires explicit approval), a reduced 8-bit host-only top (not the PRD interface).

**AD-20 — Error handling and software contracts.**
- *Decision:* LDS conflicts are the only hardware-detected error and abort the wave with sticky STATUS.ERROR. Illegal opcodes and unaligned/invalid TDM descriptors are software contracts (undefined behavior); AXI error responses are treated as OKAY in the bring-up. `S_BARRIER` is a NOP for one-wave workgroups. A new START while busy is ignored. `CONTROL.SOFT_RESET` is reserved and stored but has no function in the bring-up.
- *Rationale:* The PRD's error surface is limited to conflict-free LDS operation and the frozen ISA; adding traps or replay increases area without a requirement. The software contracts are documented so kernels cannot rely on undefined behavior.
- *Alternatives:* Full illegal-opcode traps (area, no requirement), AXI error handling (no error-generating slave in the bring-up), conflict replay (AD-17).

### Requirement Corrections and Interpretations

1. **FRD PERF-002 (corrected).** The rendered FRD previously read "Vector MXFP4 dot8 sustains 102.4 GFLOP/s (2 SIMD x 32 lanes x 8 MAC at 100 MHz)". That conflicts with the authoritative PRD (Q-3: no vector FP4/INT8 dot rate is specified; FR-CORE-5: the non-matrix path is the integer vector path; FR-EXEC-2: no dot-product instruction class in the frozen ISA). The item has been corrected at its source to the PRD's sustained-matrix bound: "Matrix core sustained throughput >=92.16 GFLOP/s (>=90% of the 102.4 GFLOP/s peak) with A/B operands fed from LDS", metric `flops`, min 92,160,000,000 flop/s, derived from KPI-PERF-001, owned by `wmma`. The FRD markdown has been re-rendered from the database. This SAD adopts the corrected item; it does **not** adopt a vector dot8 KPI.
2. **WAVE_DONE semantics.** FR-EXEC-3 says a workgroup's completion at `S_ENDPGM` is counted in WAVE_DONE; the legacy RTL increments once per launch. The SAD mandates per-retired-workgroup counting (GRID_X=8 => WAVE_DONE=8) and flags the legacy behavior as a deviation to fix.
3. **I$ preload path.** "Host preloads the I$" and "the command processor must preload the I$" are reconciled by AD-12: the host supplies the image in global memory at `KERNEL_PC`; the CP performs the AXI4 fetch. No new CSR is added.
4. **AXI address width.** The PRD parameter `axi_addr_width_bits=32` is applied to both AXI4 and AXI4-Lite; the CSR slave decodes the low 12 bits into a 4 KB window and ignores the upper address bits (the interconnect owns aperture decoding).
5. **Latency.** No host-visible latency budget exists (Q-2, PRD `latency_budget_us=null`). The 1,035-cycle (~10.35 µs) full-chip matmul run is an informational reference, not a hard bound. The only timing contract is the 100 MHz clock and the sustained-throughput bound.

## Risk Assessment

| ID | Risk | Severity | Impact | Mitigation |
|---|---|---|---|---|
| R1 | No independent golden reference model | **High** | A shared misreading of E2M1 decode, packed layout, or int32 accumulation escapes block DV and surfaces in validation | Commission a trusted Python golden model of the matrix datapath and the software scale path before validation DV; use word-exact LDS/C trace points (S1, S5); freeze the numeric contract in this SAD and the ISA |
| R2 | Sustained >=90% not met by the legacy serialized WMMA | **High** | FR-PERF-2 fails (measured ~44.3 GFLOP/s vs 92.16 required) | AD-3 pipelined core with ping-pong banks; LDS grant reservation (AD-5); instrument back-to-back MFMA throughput and gate the architecture on KPI-PERF-001 |
| R3 | 512-MAC/cycle datapath timing at 100 MHz in sky130 HD | **High** | Setup violations; a slower clock or a deeper pipeline | Pipeline the 4x4 multiplies and the int32 adder tree across the 16 compute cycles; the 16-cycle budget tolerates several register stages; retiming and a fallback to `sky130_fd_sc_hs` if needed |
| R4 | LDS flop-array area/synthesis blow-up | **High** | 4-8 mm² die budget cannot be met; full-chip P&R blocked | Mandatory 32-bank physical structure with per-bank muxes (AD-16); the current flat RTL's ~3.3M cells is rejected; production SRAM macro fallback (Q-1) as a documented requirement change |
| R5 | SIMD32 synthesis blow-up (VGPR write-enable expansion) | **Medium-High** | 2x SIMD32 is the largest logic block; synthesis did not finish in the legacy flow | Per-lane register-file structure with explicit EXEC-gated write enables; hierarchical/per-lane synthesis; avoid flat arrays |
| R6 | Full-chip P&R needs >8 GB and is pending (CON-9) | **High** | No signoff evidence; die area, timing, power unproven | Run on a host with more memory; hierarchical P&R; use the block-level evidence (WMMA 126,245 cells / 1.218 mm², TDM 10.1 mW) only as interim data |
| R7 | AXI feed is 2x short of the streaming peak (16 B/cycle vs 32 B/cycle needed for a fresh 512 B operand set per 16 cycles) | **Medium** | Peak throughput is unreachable from global memory alone; a naive streaming kernel is memory-bound at ~17 GFLOP/s | FR-PERF-2 is explicitly LDS-fed; require A/B reuse and K-blocking in kernels; document the roofline; the acceptance matmul is a single tile |
| R8 | OPENFRAME pad frame cannot host the 581-signal functional interface | **High (for tapeout)** | The soft IP cannot be hardened on the 44-pad shuttle without a wrapper | Deliver soft IP with the interface intact (AD-19); a hardened wrapper with serialization is out of scope and requires explicit approval; plan a larger package or a wrapper SoC |
| R9 | LDS/TDM/lane-port arbitration can starve the WMMA or the lane ports | **Medium** | Missed sustained KPI or hung SIMD | Credit/reservation arbiter (AD-5, S8); grant counters per master; a starvation stress test; deterministic priority |
| R10 | WAVE_DONE and launch semantics differ from the legacy RTL | **Medium** | Host software sees the wrong completion count | Implement FR-EXEC-3 per-workgroup counting and latch-at-START (AD-13); grid=1 and grid=8 tests |
| R11 | Power estimate unmeasured; 2 W bound | **Medium** | Late power overage | OpenROAD/OpenSTA with VCD activity at the tt corner; per-block clock gating inserted at backend; 2 W is generous at 100 MHz if the memories are banked |
| R12 | No AXI protocol checker/VIP | **Medium** | Protocol bugs (LAST, handshake, back-pressure) escape DV | Add an AXI VIP/protocol checker to integration DV; exercise RREADY/WREADY back-pressure |
| R13 | Numeric ambiguity in the E8M0/scale software path | **Medium** | Reference mismatch at the final C image | Freeze the scale order and the x1/4 rescale in the software spec; extend the golden model to the scale path; exact integer comparison where possible |
| R14 | Frozen ISA and assembler coverage | **Low-Medium** | Undefined behavior on unimplemented opcodes | Keep the ISA frozen; trap nothing in the bring-up but list reserved opcodes; directed per-opcode tests |

**Top three.** R1 (no golden model) is the highest semantic risk because the entire acceptance criterion is byte-exact int32; without an independent model, a decode or packing error is self-consistent between the RTL and the testbench. R2 (sustained throughput) is the highest architectural risk because the existing RTL provably misses FR-PERF-2 and the fix changes the matrix core pipeline. R4 (LDS area) is the highest physical risk because the flat flop array is an order of magnitude over the die budget; the banked structure must be proven in synthesis before the architecture can be called area-closed.

## Pinout

### Deliverable class and package

This run delivers **synthesizable soft IP** (`chip_top`), not a packaged part. The PRD's acceptance is full-chip RTL simulation (FR-VER-1), and the PRD defines top-level ports, not package balls. No package is therefore defined for this deliverable. For reference, if the full 581-signal functional interface were brought to a package, it would require a BGA with at least 600 balls (581 signals plus power/ground and spare); QFN/QFP are not feasible at this pin count. Package selection is a hardened-integration decision, not part of this soft-IP contract.

### Top-level pin table

Each row is one signal; a bus row occupies its declared width. The `Ball/Pin` column is "—" because the deliverable is soft IP; a hardened wrapper mapping is discussed under Shuttle Integration. All functional signals are in the `vccd1` (1.8 V) core domain.

| Name | Direction | Signal Type | Voltage Domain | Ball/Pin | Description |
|---|---|---|---|---|---|
| `clk` | input | clock | vccd1 (1.8 V) | — | Single 100 MHz clock (FR-CLK-1) |
| `rst_n` | input | reset | vccd1 (1.8 V) | — | Active-low synchronous reset, held >=2 clocks (FR-CLK-1) |
| `irq` | output | interrupt (level) | vccd1 (1.8 V) | — | Completion IRQ, held until next START, gated by IRQ_EN[0] (FR-HOST-2) |
| `m_axi_awid[3:0]` | output | AXI4 write address ID | vccd1 (1.8 V) | — | Tied to 0; one outstanding transaction |
| `m_axi_awaddr[31:0]` | output | AXI4 write address | vccd1 (1.8 V) | — | 128-byte-aligned block address (FR-MEM-4) |
| `m_axi_awlen[7:0]` | output | AXI4 write burst length | vccd1 (1.8 V) | — | INCR8 => 7 |
| `m_axi_awsize[2:0]` | output | AXI4 write burst size | vccd1 (1.8 V) | — | 128-bit => 4 |
| `m_axi_awburst[1:0]` | output | AXI4 write burst type | vccd1 (1.8 V) | — | INCR => 01 |
| `m_axi_awlock` | output | AXI4 write lock | vccd1 (1.8 V) | — | Tied 0 |
| `m_axi_awcache[3:0]` | output | AXI4 write cache | vccd1 (1.8 V) | — | Tied 0 (no cache hierarchy) |
| `m_axi_awprot[2:0]` | output | AXI4 write protection | vccd1 (1.8 V) | — | Tied 0 |
| `m_axi_awqos[3:0]` | output | AXI4 write QoS | vccd1 (1.8 V) | — | Tied 0 |
| `m_axi_awregion[3:0]` | output | AXI4 write region | vccd1 (1.8 V) | — | Tied 0 |
| `m_axi_awvalid` | output | AXI4 write address valid | vccd1 (1.8 V) | — | Handshake |
| `m_axi_awready` | input | AXI4 write address ready | vccd1 (1.8 V) | — | Handshake |
| `m_axi_wdata[127:0]` | output | AXI4 write data | vccd1 (1.8 V) | — | 128-bit data (FR-MEM-4) |
| `m_axi_wstrb[15:0]` | output | AXI4 write strobe | vccd1 (1.8 V) | — | Full-block writes; byte strobes |
| `m_axi_wlast` | output | AXI4 write last | vccd1 (1.8 V) | — | Beat 8 of 8 |
| `m_axi_wvalid` | output | AXI4 write data valid | vccd1 (1.8 V) | — | Handshake |
| `m_axi_wready` | input | AXI4 write data ready | vccd1 (1.8 V) | — | Handshake |
| `m_axi_bid[3:0]` | input | AXI4 write response ID | vccd1 (1.8 V) | — | Matches AWID |
| `m_axi_bresp[1:0]` | input | AXI4 write response | vccd1 (1.8 V) | — | OKAY treated as success in bring-up |
| `m_axi_bvalid` | input | AXI4 write response valid | vccd1 (1.8 V) | — | Handshake |
| `m_axi_bready` | output | AXI4 write response ready | vccd1 (1.8 V) | — | Handshake |
| `m_axi_arid[3:0]` | output | AXI4 read address ID | vccd1 (1.8 V) | — | Tied to 0 |
| `m_axi_araddr[31:0]` | output | AXI4 read address | vccd1 (1.8 V) | — | 128-byte-aligned block address |
| `m_axi_arlen[7:0]` | output | AXI4 read burst length | vccd1 (1.8 V) | — | INCR8 => 7 |
| `m_axi_arsize[2:0]` | output | AXI4 read burst size | vccd1 (1.8 V) | — | 128-bit => 4 |
| `m_axi_arburst[1:0]` | output | AXI4 read burst type | vccd1 (1.8 V) | — | INCR => 01 |
| `m_axi_arlock` | output | AXI4 read lock | vccd1 (1.8 V) | — | Tied 0 |
| `m_axi_arcache[3:0]` | output | AXI4 read cache | vccd1 (1.8 V) | — | Tied 0 |
| `m_axi_arprot[2:0]` | output | AXI4 read protection | vccd1 (1.8 V) | — | Tied 0 |
| `m_axi_arqos[3:0]` | output | AXI4 read QoS | vccd1 (1.8 V) | — | Tied 0 |
| `m_axi_arregion[3:0]` | output | AXI4 read region | vccd1 (1.8 V) | — | Tied 0 |
| `m_axi_arvalid` | output | AXI4 read address valid | vccd1 (1.8 V) | — | Handshake |
| `m_axi_arready` | input | AXI4 read address ready | vccd1 (1.8 V) | — | Handshake |
| `m_axi_rid[3:0]` | input | AXI4 read data ID | vccd1 (1.8 V) | — | Matches ARID |
| `m_axi_rdata[127:0]` | input | AXI4 read data | vccd1 (1.8 V) | — | 128-bit data |
| `m_axi_rresp[1:0]` | input | AXI4 read response | vccd1 (1.8 V) | — | OKAY treated as success in bring-up |
| `m_axi_rlast` | input | AXI4 read last | vccd1 (1.8 V) | — | Beat 8 of 8 |
| `m_axi_rvalid` | input | AXI4 read data valid | vccd1 (1.8 V) | — | Handshake |
| `m_axi_rready` | output | AXI4 read data ready | vccd1 (1.8 V) | — | Handshake |
| `s_axil_awaddr[31:0]` | input | AXI4-Lite write address | vccd1 (1.8 V) | — | 4 KB CSR window, low 12 bits decoded (FR-HOST-1) |
| `s_axil_awprot[2:0]` | input | AXI4-Lite write protection | vccd1 (1.8 V) | — | Ignored |
| `s_axil_awvalid` | input | AXI4-Lite write address valid | vccd1 (1.8 V) | — | Handshake |
| `s_axil_awready` | output | AXI4-Lite write address ready | vccd1 (1.8 V) | — | Handshake |
| `s_axil_wdata[31:0]` | input | AXI4-Lite write data | vccd1 (1.8 V) | — | 32-bit CSR data |
| `s_axil_wstrb[3:0]` | input | AXI4-Lite write strobe | vccd1 (1.8 V) | — | Full-word writes; WSTRB ignored |
| `s_axil_wvalid` | input | AXI4-Lite write data valid | vccd1 (1.8 V) | — | Handshake |
| `s_axil_wready` | output | AXI4-Lite write data ready | vccd1 (1.8 V) | — | Handshake |
| `s_axil_bresp[1:0]` | output | AXI4-Lite write response | vccd1 (1.8 V) | — | OKAY |
| `s_axil_bvalid` | output | AXI4-Lite write response valid | vccd1 (1.8 V) | — | Handshake |
| `s_axil_bready` | input | AXI4-Lite write response ready | vccd1 (1.8 V) | — | Handshake |
| `s_axil_araddr[31:0]` | input | AXI4-Lite read address | vccd1 (1.8 V) | — | 4 KB CSR window |
| `s_axil_arprot[2:0]` | input | AXI4-Lite read protection | vccd1 (1.8 V) | — | Ignored |
| `s_axil_arvalid` | input | AXI4-Lite read address valid | vccd1 (1.8 V) | — | Handshake |
| `s_axil_arready` | output | AXI4-Lite read address ready | vccd1 (1.8 V) | — | Handshake |
| `s_axil_rdata[31:0]` | output | AXI4-Lite read data | vccd1 (1.8 V) | — | 32-bit CSR data |
| `s_axil_rresp[1:0]` | output | AXI4-Lite read response | vccd1 (1.8 V) | — | OKAY |
| `s_axil_rvalid` | output | AXI4-Lite read data valid | vccd1 (1.8 V) | — | Handshake |
| `s_axil_rready` | input | AXI4-Lite read data ready | vccd1 (1.8 V) | — | Handshake |

### Pin-count arithmetic (recomputed from the table above)

- AXI4 master: AW channel 4+32+8+3+2+1+4+3+4+4+1+1 = **67**; W channel 128+16+1+1+1 = **147**; B channel 4+2+1+1 = **8**; AR channel 4+32+8+3+2+1+4+3+4+4+1+1 = **67**; R channel 4+128+2+1+1+1 = **137**. Master total = **426**.
- AXI4-Lite slave: AW 32+3+1+1 = **37**; W 32+4+1+1 = **38**; B 2+1+1 = **4**; AR 32+3+1+1 = **37**; R 32+2+1+1 = **36**. Lite total = **152**.
- Clock, reset, interrupt: **3**.
- **Total functional signal bits = 426 + 152 + 3 = 581.**
- Directions: inputs = 2 (clk, rst_n) + 146 (master inputs: awready 1, wready 1, bid 4, bresp 2, bvalid 1, arready 1, rid 4, rdata 128, rresp 2, rlast 1, rvalid 1) + 111 (Lite inputs: awaddr 32, awprot 3, awvalid 1, wdata 32, wstrb 4, wvalid 1, bready 1, araddr 32, arprot 3, arvalid 1, rready 1) = **259**; outputs = 280 (master) + 41 (Lite) + 1 (irq) = **322**. **259 + 322 = 581.**

### Power pins

The soft-IP deliverable has no package pins; power is supplied by the integrating SoC (OpenLane `VPWR`/`VGND`). For a hardened wrapper, the following pad counts are recommended for a <=2 W design at 1.8 V (peak current ~1.11 A) and are advisory, not part of the functional contract:

| Pin | Direction | Signal Type | Voltage Domain | Count (advisory) | Description |
|---|---|---|---|---|---|
| `VDD` / `vccd1` | supply | core power | 1.8 V | 12 | Digital core supply; IR-drop and electromigration margin at ~1.11 A |
| `VSS` / `vssd1` | supply | core ground | 0 V | 12 | Core ground return |
| `VDDIO` / `vddio` | supply | I/O power | 3.3 V | 8 | GPIO pad supply |
| `VSSIO` / `vssio` | supply | I/O ground | 0 V | 8 | GPIO ground return |
| `VDDA` / `vdda1` | supply | analog power | 3.3 V | 2 | Unused (no analog); tied off |
| `VSSA` / `vssa1` | supply | analog ground | 0 V | 2 | Unused; tied to VSSIO |

### I/O standards and ESD

Core logic is 1.8 V CMOS in `sky130_fd_sc_hd`. On a hardened wrapper, GPIO pads use the shuttle's 3.3 V `vddio` LVCMOS standard with level shifters between the 1.8 V core and the 3.3 V pad ring. The pad frame is expected to meet 2 kV HBM and 500 V CDM; confirm with the pad library datasheet. There are no analog, differential, or high-speed SerDes interfaces in this design.

### Pin-muxing and dedicated pads

There is no pin-muxing in the soft-IP contract: each functional signal is a distinct port. The shuttle's fixed 44-pad frame cannot carry 581 signals, so a hardened integration would require serialization or a pin-muxed wrapper. That is a different top-level interface and is out of scope for this run (AD-19); see Shuttle Integration.

### Test and debug pins

**None.** The PRD interface contract does not list JTAG, scan, test mode, or debug pins, so none are added here. DFT insertion (scan chains, test control) is a backend-flow activity and must not appear as functional pins in this SAD.

## Shuttle Integration

### Target shuttle and fit

The task names the **OPENFRAME** shuttle. Its frame is 3520 x 5188 µm (18.262 mm² total), with a user area of 3320 x 4988 µm (16.560 mm²) and a 100 µm core margin; it provides 44 GPIO pads (19 left, 19 right, 6 bottom), of which GPIO[0] = clk and GPIO[1] = rst are reserved, leaving **42 usable GPIO**. Power domains are `vccd1`/`vssd1` (1.8 V digital), `vdda1`/`vssa1` (3.3 V analog), and `vddio`/`vssio` (3.3 V I/O); the metal stack is li1 + met1–met5 with a maximum routing layer of met4.

**Fit:** the core area target (4–8 mm², CON-4) fits inside the 16.560 mm² user area with room for the pad ring and routing. The **pad count does not fit**: the functional interface is 581 signal bits, an order of magnitude beyond the 42 usable GPIO. This is the decisive shuttle constraint.

### Die area budget

| Item | Estimate | Basis |
|---|---|---|
| Logic (WMMA 126,245 measured + pipelining; 2x SIMD32 ~180 k; CP/AXI/TDM/arbiters ~40 k) | ~350–400 k cells | Measured WMMA; others advisory planning |
| LDS 4 KB, banked flop array | ~130–200 k cell-equivalents | 32,768 flops + per-bank muxes (advisory) |
| I$ 1 KB, 2R banked | ~30–50 k cell-equivalents | 8,192 flops + read muxes (advisory) |
| Core area at ~9.6 µm²/cell (measured WMMA density) | ~4.5–6.5 mm² | Advisory; wiring/fillers excluded |
| Shuttle user area | 16.560 mm² | Fixed by the harness |
| Target core-region utilization | 40–60% | Bring-up target, not a bound |

The PRD's 4.0–8.0 mm² die target is compatible with a 4.5–6.5 mm² core plus a pad ring inside the shuttle frame. The physical die delivered by the shuttle is the fixed 3520 x 5188 µm frame, not a custom 4–8 mm² die; the PRD's die range describes the core footprint, not the carrier. The flat LDS implementation (~3.3M cells, ~30 mm²) would not fit and is rejected (AD-16).

### GPIO pad plan

| Pad(s) | Signal | Direction | Notes |
|---|---|---|---|
| GPIO[0] | `clk` | input | Reserved by the harness (100 MHz) |
| GPIO[1] | `rst_n` | input | Reserved by the harness (active-low synchronous) |
| GPIO[2..43] | — | — | 42 usable pads; see below |

**Direct mapping is impossible.** The functional interface is 581 signal bits (259 in, 322 out), so no assignment of the 42 usable pads can carry `chip_top`'s AXI4/AXI4-Lite ports. Consistent with AD-19, this SAD does **not** narrow or serialize the functional interface for the shuttle.

**Option A — current run (soft IP).** Deliver `chip_top` with its full interface; the shuttle pad plan is not exercised. This is the selected option because the PRD asks for a synthesizable, simulation-verified design and does not request a hardened MPW wrapper. All 42 usable pads remain unassigned; only GPIO[0]/[1] are reserved by the harness.

**Option B — hardened wrapper (requires explicit approval; out of scope).** If a tapeout is later requested, a wrapper (`openframe_project_wrapper`) would need to (1) drive the 44 `io_out`/`io_oeb` signals from a reduced host bridge, (2) contain an on-wrapper AXI4 target memory for the accelerator's master (the chip has no external memory on a single-die shuttle), and (3) level-shift 1.8 V core to 3.3 V pads. An illustrative pad budget: 3 control (cs/we/oe) + 8 data-in + 8 data-out + 8 address + 1 ack + 1 irq + 2 status = 31 pads, leaving 11 spare of the 42. The on-wrapper memory would need a Sky130 SRAM macro or a flop test buffer (Q-1), and the host protocol would be a serialized/narrow bridge, which is a **different interface** from `chip_top`'s AXI4-Lite. This option is a wrapper-layer integration decision and must be approved before it is designed; it does not alter the soft-IP contract.

### Power domain assignment

| Block | Domain | Rationale |
|---|---|---|
| `chip_top`, `axi_lite_slave`, `command_processor`, `axi_master`, `wgp_ctrl`, `simd32` x2, `lds`, `wmma`, `tdm`, `instruction_ram` | `vccd1` / `vssd1` (1.8 V) | All digital logic; single supply domain per FR-CLK-1 and the PRD power domain "core" |
| Wrapper GPIO pads | `vddio` / `vssio` (3.3 V) | Shuttle pad-ring standard; level shifters between the 1.8 V core and 3.3 V pads |
| `vdda1` / `vssa1` | unused | No analog content; tie off per the harness rules |

The 2 W bound at 1.8 V implies ~1.11 A peak on `vccd1`; the harness's power-pad grid must be checked for IR drop, and the core should use a met4 power grid with multiple straps. Per-block clock gating (ICG cells) is expected at backend for the SIMD32s, WMMA, TDM, and AXI/CP when idle; the RTL itself contains no gating (FR-RTL-1).

### Floorplan strategy

- **Core region:** target a 4.5–6.5 mm² core inside the 16.56 mm² user area; place it centrally, leaving the pad ring and routing channels at the frame edges. A 40–60% placement utilization is the bring-up target.
- **LDS at the center** of the core, adjacent to the WMMA, TDM, and both SIMD32s; its 32-bank structure wants a compact, roughly square aspect ratio and short, balanced 32-word buses.
- **WMMA adjacent to the LDS** on one side; the 256 int32 accumulator banks and the 512-MAC datapath are the densest logic, so give it a rectangular region with a short path to the LDS linear port.
- **SIMD32 #0 and #1 flank the LDS** on the other two sides so both lane ports have short, symmetric routes; keep the two SIMDs' VGPR files local to their lanes.
- **Command processor, AXI4-Lite, and AXI4 master on the host/edge side** to minimize the pad-facing routes; the I$ sits between the CP and the two SIMDs so the preload write and the two fetch ports are short.
- **TDM next to the AXI master and the LDS linear port**, since it moves 128-byte blocks between them.
- **No hard macros in this run** (LDS/I$ are flop arrays), so no macro halos are required; reserve 5–10 µm channels between the major blocks and a wider channel along the AXI/pad edge. If production SRAM macros replace the flop arrays, add the macro halos and re-plan the LDS/WMMA adjacency.
- **The top memory arbiter** sits between the CP/AXI master and the WGP, with a dedicated route to the TDM and the SIMD global-memory path.

### Clock tree physical planning

- `clk` enters at GPIO[0] on the reserved pad, goes through the pad receiver and a root buffer at the pad ring, then drives a balanced H-tree to the block roots. Target skew <= 0.5 ns at 100 MHz (10 ns period); insertion delay is not critical because there is a single domain and no CDC.
- Insert ICG cells at the block roots for `simd32` #0/#1, `wmma`, `tdm`, `axi_master`, `axi_lite_slave`/`command_processor`; the ICG enable is the block's idle/busy signal. Keep the ICG cells on the clock spine, not inside the datapath.
- Route the clock on met3/met4 with shielded, double-width wires; keep the clock away from the LDS/WMMA high-activity data buses. Because the maximum routing layer is met4, the clock spine shares met4 with the power grid; plan the power straps first and route the clock in the gaps.
- Reset `rst_n` is synchronous and not a tree-critical signal; distribute it as data-quality logic with a 2-cycle synchronizer/filter at the pad.

### Metal density awareness

- Available: li1, met1–met5, with the harness capping routing at met4. Plan li1/met1 for standard-cell pins and local interconnect, met1–met2 for short signal routes, met3 for the clock and longer signal trunks, met4 for power/ground straps and the top-level clock spine, and treat met5 as harness/pad-layer metal rather than a routing resource.
- The LDS and WMMA are the densest regions; keep their local routing on met1–met3 and reserve met4 for the power grid so IR drop on the ~1.11 A core supply is controlled.
- Insert fill and density fill per layer to meet the shuttle's metal-density targets; check antenna rules on the long AXI and clock routes. Because the design is register-dominated with flop-array memories, expect high standard-cell density in the LDS/WMMA/SIMD regions and plan decap/fill accordingly.
- No triple-width or thick metal is assumed beyond the standard stack; the pad ring and ESD structures are the wrapper's responsibility.

### Tapeout feasibility statement

This soft-IP design is **not directly submittable** to the OPENFRAME shuttle: 581 functional signal bits cannot be carried by 42 usable GPIO pads, and the accelerator's AXI4 master needs an on-die target memory that the single-die shuttle does not provide. The area (4.5–6.5 mm² core in a 16.56 mm² user area) and the power (<=2 W) are feasible. Closing the pad gap requires a hardened wrapper with a serialized host bridge and an on-wrapper AXI4 memory (Option B), which changes the top-level interface and therefore requires explicit user approval; it is out of scope for this run. The selected deliverable is the full-chip-simulation-verified soft IP with the functional interface preserved.