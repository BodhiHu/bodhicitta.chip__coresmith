# CDNA5-M1 — Functional Requirements Document

| Field | Value |
|---|---|
| Product | CDNA5-M1, 0.1 TFLOP/s MXFP4 accelerator (1 WGP / 1 CU / 2x SIMD32) |
| Document | FRD, version 0.1 (architecture baseline) |
| Date | 2026-11-07 |
| Status | Baselined against the frozen RTL contract; measurement coverage is partial |
| Related | `spec/PRD.md`, `spec/ISA.md`, `spec/UARCH.md`, `spec/SAD.md` |

## 1. Scope and conventions

This is the normative, testable requirement set for the CDNA5-M1: the RTL in
`rtl/`, the software in `sw/`, and the verification/physical targets for the
next stages. **Must** / **shall** / **must not** are normative. The M1 is an
RTL bring-up; no gate-level, timing, power, or silicon measurement exists and
none is claimed.

| Label | Meaning |
|---|---|
| `[S]` **specified** | Normative target and acceptance method fixed; no measurement evidence yet |
| `[M]` **measured** | Evidence exists in this repository (Icarus Verilog RTL simulation 2026-11-07, or inspection of the frozen RTL) |
| `[P]` **planned** | Target for a later stage with a fixed measurement method; evidence pending |

## 2. Verification methods

| ID | Method | Tool / artefact |
|---|---|---|
| VM-1 | Directed self-checking RTL simulation | Icarus Verilog: `iverilog -g2005-sv -Irtl rtl/*.v tb/<test>.v; vvp` |
| VM-2 | Assembler + kernel image execution | `sw/asm.py`, `sw/*.s`, `sw/*.hex` loaded into the behavioural AXI slave |
| VM-3 | Static inspection / lint | RTL review; Verilog-2005 lint (verilator `--lint-only` is TODO) |
| VM-4 | Synthesis and area | Yosys with `sky130_fd_sc_hd` liberty; cell count, latch check |
| VM-5 | Static timing analysis | OpenSTA / OpenROAD at 100 MHz, TT/25 C/1.80 V |
| VM-6 | Place-and-route, DRC, LVS | OpenROAD, Magic, netgen |
| VM-7 | Bound-harness measurement | `orchestrator.harness.measure.record("<ID>", value, unit=..., test=...)` into `$CORESMITH_MEASUREMENTS` |
| VM-8 | Cycle-accurate count | Waveform / counter over a defined execution window |

## 3. Functional requirements

### FR-001 — Single clock and synchronous reset `[M]`
**Requirement:** One clock `clk` (100 MHz nominal) and one active-low **synchronous** reset `rst_n`; every register is `always @(posedge clk)`, with no async reset, latch, or tri-state.
**Acceptance:** `rst_n` low for ≥ 2 clocks, released synchronously, reaches a defined state with no X on CSR outputs or instruction memory.
**Verification:** VM-1 (both full-chip tests reset and run), VM-3.

### FR-002 — AXI4-Lite host slave `[M]`
**Requirement:** AXI4-Lite slave (`s_axil_*`), 32-bit data/address, independent AW/W/B and AR/R channels, OKAY responses, no bursts, 4 KB CSR window; `WSTRB` is ignored (full-word writes only).
**Acceptance:** Single writes/reads complete correctly and return programmed values.
**Verification:** VM-1 (`tb_top`, `tb_wmma_top` program all launch CSRs).

### FR-003 — CSR map and reset values `[M]`
**Requirement:** Implement SAD §7 exactly: `CONTROL` 0x00, `STATUS` 0x04, `KERNEL_PC` 0x08, `ARG_PTR` 0x0C, `GRID_X` 0x10, `GRID_Y` 0x14, `GRID_Z` 0x18, `WG_SIZE` 0x1C, `IRQ_EN` 0x20, `CYCLE_LO` 0x24, `CYCLE_HI` 0x28, `WAVE_DONE` 0x2C, `ID` 0x30 read-only `0x43444E35`. Unimplemented addresses read 0, ignore writes.
**Acceptance:** Reset values match SAD §7; RW registers read back; `ID` is constant.
**Verification:** VM-1 (writes/reads exercised); reset-value and `ID` assertions are TODO (`tb_csr`).

### FR-004 — Launch sequencing and I$ preload `[M]`
**Requirement:** A write of 1 to `CONTROL.START` (bit 0) starts one launch. The CP reads eight 128-byte blocks from `KERNEL_PC`, writes all 256 words into the 1 KB instruction RAM, then pulses `wgp_start`; `STATUS.BUSY` is set and `DONE` cleared at launch.
**Acceptance:** A kernel at `KERNEL_PC` executes without further host action; the I$ holds exactly the 256-word image.
**Verification:** VM-1 (both full-chip tests depend on I$ fetch), VM-3.

### FR-005 — Wave initial state `[M]`
**Requirement:** At launch seed `s0=wg_id`, `s1=arg_ptr`, `s2=lds_base=0`, `s3=wg_size`, `s4=lane_base=0`, `PC=0` (word index), `EXEC=(1<<wg_size)-1` (`0xFFFFFFFF` for size 32). VGPRs are undefined; software initialises them.
**Acceptance:** A kernel reading `s0..s4` observes these values.
**Verification:** VM-1 (`tb_top` observes `s0..s2`); `s3`/`s4` test is TODO.

### FR-006 — Wave32 execution and EXEC mask `[S]`
**Requirement:** Each SIMD executes one 32-work-item wave with one PC. Every vector instruction is per-lane gated by `EXEC`; inactive lanes write nothing. `VCC` is per-lane, `SCC` per-wave; `S_SET_EXEC` updates `EXEC`.
**Acceptance:** A partial-`EXEC` kernel writes only enabled lanes; `V_CMP_LT_I32` yields expected `VCC`.
**Verification:** VM-1 (`tb_exec`), VM-3.

### FR-007 — Scalar instruction subset `[M]`
**Requirement:** Implement scalar opcodes 0x00–0x17 per `spec/ISA.md`: moves, integer ALU, shifts, compare (`SCC`), word-relative branches, `S_ENDPGM`, `S_BARRIER` (NOP for one-wave workgroups), `S_WAITCNT`, WG queries, `S_CSR_READ`, `S_SET_EXEC`, `S_TDM_COPY`, `S_WMMA`.
**Acceptance:** Arithmetic and control flow match the ISA; `S_ENDPGM` retires the wave.
**Verification:** VM-1 (`wmma_test` uses a compare/branch loop; `vecadd` uses moves), VM-2.

### FR-008 — Vector integer ALU subset `[M]`
**Requirement:** Implement vector opcodes 0x20–0x2C, 0x3A: move, add/sub, bitwise, shifts, multiply (low 32 bits of signed product), compare, conditional mask, lane-id, read-first-lane.
**Acceptance:** Directed vectors match a reference model for every opcode.
**Verification:** VM-1 (`V_ADD_I32` measured in `vecadd`); other opcodes are a TODO directed test, VM-3.

### FR-009 — Vector dot products `[S]`
**Requirement:** `V_DOT4_I32_IU8` = `vd += Σ(k=0..3) int8(vs0[k])*int8(vs1[k])`; `V_DOT8_I32_IU4` = `vd += Σ(k=0..7) int4(vs0[k])*int4(vs1[k])` using the MXFP4 E2M1 decode `{0,1,2,3,4,6,8,12}` (x2 scaling). Both accumulate into prior `vd`; software zeroes `vd` first.
**Acceptance:** 32-lane result matches a golden integer model; `V_DOT8` matches the matrix-core integer product for the same operands.
**Verification:** VM-1 (`tb_dot`), VM-3.

### FR-010 — F16 / FP32 vector arithmetic is reserved `[M]`
**Requirement:** F16 and FP32 vector arithmetic is **not implemented** in the bring-up RTL. Opcodes 0x34–0x37 (`V_ADD_F16`, `V_MUL_F16`, `V_FMA_F16`, `V_CVT_F16_F32`) and 0x2F (`V_CVT_F32_I32`) must not be used; in the frozen RTL they fall through to a zero result and are not trapped.
**Acceptance:** RTL contains no F16/FP32 datapath; the requirement is a must-not-use contract.
**Verification:** VM-3 (inspection: no `fp16_lane`, no `ENABLE_F16`).

### FR-011 — Local Data Share structure `[M]`
**Requirement:** 4 KB LDS as 32 banks x 32 rows x 32-bit, `bank=addr[6:2]`, `row=addr[11:7]`; two lane ports (one per SIMD, 32 byte-addresses each) and one linear port (32 consecutive words, used by WMMA/TDM, 32-word-aligned word address).
**Acceptance:** Block loads/stores and linear accesses return written data with the defined bank/row mapping.
**Verification:** VM-1 (`tb_wmma`, `tb_wmma_top` exercise TDM/WMMA/V_LDS_LD), VM-3.

### FR-012 — LDS bank-conflict detection `[S]`
**Requirement:** A lane port conflicts when two lane addresses hit the same bank with different rows; a conflicting port is not served and the SIMD raises sticky `error`. Contiguous `V_LDS_*` forms are conflict-free by construction.
**Acceptance:** A conflicting access sets `STATUS.ERROR`, clears `BUSY`, and asserts no `DONE`.
**Verification:** VM-1 (`tb_lds_conflict`), VM-3.

### FR-013 — Global memory block access `[M]`
**Requirement:** `V_MEM_LD`/`V_MEM_ST` move one 128-byte-aligned block; lane *i* accesses word *i* (`addr = sgpr[src] + i*4`). No per-lane coalescing, scatter/gather, or atomics.
**Acceptance:** A 32-lane block load/store round-trips correctly.
**Verification:** VM-1 (`vecadd` loads A/B and stores C), VM-3.

### FR-014 — WMMA matrix instruction `[M]`
**Requirement:** `S_WMMA` computes `C[16][16] (int32) = A[16][32] (MXFP4 E2M1) x B[32][16] (MXFP4 E2M1)`. Descriptor `s[dst..dst+2]` holds A/B/C LDS word bases, all 32-word aligned; A is 64 words, B 64 words, C 256 words. Compute is exactly 16 cycles at 512 FP4 MAC/cycle. In v1 the core computes `C = A*B` (no accumulation into a prior C; ISA says `+=`, so software adds previous C).
**Acceptance:** With A=1.0 (code 0x2), B=2.0 (code 0x4), K=32, every `C[i][j]` equals the integer product sum (256 in the M1 integer pipeline).
**Verification:** VM-1 (`tb_wmma` unit PASS; `tb_wmma_top` full-chip PASS), VM-3.

### FR-015 — TDM 1-D copy `[M]`
**Requirement:** `S_TDM_COPY` copies `len` 32-bit words from a 128-byte-aligned global address to a 32-word-aligned LDS word address, one 128-byte block per 32 words. `len` is a multiple of 32 and ≤ 256 words. No bounds checks, 5-D descriptors, or multicast.
**Acceptance:** 64-word A and B copies land exactly, and the following WMMA produces the expected C.
**Verification:** VM-1 (`tb_wmma_top` PASS), VM-3.

### FR-016 — Workgroup dispatch `[S]`
**Requirement:** `GRID_X` = 1..8 (one workgroup = one wave here), `WG_SIZE` = 1..32. Workgroups go to the two SIMDs, SIMD0 first; two waves run concurrently; the WGP reports `DONE` when all `GRID_X` workgroups retire.
**Acceptance:** A grid of 8 produces 8 correct results and documented `WAVE_DONE` accounting.
**Verification:** VM-1 (`tb_grid8`), VM-3. Current evidence covers only `GRID_X=1`, `WG_SIZE=32`.

### FR-017 — Completion, STATUS, and IRQ `[M]`
**Requirement:** On retirement of all workgroups the CP sets `DONE`, clears `BUSY`, increments `WAVE_DONE`, and raises `irq` (level, held until the next accepted START) if `IRQ_EN[0]=1`. A new launch clears `DONE`/`ERROR` and sets `BUSY`. An error clears `BUSY`, sets `ERROR`, and raises no `irq`.
**Acceptance:** Both full-chip tests observe `irq` and `STATUS.DONE=1`.
**Verification:** VM-1 (`tb_top`, `tb_wmma_top`), VM-3.

### FR-018 — Cycle counter `[S]`
**Requirement:** 64-bit free-running counter incremented every `clk`, readable as `CYCLE_LO`/`CYCLE_HI` and via `S_CSR_READ` (`imm[0]` selects the high word); resets to 0.
**Acceptance:** Reads advance monotonically and match the reference clock count.
**Verification:** VM-1 (`tb_cycle`), VM-3.

### FR-019 — Error reporting `[S]`
**Requirement:** `STATUS.ERROR` is sticky until the next launch. The only implemented source is an LDS bank conflict; there is **no** illegal-opcode trap and unknown opcodes must not be relied on to fault.
**Acceptance:** Conflict injection sets `ERROR=1`, stops the wave, and a new launch clears it.
**Verification:** VM-1 (`tb_lds_conflict`), VM-3.

### FR-020 — Instruction encoding and assembler `[M]`
**Requirement:** Instructions are one 32-bit word (literal forms add a second), layout `opcode[31:26] | I[25] | dst[24:20] | src0[19:15] | src1[14:10] | src2[9:5] | flags[1:0]`. `sw/asm.py` emits the little-endian 256-word image. `flags` (negate/abs) is defined but **not implemented**; encode `00`.
**Acceptance:** Assembled kernels execute correctly; image is exactly 256 words.
**Verification:** VM-2 (`sw/vecadd.hex`, `sw/wmma_test.hex`), VM-1.

### FR-021 — Register files `[M]`
**Requirement:** 16 VGPRs per lane (2 KB per SIMD) and 32 SGPRs per wave (128 B); indices alias modulo the file size.
**Acceptance:** `VGPR_NUM=16`, `SGPR_NUM=32`; no array out-of-bounds access in simulation.
**Verification:** VM-3 (inspection), VM-1.

### FR-022 — Instruction memory `[M]`
**Requirement:** 1 KB instruction RAM (256 x 32-bit) with two read ports (one per SIMD). PC is an 8-bit word index; branches are word-relative to the next PC. No cache, miss handling, or fetch backpressure beyond the 2-cycle fetch pipeline.
**Acceptance:** Branches stay in 0..255; both SIMDs fetch independently.
**Verification:** VM-1 (`wmma_test` loop), VM-3.

### FR-023 — AXI4 master `[M]`
**Requirement:** AXI4 `m_axi_*`, 128-bit data, 32-bit address, INCR bursts of `len=7` (8 beats x 16 B = 128 B), `AxSIZE=4`, one outstanding transaction, 128-byte-aligned addresses; no exclusive, atomic, or unaligned accesses.
**Acceptance:** The behavioural AXI slave completes all bursts with correct `WLAST`/`RLAST` and data assembly.
**Verification:** VM-1 (`tb_top` counts 10 AR bursts and 80 R beats), VM-3. AXI protocol checker is TODO.

### FR-024 — Arbitration and ordering `[M]`
**Requirement:** Fixed priority: top level CP (I$ preload) above the WGP; inside the WGP SIMD0 > SIMD1 > TDM for global memory and SIMD0 lane port > SIMD1 lane port > linear port for LDS. WMMA and TDM are mutually exclusive.
**Acceptance:** A launch is never starved by kernel traffic; both SIMDs can use LDS without corruption.
**Verification:** VM-3 (inspection), VM-1.

### FR-025 — Determinism and forward progress `[M]`
**Requirement:** For a supported launch every FSM reaches a terminal state (`S_ENDPGM`/`DONE`) in bounded time; no tested kernel deadlocks; identical inputs give identical outputs.
**Acceptance:** All current tests PASS deterministically on repeated runs.
**Verification:** VM-1 (all current tests), VM-3.

## 4. Performance requirements

Peak values are execution-window limits; sustained values include bring-up RTL
serialisation. All at 100 MHz.

### PERF-001 — Matrix peak 102.4 GFLOP/s `[S]`
8192 MAC per `S_WMMA` in exactly 16 compute cycles = 512 MAC/cycle = 1024 FLOP/cycle = **102.4 GFLOP/s**. Acceptance: cycle-counted window over back-to-back WMMAs with LDS-resident operands, within ±1%. **Verification:** VM-8/VM-7; structural confirmation in `rtl/wmma.v`.

### PERF-002 — Vector FP4 peak 102.4 GFLOP/s `[S]`
One `V_DOT8_I32_IU4` retires 32 lanes x 8 MAC = 256 MAC per SIMD per EXEC cycle; two SIMDs = 512 MAC/cycle = **102.4 GFLOP/s**. Acceptance: measured over EXEC cycles of a dot microbenchmark, ±1%. **Verification:** VM-8/VM-7. The SIMD issues one instruction per 4 cycles, so sustained vector FP4 is 25.6 GFLOP/s.

### PERF-003 — INT8 peak 51.2 GOPS `[S]`
One `V_DOT4_I32_IU8` retires 32 lanes x 4 MAC = 128 MAC per SIMD per EXEC cycle; two SIMDs = 256 MAC/cycle = 512 ops/cycle = **51.2 GOPS** (2 ops/MAC). **Verification:** as PERF-002. Sustained at 4-cycle issue: 12.8 GOPS.

### PERF-004 — Matrix sustained ≥ 51.2 GFLOP/s `[P]`
WMMA cadence is 7 cycles A/B load (4 load beats + 3 `S_LW` gaps), 16 compute, 8 store, 1 done = 32 cycles per 8192 MAC = 256 MAC/cycle = **51.2 GFLOP/s** for one core with no overlap. Acceptance: ≥ 64 back-to-back WMMAs, ≥ 51.2 GFLOP/s. **Verification:** VM-8/VM-7.

### PERF-005 — AXI4 bandwidth 1.6 GB/s peak `[S]`
128 bits x 100 MHz = **1.6 GB/s** peak; with one outstanding 128-byte burst and ~2-cycle cooldown, expected sustained ≈ 1.1–1.2 GB/s. Acceptance: ≥ 64 bursts, measured ≥ 1.0 GB/s. **Verification:** VM-8/VM-7.

### PERF-006 — LDS bandwidth 12.8 GB/s `[S]`
One 32-word (128-byte) access per cycle across the shared banks = **12.8 GB/s**; the three ports are arbitrated, not simultaneous. **Verification:** VM-8/VM-7 (LDS microbenchmark).

### PERF-007 — Vector-add latency ≤ 1024 clocks `[M]`
End-to-end from accepted `CONTROL.START` to `irq` for UC-1. **Measured: 446 clocks** from START = **485 clocks** from reset release (instrumented bench, same RTL; 4.85 µs at 10 ns). Acceptance ≤ 1024. **Verification:** VM-1/VM-8.

### PERF-008 — Matrix kernel latency ≤ 2048 clocks `[M]`
End-to-end for UC-2 (`tb_wmma_top`: preload, 2 TDM copies, 1 WMMA, 256-word readback). **Measured: 996 clocks** from START = **1035 clocks** from reset release (instrumented; 10.35 µs). Acceptance ≤ 2048. **Verification:** VM-1/VM-8.

### PERF-009 — I$ fetch bandwidth `[S]`
Each I$ read port delivers one 32-bit word per cycle = **400 MB/s per SIMD** (800 MB/s aggregate). Acceptance: port microbenchmark, ±5%. **Verification:** VM-8/VM-7.

## 5. Timing requirements

### TIME-001 — 100 MHz single clock `[P]`
Close timing at 100 MHz (10.0 ns) on `sky130_fd_sc_hd`, TT/25 C/1.80 V, WNS ≥ 0 after P&R. Acceptance: OpenSTA report on the final netlist with SPEF. **Verification:** VM-5/VM-6. No STA run exists; the 512-MAC combinational WMMA tree is the main risk.

### TIME-002 — Synchronous reset timing `[M]`
`rst_n` is sampled on `posedge clk`, asserted ≥ 2 clocks and released synchronously; no async reset path. Acceptance: the 4-clock-low reset in both benches yields no X or spurious launch. **Verification:** VM-1/VM-3.

## 6. Area and power requirements

### AREA-001 — Core area ≤ 6.0 mm² `[P]`
Standard cells + LDS flops, excluding pad ring. Budget ~340 k cells: SIMD 180 k, WMMA 90 k, LDS 30 k flops, TDM/I$/CP 25 k, AXI/CSR 15 k. Acceptance: Yosys/OpenROAD area ≤ 6.0 mm². **Verification:** VM-4/VM-6. Early `syn/lds` runs are incomplete; the 3-port LDS register array is the main area risk (SRAM macro may be required).

### AREA-002 — Die area ≤ 16 mm² `[P]`
≤ 4.0 x 4.0 mm including pad ring. **Verification:** VM-6 (floorplan/DRC report).

### PWR-001 — Active power ≤ 1.0 W `[P]`
At 1.8 V, 100 MHz, TT/25 C, typical mixed vector+matrix activity. Acceptance: OpenROAD/OpenSTA power ≤ 1.0 W. **Verification:** VM-5/VM-6. No power measurement exists.

### PWR-002 — Standby power ≤ 50 mW `[P]`
Clock-gated idle (no launch, no memory traffic). **Verification:** VM-5/VM-6.

## 7. Traceability to the PRD

| PRD use case | Requirements | Performance / timing |
|---|---|---|
| UC-1 vector add | FR-002..FR-005, FR-007, FR-008, FR-013, FR-017, FR-020, FR-021, FR-023, FR-024 | PERF-007, TIME-002 |
| UC-2 MXFP4 matmul | FR-011, FR-012, FR-014, FR-015, FR-017, FR-020, FR-024 | PERF-001, PERF-004, PERF-008 |
| UC-3 TDM tiling | FR-011, FR-015, FR-016 | PERF-005, PERF-006 |
| Headline 0.1 TFLOP/s | FR-014 (matrix), FR-009 (vector FP4/INT8) | PERF-001..PERF-004 |
| Host control | FR-002, FR-003, FR-004, FR-017, FR-018 | TIME-001 |

## 8. Measured evidence register (2026-11-07)

| Test | Command (from `designs/cdna5-m1`) | Result | Notes |
|---|---|---|---|
| `tb_top` (UC-1, full chip) | `iverilog -g2005-sv -Irtl -o /tmp/tb_top.vvp rtl/*.v tb/tb_top.v && vvp /tmp/tb_top.vvp` | **PASS**, vecadd 32/32 lanes | 446 clocks START→IRQ = 485 from reset (instrumented) |
| `tb_wmma` (WMMA unit) | `iverilog -g2005-sv -Irtl -o /tmp/tb_wmma.vvp rtl/*.v tb/tb_wmma.v && vvp /tmp/tb_wmma.vvp` | **PASS**, C=256 for A=1.0, B=2.0, K=32 | Uses a real `lds` instance |
| `tb_wmma_top` (UC-2, full chip) | `iverilog -g2005-sv -Irtl -o /tmp/tb_wmma_top.vvp rtl/*.v tb/tb_wmma_top.v && vvp /tmp/tb_wmma_top.vvp` | **PASS**, 256/256 C words | 996 clocks START→IRQ = 1035 from reset (instrumented) |

The PASS strings printed by the in-repo benches report loop indices, not
elapsed clocks (e.g. "32 cycles", "256 cycles"); the real latencies above come
from an instrumented copy of the same benches with the same RTL. Fixing the
bench reporting is a TODO.

## 9. Known deviations and document mismatches

| ID | Deviation | Where documented | Action |
|---|---|---|---|
| DEV-01 | WMMA computes `C = A*B`, not `C += A*B` (ISA says `+=`) | ISA §Matrix core, UARCH §wmma | Software adds prior C; reconcile in v0.2 |
| DEV-02 | F16/FP32 vector ops (0x34–0x37, 0x2F) not implemented and not trapped | UARCH §valu claims `fp16_lane`/`ENABLE_F16=1` — stale | Keep reserved; trap or delete in v0.2 |
| DEV-03 | No illegal-opcode detection (UARCH says error latches on illegal opcode) | UARCH §simd32 | Add trap in v0.2 or state "undefined" |
| DEV-04 | `WAVE_DONE` increments once per completed **launch**, not per wave | UARCH CSR table says "completed waves" | Fix counter or rename CSR |
| DEV-05 | `CONTROL.SOFT_RESET` (bit 1) is stored/read back but has no function | UARCH CSR table | Implement in v0.2 or mark reserved |
| DEV-06 | AXI4-Lite `WSTRB` is ignored; only full-word writes work | — | Documented here |
| DEV-07 | TDM is 1-D, no bounds checks; `len` multiple of 32, ≤ 256 by contract | UARCH §tdm | 5-D TDM is future work |
| DEV-08 | Arbitration is fixed priority (CP > WGP; SIMD0 > SIMD1 > TDM), not round-robin | UARCH §axi_master says "round-robin" — stale | Fix UARCH text |
| DEV-09 | LDS conflicts abort the wave with `ERROR` instead of serialising | UARCH §lds (consistent) | Software must use conflict-free patterns |
| DEV-10 | I$ is a 1 KB preload RAM, not a cache; no miss handling | UARCH §instruction fetch (consistent) | Production I$ is future work |
| DEV-11 | WMMA operands are LDS-resident, not VGPR-based as in CDNA5 | UARCH §wmma (consistent) | Bring-up staging choice |
| DEV-12 | No hardware MXFP4 E8M0 block scale; int32 C is 4x the nominal product (2x operand decode squared) | ISA §Data formats (consistent) | Software post-scales |
| DEV-13 | In-repo benches print loop indices as "cycles" | `tb/tb_top.v`, `tb/tb_wmma_top.v` | Fix reporting in a TB cleanup |
| DEV-14 | Instruction `flags[1:0]` (negate/abs) defined but not implemented | ISA §Instruction encoding | Encode `00`; implement or delete in v0.2 |
| DEV-15 | UARCH says WMMA loads A/B in 4 cycles; the FSM is 4 load beats + 3 `S_LW` gaps = 7 cycles | UARCH §wmma | Fix UARCH cycle budget |

## 10. Open verification items (TODO)

1. `tb_csr`: reset values, `ID=0x43444E35`, RW read-back, unimplemented addresses, `WSTRB`.
2. `tb_exec`: `wg_size < 32`, `S_SET_EXEC`, partial `EXEC`, `VCC`.
3. `tb_grid8`: `GRID_X=8`, two concurrent SIMDs, `WAVE_DONE` accounting.
4. `tb_dot`: `V_DOT4`/`V_DOT8` vs golden model, including negative FP4 codes.
5. `tb_lds_conflict`: conflict -> `ERROR`, no `DONE`, next launch clears error.
6. AXI protocol checker/VIP; backpressure and error-response tests.
7. WMMA cadence and peak-rate measurements (PERF-001/004).
8. Full-chip synthesis with area report and latch check (VM-4).
9. 100 MHz STA with SPEF and power report (TIME-001, PWR-001).
10. Multi-tile TDM/WMMA kernel to exercise tiling beyond one 16x16x32 tile.
