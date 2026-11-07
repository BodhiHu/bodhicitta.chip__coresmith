# FRD — CDNA5-M1 0.1 TFLOP/s MXFP4 AI Accelerator on Sky130

| Field | Value |
|---|---|
| Document | Functional Requirements Document (FRD), revision 1.0 |
| Product | CDNA5-M1: 1 WGP / 1 CU / 2x SIMD32 / 4 KB LDS / WGP-shared 16x16x32 MXFP4 matrix core |
| Technology | SkyWater Sky130A, `sky130_fd_sc_hd`, `tt_025C_1v80`, 1.8 V, Yosys/OpenROAD |
| Clock | Single 100 MHz clock, active-low synchronous reset (FR-CLK-1, CON-2) |
| Deliverable | Synthesizable Verilog-2005 soft IP `chip_top`, verified by full-chip simulation |
| Authoritative inputs | PRD rev 1.0, SAD rev 1.0, `spec/ISA.md`, `spec/UARCH.md` |
| Shuttle | OPENFRAME, 3520 x 5188 µm die, 3320 x 4988 µm user area, 44 pads / 42 usable |

**Requirement authority.** The PRD and the SAD records are the contract for this
document. Every hard numeric bound below cites its originating PRD requirement
(FR-, KPI-, CON-, parameter) or SAD decision (AD-). Numbers marked *advisory*
are planning estimates and are not pass/fail bounds. This FRD answers "how
well should the functionality work"; the functional behavior itself (what the
chip does) is fixed by the PRD functional requirements and is only restated
here as measurable criteria.

## Requirement Authority, Scope, and Traceability

### Hard bounds used in this document

| Bound | Value | Units | Originating requirement | FRD item |
|---|---|---|---|---|
| Matrix peak throughput | 102,400,000,000 (1.024e11) | flop/s | FR-PERF-1, KPI-001 | PERF-001 |
| Matrix sustained throughput | >= 92,160,000,000 (9.216e10) | flop/s | FR-PERF-2, KPI-PERF-001 | PERF-002 |
| MFMA issue cadence | 16 | cycles/16x16x32 op | FR-PERF-1, PRD `mfma_cycles_per_op` | PERF-003 |
| AXI4 feed (each direction) | 12,800 (1.28e10) | Mbit/s | PRD `speed_and_feeds.input/output_data_rate_mbps` | PERF-004 |
| SIMD32 integer lane width | 32 | lane-ops/cycle/SIMD | FR-CORE-5 | PERF-005 |
| LDS aggregate feed | 12,800,000,000 (1.28e10) | byte/s | PRD `speed_and_feeds` ("32 words/cycle x 32 bits") | PERF-006 |
| Clock | 100 (10 ns period) | MHz | FR-CLK-1, CON-2 | TIME-001 |
| Reset hold | >= 2 | cycles | SAD `Clocking and reset` (FR-CLK-1) | TIME-002 |
| MFMA drain | 8 | cycles | SAD AD-3 | TIME-005 |
| LDS | 4096; 32 banks x 32 rows x 32 bits | bytes | FR-MEM-1 | IFACE-004 |
| Instruction RAM | 1024; 256 x 32-bit; 2 read ports | bytes | FR-MEM-2 | IFACE-005 |
| AXI4 master | 128-bit data, 32-bit address, INCR8, 1 outstanding | — | FR-MEM-4 | IFACE-002 |
| Grid / workgroup | 1–8 workgroups; 1–32 work-items | — | FR-EXEC-1 | INV-011 |
| Standard-cell cap | <= 500,000 (LDS/I$ excluded) | cells | CON-4 | PHYS-006 |
| Core area | 4.0–8.0 (ceiling 8.0 enforced) | mm² | CON-4 | PHYS-002 |
| Power | <= 2,000 | mW | CON-4 | PHYS-009 |
| Functional interface | 581 | signal bits | SAD pin table, AD-19 | IFACE-002/003 |
| Shuttle pads | 44 total, 42 usable (GPIO[0]=clk, GPIO[1]=rst) | pads | OPENFRAME constraints | PHYS-001, MPW-006 |

### PRD functional requirement coverage

| PRD requirement | FRD items that make it measurable |
|---|---|
| FR-CORE-1 (1 WGP, 1 CU, 2x SIMD32, wave32, one PC, EXEC) | INV-008, INV-011, IFACE-006 |
| FR-CORE-2 (16 VGPR/lane, 32 SGPR/wave, VCC, SCC, EXEC masking) | INV-008, IFACE-006 |
| FR-CORE-3 (WGP-shared 16x16x32 core, 8192 MAC, 512 MAC/cycle, 16-cycle cadence) | PERF-001, PERF-003, INV-003 |
| FR-CORE-4 (E2M1 decode, exact int32, scale outside the MAC tree) | INV-001, INV-009 |
| FR-CORE-5 (2x SIMD32 integer path; no F16/FP32 vector arithmetic) | PERF-005, IFACE-006 |
| FR-MEM-1 (4 KB LDS, 32 banks x 32 rows, 2 lane + 1 linear port) | IFACE-004, INV-002, INV-007, PERF-006 |
| FR-MEM-2 (1 KB I$, 256 x 32, two read ports, host preload) | IFACE-005, INV-005 |
| FR-MEM-3 (1-D TDM, 32-word units, 128 B / 32-word alignment) | PERF-007, INV-010 |
| FR-MEM-4 (AXI4 128-bit, 32-bit address, INCR8, one outstanding) | IFACE-002, INV-006 |
| FR-HOST-1 (AXI4-Lite CSR: CONTROL, STATUS, KERNEL_PC, ARG_PTR, GRID_X/Y/Z, WG_SIZE, IRQ_EN, CYCLE, WAVE_DONE) | IFACE-003 |
| FR-HOST-2 (preload I$, start grid, DONE/BUSY, WAVE_DONE, level IRQ) | INV-004, TIME-003, TIME-006 |
| FR-HOST-3 (launch parameters latched at CONTROL.START) | INV-004 |
| FR-EXEC-1 (1–8 workgroups, 1–32 work-items, one wave32 each) | INV-011, INV-004 |
| FR-EXEC-2 (frozen 32-bit ISA subset; not gfx-compatible) | IFACE-006 |
| FR-EXEC-3 (S_ENDPGM completion counted in WAVE_DONE) | INV-004 |
| FR-CLK-1 (single 100 MHz domain, active-low synchronous reset) | TIME-001, TIME-002, IFACE-001 |
| FR-RTL-1 (Verilog-2005, no latches/tri-states, Yosys/OpenROAD) | PHYS-013 |
| FR-PERF-1 (102.4 GFLOP/s peak) | PERF-001, PERF-003 |
| FR-PERF-2 (>= 92.16 GFLOP/s sustained, LDS-fed) | PERF-002, PERF-006 |
| FR-VER-1 (self-checking WMMA, full-chip vector add, full-chip matmul) | Testability; INV-001, INV-012; MISSION-ACC-001 |

### PRD validation KPI coverage

| KPI | Threshold | Deriving FRD item |
|---|---|---|
| KPI-001 (matrix peak) | 102.4 GFLOP/s = 1.024e11 flop/s | PERF-001 |
| KPI-CORR-001 (full 16x16x32 matmul) | all 256 int32 C words byte-exact | INV-001, INV-002, INV-003, MISSION-ACC-001 |
| KPI-FUNC-001 (full-chip 32-lane vector add) | all 32 lane results exact; DONE=1; IRQ | INV-012, MISSION-ACC-001 |
| KPI-PERF-001 (LDS-fed sustained) | >= 90% of peak, 92.16 GFLOP/s | PERF-002 |

### Requirement corrections and interpretations adopted

1. **PVT/clock.** 100 MHz, `tt_025C_1v80`, 1.8 V, `sky130_fd_sc_hd` are fixed (CON-1, CON-2, FR-CLK-1). No other corner is a pass criterion in this run.
2. **Peak definition.** 1 TFLOP/s = 1e12 FLOP/s; 0.1 TFLOP/s = 1.024e11 FLOP/s here, consistently with KPI-001. The 16x16x32 operation is 8192 MAC = 16,384 FLOP at 2 FLOP/MAC.
3. **`C = A*B` vs `C += A*B`.** SAD AD-8 fixes the hardware operation as `C = A*B` per 16x16x32 MFMA; cross-K accumulation is software int32 addition. `spec/ISA.md` and `spec/UARCH.md` line 141 still say `C += A*B`; that prose is superseded for the FRD and must be corrected at its source in the ISA/UARCH docs. INV-001, INV-003 and MISSION-ACC-001 assume AD-8.
4. **WAVE_DONE.** FR-EXEC-3 requires per-retired-workgroup counting (`GRID_X = 8` => `WAVE_DONE = 8`); the legacy RTL counts once per launch. INV-004 encodes the required behavior (SAD AD-13).
5. **I$ preload path.** "Host preloads the I$" and "the command processor preloads the I$" are reconciled by SAD AD-12: the host places the image in global memory at `KERNEL_PC`; the CP performs the eight INCR8 reads. IFACE-003/005 and INV-005 follow AD-12; no CSR aperture is added.
6. **Die area.** The PRD bound is 4.0–8.0 mm² (CON-4). The OPENFRAME carrier is a fixed 3520 x 5188 µm (18.262 mm²) die. Per SAD "Die area budget", the 4.0–8.0 mm² figure is applied to the core footprint (standard cells plus banked memories, pad ring excluded); the carrier is the shuttle frame. If the human intended the entire die including pad ring to be 4.0–8.0 mm², that is unsatisfiable on OPENFRAME and must be renegotiated — PHYS-002 states both readings explicitly.
7. **Latency.** No host-visible latency budget exists (PRD `latency_budget_us = null`, SAD Q-2/interpretation 5). PERF/TIME items never turn the 1,035-cycle (~10.35 µs) acceptance run into a pass/fail ceiling; it is measured and reported (TIME-004).
8. **Vector dot products.** No vector FP4/INT8 dot-product throughput is required (PRD Q-3, SAD AD-18). The ISA may retain `V_DOT4_I32_IU8`/`V_DOT8_I32_IU4` as implementation extras; they carry no FRD performance bound. PERF-005 bounds only the 32-lane integer VALU datapath required by FR-CORE-5.
9. **Functional interface gap.** The SAD pin table enumerates 581 functional signal bits and AD-19 keeps the interface intact. The current RTL top `cdna5_m1_top` exposes 527 bits: it omits `m_axi_awid[3:0]`, `m_axi_awlock`, `m_axi_awcache[3:0]`, `m_axi_awprot[2:0]`, `m_axi_awqos[3:0]`, `m_axi_awregion[3:0]` and the matching AR ID/lock/cache/prot/qos/region fields, plus `s_axil_awprot[2:0]`/`s_axil_arprot[2:0]` and the `bid`/`rid` inputs (54 bits). IFACE-002/003 transcribe the SAD contract; closing the 54-bit gap (wiring the optional sidebands, tied per AD-10) or formally amending the SAD is a required action, not a silent deviation.
10. **Memory implementation.** LDS and I$ are flop arrays in this run (CON-5); production may use Sky130 1R1W SRAM macros (Q-1). PHYS-007/008 bound the banked implementation; a flat 1024x32 array (~3.3M cells) is rejected (AD-16).

---

## Performance Requirements

1. **ID**: PERF-001
   - **Requirement**: The WGP-shared matrix core delivers the PRD peak of 102.4 GFLOP/s: one 16x16x32 MXFP4 MFMA (8192 MAC = 16,384 FLOP) issued every 16 cycles at 100 MHz, i.e. 512 MAC/cycle = 1024 FLOP/cycle = 1.024e11 FLOP/s. [HARD, FR-PERF-1, KPI-001]
   - **Acceptance criteria**: Run N = 64 back-to-back MFMA descriptors with A/B resident in LDS and the C ping-pong banks active; measure the interior window from completion of operation 0 to completion of operation 64 (this excludes the first pipeline fill and the final 8-cycle drain, so the number is the steady-state cadence, not an ideal lower bound). Measured flop/s = 64 x 16,384 x 100,000,000 / cycles_interior must be >= 102,400,000,000. Record with `orchestrator.harness.measure.record("PERF-001", value, unit="flop/s", test="wmma_peak_back_to_back")`. Pass only on the measured receipt; a simulation harness that reports an unmeasured or modelled-only value fails the item.
   - **Priority**: must_have
   - **Metric**: flops; min 102400000000; max -; unit flop/s
   - **Model check**: SystemC LT `wmma` model, scenario `wmma_peak_back_to_back`: the harness issues 64 descriptors, the model timestamps descriptor accept and done, and the LT cycle accounting uses the declared 16-cycle compute plus the one-deep descriptor queue; the model must report >= 102.4 GFLOP/s on the same interior window. LT cycles stand in for RTL cycles at 10 ns/cycle; because LT omits gate delay, a model value inside [1.024e11, 1.03e11] is the meaningful band (0.5% margin) and any value below 1.024e11 is a fail, not noise.
   - Measurement detail: cycles are counted at the `wmma_req`/`wmma_done` handshakes of the WMMA block; the stimulus is the A/B tiles of acceptance case `mxfp4_gemm_16x16x256_grid8` replayed 8 times per tile.

2. **ID**: PERF-002
   - **Requirement**: Sustained matrix throughput is at least 90% of peak, i.e. >= 92.16 GFLOP/s (9.216e10 FLOP/s), when A/B operands are fed from LDS, including TDM refill traffic and C-store traffic sharing the LDS linear port. This is an average cadence of at most 17.78 cycles per 16x16x32 MFMA. [HARD, FR-PERF-2, KPI-PERF-001]
   - **Acceptance criteria**: Issue N = 256 MFMA descriptors in a loop with A/B double-buffered by the TDM (4 chunks per K-block, A/B ping-pong per SAD AD-6) and the C tile stored to LDS each operation. Measure the amortized window from completion of operation 8 to completion of operation 256 (drain amortized, first fill excluded). Measured flop/s must be >= 92,160,000,000 and the reported average cycles/op must be <= 17.78. Record with `measure.record("PERF-002", value, unit="flop/s", test="wmma_sustained_lds_fed")`. Both the RTL receipt and the arbiter grant trace (INV-007) must accompany the value.
   - **Priority**: must_have
   - **Metric**: flops; min 92160000000; max -; unit flop/s
   - **Model check**: SystemC LT `wmma` + `lds` + `tdm` models, scenario `wmma_sustained_lds_fed`: 256 descriptors with TDM refills; the model cycle accounting is 16 compute cycles + 8 overlapped C-store cycles + the 12-of-16 linear-port reservation. LT cycles stand in for RTL cycles. Because the LT arbiter is an approximation, require the model value >= 96,768,000,000 (5% guard over 92.16e9); a model pass exactly at 92.16e9 with the arbitration model disabled is not sufficient evidence.

3. **ID**: PERF-003
   - **Requirement**: The matrix core accepts and completes one 16x16x32 MFMA per 16-cycle slot in steady state, and the one WGP-shared core is shared by both SIMD32 units (one operation at a time). The hard cadence is 16 cycles/op (PRD parameter `mfma_cycles_per_op` min = max = 16). [HARD, FR-PERF-1, FR-CORE-3, AD-2/AD-3]
   - **Acceptance criteria**: With 64 back-to-back descriptors from one or both SIMDs, measure the interval between consecutive `wmma_done` pulses over the interior window. Report mean, maximum, and the count of intervals > 16 cycles. Pass when mean <= 16.0 cycles/op and max <= 17 cycles/op (one cycle of queue slack) for the steady-state window, and the amortized cadence including the final drain over N >= 2 operations is <= 17.78 cycles/op. Record with `measure.record("PERF-003", mean_cycles, unit="cycles", test="wmma_cadence")`.
   - **Priority**: must_have
   - **Metric**: cycles; min -; max 16; unit cycles
   - **Model check**: SystemC LT `wmma` model, scenario `wmma_cadence`: descriptor accept/done timestamps over 64 operations; the model must report mean <= 16.0 cycles and max <= 17 cycles (LT may show a one-cycle queue edge, which is within the 17.78-cycle amortized bound and inside the declared margin).

4. **ID**: PERF-004
   - **Requirement**: The AXI4 global-memory master sustains the PRD feed of 12,800 Mbit/s (1.28e10 bit/s = 1.6 GB/s = 128 bits x 100 MHz) in each direction in 128-byte INCR8 bursts. [HARD, PRD `speed_and_feeds.input_data_rate_mbps` and `output_data_rate_mbps`, FR-MEM-4]
   - **Acceptance criteria**: Read direction: a TDM copy of 64 x 128-byte blocks (512 R beats) against an always-ready, zero-latency AXI target; measure the data phase from the first R beat to the last R beat and require 8 beats in 8 consecutive cycles per burst, i.e. >= 12,800 Mbit/s during the data phase. Write direction: a `V_MEM_ST` sequence of 64 blocks (512 W beats) with the same requirement. Separately report the end-to-end rate including AR/AW handshake and B/R response turnaround; that end-to-end number is advisory (one outstanding transaction per FR-MEM-4) and is not the PERF-004 bound. Record with `measure.record("PERF-004", bits_per_s, unit="bit/s", test="axi_feed_read" / "axi_feed_write")`.
   - **Priority**: must_have
   - **Metric**: bit/s; min 12800000000; max -; unit bit/s
   - **Model check**: SystemC LT AXI BFM, scenarios `axi_feed_read`/`axi_feed_write`: the model delivers one 128-bit beat per cycle while ready and reports the same burst count (64 INCR8) and addresses; the data-phase rate is computed from the model's beat timestamps. LT service time stands in for RTL; the model must also report the end-to-end rate with the declared response latency, and the model verdict on the data-phase bound is meaningful only with the burst count exact.

5. **ID**: PERF-005
   - **Requirement**: Each SIMD32 executes the integer vector path at 32 lanes per cycle: for single-cycle integer VALU operations (V_ADD_I32 and the integer/bitwise class) the execution stage retires one 32-lane opcode per cycle per SIMD32, so two SIMD32 units provide 64 lane-ops/cycle (6.4 Gops/s aggregate at 100 MHz). The 6.4 Gops/s aggregate is a derived number (advisory, PRD Q-3); the 32-lane-per-cycle datapath is the hard FR-CORE-5 requirement. [HARD, FR-CORE-5; derived aggregate advisory]
   - **Acceptance criteria**: Per SIMD, execute 1024 back-to-back register-only integer VALU operations (no LDS/global dependency, EXEC = 0xFFFFFFFF); measure the execution-stage retire rate and require >= 32 lane-ops/cycle (1 opcode/cycle) per SIMD and >= 2 opcodes/cycle aggregate with one wave on each SIMD. Also report the end-to-end instruction issue rate (fetch/decode included) as advisory. Record with `measure.record("PERF-005", lane_ops_per_cycle, unit="lane-ops/cycle", test="valu_exec_rate")`.
   - **Priority**: must_have
   - **Metric**: lane_ops_per_cycle; min 32; max -; unit lane-ops/cycle
   - **Model check**: SystemC LT `simd32` model, scenario `valu_exec_rate`: 1024 register-only VALU ops per SIMD; the model retires one opcode/cycle in the EXEC state and reports 32 lane-ops/cycle/SIMD. LT cycles stand in for RTL; the model must not be credited for an idealized 0-latency fetch (the advisory end-to-end number is reported separately).

6. **ID**: PERF-006
   - **Requirement**: The LDS serves one 32-word (128-byte) grant per cycle, i.e. 32 words x 32 bits x 100 MHz = 12.8 GB/s aggregate, and the port arbiter reserves the matrix core 12 grants per 16-cycle slot (4 operand reads + 8 C-store grants) while back-to-back MFMA is active, provides the TDM at least 2 grants per 16 cycles when it has pending traffic, and leaves the remainder to the two lane ports without starvation. [HARD, PRD `speed_and_feeds`, FR-MEM-1, AD-5, SAD S8]
   - **Acceptance criteria**: Over a 1024-cycle mixed workload (back-to-back MFMA + TDM refill + lane traffic), count grants per master from the S8 grant trace. Pass when (a) aggregate sustained grants >= 1.0 grant/cycle (12.8 GB/s), (b) every complete 16-cycle window with back-to-back MFMA gives the WMMA >= 12 grants, (c) the TDM receives >= 2 grants per 16 cycles whenever it is requesting, and (d) no requesting master waits more than 64 consecutive cycles. Record with `measure.record("PERF-006", bytes_per_s, unit="byte/s", test="lds_mixed_grant_trace")`.
   - **Priority**: must_have
   - **Metric**: byte/s; min 12800000000; max -; unit byte/s
   - **Model check**: SystemC LT `lds` + arbitration model, scenario `lds_mixed_grant_trace`: per-cycle grant records (master, address, read/write); the harness recomputes (a)–(d) from the model trace. The model must implement the 12/2 reservation or the item is a fail; LT grant timing stands in for RTL with the declared 5% guard on the aggregate rate.

7. **ID**: PERF-007
   - **Requirement**: The 1-D TDM stages one 32-word (128-byte) LDS row per AXI INCR8 burst: a copy of `len` words issues exactly `len/32` bursts of 8 beats, writes exactly `len/32` LDS rows through the linear port, and lands chunk n before chunk n+1 with a 128-byte contiguous source address. This is the FR-MEM-3 copy contract; throughput is measured, not capped (no latency budget, Q-2). [HARD, FR-MEM-3, CON-6]
   - **Acceptance criteria**: Execute `S_TDM_COPY` with `len = 256` words (maximum) from a 128-byte-aligned source to a 32-word-aligned LDS destination against an always-ready AXI target. Pass when exactly 8 AR handshakes (INCR8, `arlen = 7`, `arsize = 4`) are issued, 8 LDS rows are written, the source addresses are 0x80 apart and increasing, the destination rows are contiguous, and no write occurs outside `[dst, dst + len)`. Report the measured copy cycles; with a zero-latency target the data phase is 8 beats per chunk and the burst-to-burst period is measured (advisory). Record with `measure.record("PERF-007", chunks_per_cycle, unit="chunk/cycle", test="tdm_256_word_copy")`.
   - **Priority**: must_have
   - **Model check**: SystemC LT `tdm` + AXI BFM, scenario `tdm_256_word_copy`: 8 bursts and 8 row writes with the same addresses/order; the model reports the chunk count and the measured period. The structural counts (8 bursts, 8 rows) are exact and model-testable; the period is advisory.

---

## Interface Requirements

1. **ID**: IFACE-001
   - **Requirement**: `chip_top` exposes exactly one clock `clk` (100 MHz), one active-low synchronous reset `rst_n`, and one level interrupt `irq`; no second clock, no asynchronous reset, and no test/scan/debug pins are part of the functional interface. `irq` is asserted as a level when `STATUS.DONE = 1` and `IRQ_EN[0] = 1` and is held until the next `CONTROL.START`. [HARD, FR-CLK-1, FR-HOST-2, CON-2]
   - **Acceptance criteria**: Port list contains `clk` (input), `rst_n` (input), `irq` (output) and nothing else in this group; full-chip simulation with `IRQ_EN[0] = 0` holds `irq = 0` through completion, and with `IRQ_EN[0] = 1` asserts `irq = 1` at completion and holds it for at least 1024 cycles until the next `CONTROL.START` write.
   - **Priority**: must_have
   - **Model check**: SystemC LT `command_processor` model: the harness drives reset and launch, reads the `irq` output and the CSR state; `IRQ_EN = 0` scenario expects `irq` never high, `IRQ_EN = 1` expects a level held until START.

2. **ID**: IFACE-002
   - **Requirement**: The global-memory interface is an AXI4 master with 128-bit data, 32-bit address, INCR bursts of exactly 8 beats (128 bytes, `awlen/arlen = 7`, `awsize/arsize = 4`, `awburst/arburst = 01`), one outstanding transaction, `awid/arid` tied to 0, `awlock/arlock` tied 0, `awcache/arcache` tied 0, `awprot/arprot` tied 0, `awqos/arqos` tied 0, `awregion/arregion` tied 0, 4-bit `bid`/`rid`, and OKAY/EXOKAY responses treated as success. The full port set is the SAD pin table. [HARD, FR-MEM-4, AD-10, AD-19]
   - **Acceptance criteria**: `chip_top` exposes the following 426 signal bits: `m_axi_awid[3:0]`, `m_axi_awaddr[31:0]`, `m_axi_awlen[7:0]`, `m_axi_awsize[2:0]`, `m_axi_awburst[1:0]`, `m_axi_awlock`, `m_axi_awcache[3:0]`, `m_axi_awprot[2:0]`, `m_axi_awqos[3:0]`, `m_axi_awregion[3:0]`, `m_axi_awvalid`, `m_axi_awready`, `m_axi_wdata[127:0]`, `m_axi_wstrb[15:0]`, `m_axi_wlast`, `m_axi_wvalid`, `m_axi_wready`, `m_axi_bid[3:0]`, `m_axi_bresp[1:0]`, `m_axi_bvalid`, `m_axi_bready`, `m_axi_arid[3:0]`, `m_axi_araddr[31:0]`, `m_axi_arlen[7:0]`, `m_axi_arsize[2:0]`, `m_axi_arburst[1:0]`, `m_axi_arlock`, `m_axi_arcache[3:0]`, `m_axi_arprot[2:0]`, `m_axi_arqos[3:0]`, `m_axi_arregion[3:0]`, `m_axi_arvalid`, `m_axi_arready`, `m_axi_rid[3:0]`, `m_axi_rdata[127:0]`, `m_axi_rresp[1:0]`, `m_axi_rlast`, `m_axi_rvalid`, `m_axi_rready`. An AXI4 VIP/protocol checker passes every full-chip test: VALID held until READY, WLAST/RLAST exactly at beat 8, `awlen/arlen = 7`, `awsize/arsize = 4`, `awburst/arburst = 01`, `addr[6:0] = 0`, at most one outstanding AR and one outstanding AW, BID/RID = 0, and no response is required for correct data ordering. The recomputed group counts are AW = 67, W = 147, B = 8, AR = 67, R = 137, total 426 (inputs 146, outputs 280).
   - **Priority**: must_have
   - **Model check**: not model-testable for the exact port list -- elaboration/VIP checks the pin names and widths; the LT AXI BFM verifies the transaction behavior (burst length, one outstanding, address alignment, beat order) and the same counts.

3. **ID**: IFACE-003
   - **Requirement**: The host interface is an AXI4-Lite slave with 32-bit data and 32-bit address, a 4 KB CSR window decoded from address bits [11:0], OKAY responses, full-word writes (`WSTRB` ignored), unimplemented offsets reading 0, and the frozen 11-register CSR map: `CONTROL` 0x000 (bit0 START self-clearing, bit1 SOFT_RESET reserved), `STATUS` 0x004 (bit0 BUSY, bit1 DONE, bit2 ERROR, RO), `KERNEL_PC` 0x008, `ARG_PTR` 0x00C, `GRID_X` 0x010, `GRID_Y` 0x014 (must be 1), `GRID_Z` 0x018 (must be 1), `WG_SIZE` 0x01C, `IRQ_EN` 0x020 (bit0), `CYCLE_LO` 0x024, `CYCLE_HI` 0x028, `WAVE_DONE` 0x02C. Reset values are all zero except `GRID_X/GRID_Y/GRID_Z = 1` and `WG_SIZE = 32`. [HARD, FR-HOST-1, AD-11]
   - **Acceptance criteria**: `chip_top` exposes the following 152 signal bits: `s_axil_awaddr[31:0]`, `s_axil_awprot[2:0]`, `s_axil_awvalid`, `s_axil_awready`, `s_axil_wdata[31:0]`, `s_axil_wstrb[3:0]`, `s_axil_wvalid`, `s_axil_wready`, `s_axil_bresp[1:0]`, `s_axil_bvalid`, `s_axil_bready`, `s_axil_araddr[31:0]`, `s_axil_arprot[2:0]`, `s_axil_arvalid`, `s_axil_arready`, `s_axil_rdata[31:0]`, `s_axil_rresp[1:0]`, `s_axil_rvalid`, `s_axil_rready` (AW = 37, W = 38, B = 4, AR = 37, R = 36; inputs 111, outputs 41). After reset, readback of all offsets 0x000–0x02C matches the reset map; every RW register writes and reads back; writes to STATUS/CYCLE_LO/CYCLE_HI/WAVE_DONE are ignored; reads of 0x030 and above return 0; AWPROT/ARPROT are ignored; every response is OKAY.
   - **Priority**: must_have
   - **Model check**: SystemC LT `command_processor` model, scenario `csr_map`: reset readback, per-register write/readback, RO write-ignore, unimplemented offset read-0; the harness compares the full map to the table above.

4. **ID**: IFACE-004
   - **Requirement**: The LDS block interface is 4096 bytes organized as 32 banks x 32 rows x 32 bits, with two lane ports (one per SIMD32, each carrying 32 independent byte addresses and 32-bit write data per lane) and one linear port used by the WMMA and TDM (one 32-word row per access). The physical array serves one 32-word access per cycle. Address map: lane `bank = addr[6:2]`, lane `row = addr[11:7]`; linear `row = addr[9:5]`. A conflict-free lane access presents 32 distinct banks and returns data one cycle after the request (synchronous read registered at the port); a same-bank/different-row lane access asserts `conflict` and is not served. [HARD, FR-MEM-1, AD-5, AD-16]
   - **Acceptance criteria**: LDS capacity is exactly 4096 bytes and the bank/row mapping matches the equations above in a directed test; a conflict-free 32-lane access returns 32 correct words with one cycle of read latency; a conflicting access asserts `conflict` in the request cycle and the offending wave aborts with `STATUS.ERROR` (no silent corruption); the linear port transfers exactly 32 words per granted cycle; arbitration of lane port 0, lane port 1 and the linear port is deterministic and matches PERF-006.
   - **Priority**: must_have
   - **Model check**: SystemC LT `lds` model: the harness writes/reads the full 4 KB image through the three ports, checks the bank/row equations, injects a bank conflict and expects the conflict event; the model returns the same word image as the RTL reference.

5. **ID**: IFACE-005
   - **Requirement**: The instruction RAM is 1024 bytes = 256 x 32-bit words with one write port (the command processor preload) and two independent read ports (SIMD0 and SIMD1), synchronous reads. Word `i` of the kernel image at `KERNEL_PC` is instruction RAM word `i`; the SIMD PC is an 8-bit word index in 0..255 starting at 0; the RAM is a preloaded memory, not a cache (no misses, refills, or coherence). [HARD, FR-MEM-2, AD-12, SAD S2]
   - **Acceptance criteria**: Preload a full 1 KB image (256 words) and read it back word-exact through both read ports, including both ports reading different addresses in the same cycle; immediately after preload, both SIMDs fetch word 0 of the new image with no stale words; a branch-loop kernel produces the expected signed-11-bit PC sequence.
   - **Priority**: must_have
   - **Model check**: SystemC LT `instruction_ram` model: preload/readback through both ports, concurrent fetch, and the PC trace for a branch loop.

6. **ID**: IFACE-006
   - **Requirement**: The instruction interface is the frozen 32-bit ISA subset of `spec/ISA.md`: scalar opcodes 0x00–0x17 (0x11 `S_MOV_B64` reserved), vector opcodes 0x20–0x3A (`0x2F`, `0x34`–`0x37` reserved, F16/FP32 not implemented), with `S_WMMA` (0x15), `S_TDM_COPY` (0x14) and `S_ENDPGM` (0x0C) required. Reserved opcodes decode as NOP with no architectural side effects. Branch offsets are signed 11-bit word offsets relative to the next PC. Binary compatibility with gfx-class CDNA5 encodings is not required. [HARD, FR-EXEC-2, CON-7, CON-8]
   - **Acceptance criteria**: A directed per-opcode test executes every implemented opcode and compares the architectural state (SGPR/VGPR/VCC/SCC/EXEC/PC/LDS) to the reference; every reserved opcode leaves all architectural state unchanged (no register, LDS, global, STATUS or PC side effect); the branch-offset test retires the expected PC sequence; no F16/FP32 vector arithmetic is required or credited.
   - **Priority**: must_have
   - **Model check**: SystemC LT `simd32` model: the decoded opcode stream and architectural state for the directed test; reserved opcodes must be no-ops in the model as well.

---

## Semantic Invariants

1. **ID**: INV-001
   - **Requirement**: MXFP4 numeric exactness across the matrix datapath. For every MFMA, `C[i][j] = sum(k=0..31) D(A[i][k]) * D(B[k][j])`, where `D` decodes a signed E2M1 nibble to the x2 integer sequence `{0,+/-1,+/-2,+/-3,+/-4,+/-6,+/-8,+/-12}`; the accumulation is exact int32 with no rounding, saturation or scale inside the MAC tree; the 256 int32 C words are written to LDS at the descriptor base. [HARD, FR-CORE-3, FR-CORE-4, KPI-CORR-001, AD-7]
   - Affected blocks/interfaces: `wmma`, `lds` linear port, `axi_master` C writeback, the validation reference.
   - **Acceptance criteria**: All 256 C words equal the reference byte-exactly for the full 16x16x32 stimulus (KPI-CORR-001); the directed sanity vector A = code 2 (1.0), B = code 4 (2.0), K = 32 gives C = 256 in the x4 integer pipeline; the LDS snapshot after the C store matches the reference word-for-word.
   - Validation method: full-chip TDM->LDS->WMMA->AXI4 matmul; word-exact LDS snapshots at (a) after TDM staging, (b) after the WMMA C store; VCD-visible `wmma_a`, `wmma_b`, `wmma_c`, `lds_*` buses and the `wmma_done` pulse.
   - **Priority**: must_have
   - **Model check**: SystemC LT `wmma` model versus `reference()` from `inputs/acceptance_stimulus.py`; the harness prints the first divergence as (case, tile, k-block, row, col, expected, actual).

2. **ID**: INV-002
   - **Requirement**: The LDS word image, address map and packed operand layout are preserved across writers and readers. The map is `bank = addr[6:2]`, `row = addr[11:7]` for lane ports and `row = addr[9:5]` for the linear port; A is 64 packed words at a 32-word-aligned base (row-major 16x32), B is 64 packed words (32x16), C is 256 int32 words; two E2M1 nibbles per byte, low nibble first. The AD-6 map is `A0/A1 = 0x000/0x100`, `B0/B1 = 0x200/0x300`, `C = 0x400–0x7FF`, scratch = `0x800–0xFFF`. [HARD, FR-MEM-1, AD-4, AD-6, SAD S1]
   - Affected blocks/interfaces: `tdm`, `wmma`, `simd32` x2, `lds`.
   - **Acceptance criteria**: After a TDM copy, the LDS word image equals the packed source image; the WMMA reads exactly the intended 64 A + 64 B words for a descriptor; an alias test writes and reads every bank/row and detects no overlap between the A0/A1/B0/B1/C/scratch regions; the packed nibble order is confirmed by a directed pattern whose two nibbles differ.
   - Validation method: LDS image dumps at the INV-001 trace points; the TDM chunk trace; VCD `lds_addr`, `lds_wdata`, `lds_rdata`.
   - **Priority**: must_have
   - **Model check**: SystemC LT `lds` model seeded with the same packed image; the harness compares the full 4 KB image after each stage.

3. **ID**: INV-003
   - **Requirement**: WMMA accumulator-bank ownership. With two 256 x int32 accumulator banks and a one-deep descriptor queue, the core never reads a bank out to LDS while writing the same bank, and never overwrites the bank of an operation whose C-store has not completed; `C = A*B` is computed into the bank for that operation and the completed bank is drained in 8 grants. The bank selector toggles once per accepted operation. [HARD, FR-CORE-3, AD-3, SAD S5]
   - Affected blocks/interfaces: `wmma`, `lds` linear port, `wgp_ctrl`.
   - **Acceptance criteria**: For 64 back-to-back operations, each operation's 256 C words match the per-operation reference and no cross-operation contamination appears; a forced bank-switch test (shorter and longer C-store stalls) shows no corruption; the bank selector toggles exactly once per operation; the final drain completes with the last operation's data intact.
   - Validation method: per-operation C trace to LDS versus the reference model; VCD `wmma_bank`, `wmma_c_we`, `wmma_done`.
   - **Priority**: must_have
   - **Model check**: SystemC LT `wmma` model exposes the bank index and per-operation C; the harness compares each operation independently.

4. **ID**: INV-004
   - **Requirement**: Launch, completion, WAVE_DONE and IRQ are a single coherent handshake. All launch parameters (`KERNEL_PC`, `ARG_PTR`, `GRID_X/Y/Z`, `WG_SIZE`, `IRQ_EN`) are latched at `CONTROL.START` and define the launched grid; each `S_ENDPGM` retires exactly one workgroup and increments `WAVE_DONE`; `STATUS.DONE` is set only when `pending == 0` and both SIMDs are idle; `STATUS.BUSY` is cleared at completion; `WAVE_DONE = GRID_X * GRID_Y * GRID_Z` for a successful run; `IRQ` is a level held until the next START and asserted only when `IRQ_EN[0] = 1`; a new START while busy is ignored; an LDS conflict sets sticky `STATUS.ERROR`, aborts the wave, clears BUSY and does not assert IRQ. [HARD, FR-HOST-2, FR-HOST-3, FR-EXEC-3, AD-13, SAD S9/S10]
   - Affected blocks/interfaces: `command_processor`, `wgp_ctrl`, `simd32` x2, `axi_lite_slave`.
   - **Acceptance criteria**: For `GRID_X` = 1, 2 and 8, `WAVE_DONE` = 1, 2 and 8 exactly, `DONE = 1`, `BUSY = 0`, `ERROR = 0`; for `WG_SIZE` = 1, 31 and 32 the EXEC seeds are `(1<<WG_SIZE)-1`; a mid-run CSR write to a latched parameter has no effect; START while busy is ignored; `IRQ_EN` 0/1 behaves as above; an injected LDS conflict produces ERROR = 1, BUSY = 0, IRQ = 0.
   - Validation method: CSR timeline and dispatch/retirement trace; VCD `wave_done`, `status_busy`, `status_done`, `status_error`, `irq`, `wgp_done`.
   - **Priority**: must_have
   - **Model check**: SystemC LT `command_processor` + `wgp_ctrl` models, scenario `completion_handshake`: the same grid/WG_SIZE matrix, reading WAVE_DONE/STATUS/IRQ after each run.

5. **ID**: INV-005
   - **Requirement**: Instruction image fidelity. Instruction RAM word `i` equals kernel image word `i` for all 256 words after preload; both SIMD32 units fetch the same image through independent ports; the wave PC starts at word 0 after preload; branch targets are signed 11-bit word offsets relative to the next PC; a preload followed immediately by START produces no stale words. [HARD, FR-MEM-2, FR-HOST-2, AD-12, SAD S2]
   - Affected blocks/interfaces: `command_processor`, `axi_master`, `instruction_ram`, `simd32` x2.
   - **Acceptance criteria**: 256-word preload/readback is word-exact; concurrent fetch by both SIMDs at different addresses in one cycle returns the right words; a branch-loop kernel retires the expected PC stream; a second launch with a different image replaces all 256 words (no residue).
   - Validation method: I$ image dump after preload; PC stream trace; VCD `imem_addr`, `imem_data` for both SIMDs.
   - **Priority**: must_have
   - **Model check**: SystemC LT `instruction_ram` + `command_processor` models: image readback and PC trace.

6. **ID**: INV-006
   - **Requirement**: AXI4 ordering and block assembly. At most one read and one write transaction are outstanding; every transaction is an aligned 128-byte INCR8 block; the assembled 128-byte block equals the 8 R beats in order and the 8 W beats carry the block in order; `RLAST`/`WLAST` are asserted exactly at beat 8; no reordering across TDM chunks. [HARD, FR-MEM-4, AD-10, SAD S7]
   - Affected blocks/interfaces: `axi_master`, `tdm`, `simd32` (`V_MEM_*`), `command_processor` (preload).
   - **Acceptance criteria**: AXI VIP trace shows no second AR before RLAST and no second AW before B; `RLAST`/`WLAST` position is beat 8 on every burst; every address is 128-byte aligned; the block read by the TDM equals the block written by the source; chunk n lands before chunk n+1; `BID`/`RID` = 0 and responses are handled as success.
   - Validation method: AXI protocol checker trace; assembled-block comparison; VCD `m_axi_ar*`, `m_axi_r*`, `m_axi_aw*`, `m_axi_w*`, `m_axi_b*`.
   - **Priority**: must_have
   - **Model check**: SystemC LT AXI BFM: the harness checks the same ordering rules and reassembles blocks from the model's beat records.

7. **ID**: INV-007
   - **Requirement**: LDS linear-port arbitration is deterministic, credit-based and starvation-free. While back-to-back MFMA is active the WMMA receives 12 grants of every 16-cycle slot (4 operand grants + 8 C-store grants); the TDM receives at least 2 grants per 16 cycles when pending; the two lane ports consume the remainder; a master that is requesting is never starved beyond 64 consecutive cycles. The grant sequence is a deterministic function of the request history. [HARD, FR-PERF-2, FR-MEM-1, AD-5, SAD S8]
   - Affected blocks/interfaces: `wgp_ctrl` (arbiter), `lds`, `wmma`, `tdm`, `simd32` x2.
   - **Acceptance criteria**: Over a 1024-cycle mixed run every 16-cycle window with back-to-back MFMA meets the 12/2 split; the per-master grant counts are reproducible run-to-run for the same request sequence; no master exceeds the 64-cycle starvation bound; the run still meets PERF-002.
   - Validation method: per-cycle grant trace (master ID, address, read/write) captured to VCD; the harness recomputes the quotas; a starvation stress test holds one port busy.
   - **Priority**: must_have
   - **Model check**: SystemC LT arbiter model emits the grant trace; the harness applies the same quota/ starvation checks and requires the deterministic sequence.

8. **ID**: INV-008
   - **Requirement**: EXEC-mask semantics. Vector writes affect only lanes where `EXEC[i] = 1`; inactive lanes retain their VGPR value; `EXEC` is seeded to `(1 << WG_SIZE) - 1` at launch; VCC is per-lane (32 bits), SCC is per-wave; 16 VGPRs per lane and 32 SGPRs per wave are the architectural state. [HARD, FR-CORE-1, FR-CORE-2, SAD S3/S4]
   - Affected blocks/interfaces: `simd32` x2, `wgp_ctrl` (launch seeds).
   - **Acceptance criteria**: For `EXEC` = 0x00000000, 0x00000001, 0xAAAAAAAA, 0xFFFFFFFF and `WG_SIZE` = 1, 31, 32, the per-lane VGPR image equals the reference; `EXEC = 0` writes nothing; inactive lanes are bit-identical before and after; VCC/SCC/PC match the reference after each scalar/vector op.
   - Validation method: directed per-lane VGPR dumps; VCD `exec`, `vcc`, `scc`, `v_wdata`.
   - **Priority**: must_have
   - **Model check**: SystemC LT `simd32` model: per-lane register image for each EXEC mask.

9. **ID**: INV-009
   - **Requirement**: The numeric scale/rescale contract between hardware and software is fixed. The hardware C word is x4 the nominal FP4 product; the consumer computes `C_sw = C_hw * 2^(e_a + e_b - 256)` for each 32-element K block, applying the E8M0 scale `2^(e-127)` once per block; no scale is applied inside the MAC tree; cross-K accumulation is exact int32 addition before the final scale. [HARD, FR-CORE-4, AD-7, AD-8, SAD S11]
   - Affected blocks/interfaces: `wmma` (hardware side), host software (S11), validation reference.
   - **Acceptance criteria**: A directed block with known codes and exponents reproduces the reference mantissa/exponent exactly; the software reference applies the same order; the byte-exact int32 C comparison (INV-001) is independent of the scale; a scale test with `e_a + e_b - 256` negative (e.g. 120 + 120 - 256 = -16) and positive (134 + 134 - 256 = 12) matches the exact rational value.
   - Validation method: compare the scaled reference and the hardware C for the acceptance stimulus; VCD of the C words; the reference's scale order is part of the artifact.
   - **Priority**: must_have
   - **Model check**: SystemC LT harness runs the reference epilogue on the model's C and compares exact integer mantissa/exponent pairs.

10. **ID**: INV-010
   - **Requirement**: TDM descriptor and alignment contract. The copy is 1-D contiguous; the source is 128-byte aligned; the destination is 32-word aligned; `len` is a multiple of 32 and at most 256 words; each 128-byte burst writes exactly one 32-word LDS row; chunk n lands before chunk n+1; no write occurs outside `[dst, dst + len)`. No bounds checks, multicast or LDS-to-global direction are implemented. [HARD, FR-MEM-3, CON-6, AD-9, SAD S6]
   - Affected blocks/interfaces: `tdm`, `axi_master`, `lds`, `simd32`.
   - **Acceptance criteria**: A 64-word A copy and a 64-word B copy followed by WMMA are correct; a 256-word maximum copy is correct; a misaligned or invalid descriptor never writes outside the destination range in the bring-up (undefined behavior is allowed to fail, silent corruption of other rows is not); the chunk ordering trace is monotonic.
   - Validation method: TDM AR/R trace and the LDS image; VCD `tdm_src`, `tdm_dst`, `tdm_len`, `tdm_done`.
   - **Priority**: must_have
   - **Model check**: SystemC LT `tdm` model: chunk addresses and LDS image for the valid and maximum-length copies.

11. **ID**: INV-011
   - **Requirement**: Workgroup dispatch determinism. `GRID_X` workgroups are launched exactly once each; SIMD0 receives the first free workgroup and SIMD1 the next; each SIMD executes one wave at a time; `wg_id` seeds `s0` and the launch seeds are `s0 = wg_id`, `s1 = arg_ptr`, `s2 = lds_base`, `s3 = wg_size`, `s4 = lane_base`, `PC = 0`, `EXEC = (1 << WG_SIZE) - 1`; `wgp_done` asserts only when `pending == 0` and both SIMDs are idle. [HARD, FR-EXEC-1, FR-CORE-1, AD-14, SAD S10]
   - Affected blocks/interfaces: `wgp_ctrl`, `simd32` x2, `command_processor`.
   - **Acceptance criteria**: Dispatch/retirement traces for `GRID_X` = 1, 2 and 8 show each `wg_id` exactly once and SIMD0-first order; the seeded SGPR/PC/EXEC values match the launch table for `WG_SIZE` = 1, 31 and 32; `wgp_done` asserts only after all retirements.
   - Validation method: dispatch trace (cycle, wg_id, SIMD) and the seeded state dump; VCD `wg_id`, `simd_busy`, `wgp_done`.
   - **Priority**: must_have
   - **Model check**: SystemC LT `wgp_ctrl` + `simd32` models: deterministic dispatch trace for the three grid sizes.

12. **ID**: INV-012
   - **Requirement**: Full-chip 32-lane vector-add path exactness. The sequence `V_MEM_LD` (128-byte aligned 32-word block) -> `V_ADD_I32` (EXEC-masked, int32 wrap) -> `V_MEM_ST` (128-byte block) -> `S_ENDPGM` produces `C[i] = (A[i] + B[i]) mod 2^32` for all 32 lanes and the completion handshake. [HARD, KPI-FUNC-001, FR-CORE-5, FR-EXEC-3]
   - Affected blocks/interfaces: `simd32` x2, `lds`, `axi_master`, `command_processor`.
   - **Acceptance criteria**: All 32 lane results of the KPI-FUNC-001 test are exact, including values that wrap (0x7FFFFFFF + 1, 0xFFFFFFFF + 1); `STATUS.DONE = 1`; the level IRQ asserts when `IRQ_EN[0] = 1`; the AXI loads/stores are 128-byte aligned blocks with 8 beats each.
   - Validation method: full-chip simulation with two 128-byte AXI reads, one add, one 128-byte store; compare all 32 words and the CSR/IRQ state; VCD `gmem_addr`, `gmem_wdata`, `gmem_rdata`.
   - **Priority**: must_have
   - **Model check**: SystemC LT full-SoC path: the harness runs the same host flow on the model and compares the 32 output words and the completion state.

---

## Timing Requirements

1. **ID**: TIME-001
   - **Requirement**: The chip is a single 100 MHz clock domain: one clock `clk` with a 10.0 ns period, no second domain, no generated clock, and no clock crossing. [HARD, FR-CLK-1, CON-2]
   - **Acceptance criteria**: The SDC constrains exactly one clock at 10.0 ns; post-synthesis OpenSTA at `tt_025C_1v80` reports WNS >= 0 and one clock domain; the CDC report is empty; the netlist contains no generated-clock logic.
   - **Priority**: must_have
   - **Metric**: ns; min -; max 10; unit ns
   - **Model check**: SystemC LT model declares `clock_mhz = 100`; all model cycle accounting uses 10 ns/cycle. The model check is the cycle base, not a timing signoff; STA is not model-testable.

2. **ID**: TIME-002
   - **Requirement**: Reset is active-low and synchronous: `rst_n` is sampled on every `posedge clk`, held for at least two clocks, and released synchronously; every register is `always @(posedge clk)`; no asynchronous reset, no latches, no tri-states. All state is defined at reset except LDS, instruction RAM and VGPR contents, which are software-initialized or preloaded. [HARD, FR-CLK-1, CON-2, FR-RTL-1, AD-15]
   - **Acceptance criteria**: A 2-cycle reset pulse returns every defined register to its reset value; the first instruction fetch occurs only after reset release; lint reports zero latches, zero tri-states and no `negedge rst_n`; the synthesized netlist uses only flops with synchronous reset (no async-reset cells in the reset path).
   - **Priority**: must_have
   - **Metric**: cycles; min 2; max -; unit cycles
   - **Model check**: SystemC LT harness drives `rst` low for 2 cycles and releases it; the model reaches the reset state in <= 2 cycles and the first transaction occurs only after release.

3. **ID**: TIME-003
   - **Requirement**: The command-processor preload fetches the complete 1 KB instruction image as eight INCR8 reads (64 beats, 256 I$ words) from `KERNEL_PC` before `wgp_start`. There is no hard host-visible latency budget (PRD `latency_budget_us = null`, Q-2); the requirement is structural completeness and the absence of deadlock. [HARD, FR-HOST-2, AD-12]
   - **Acceptance criteria**: On START, exactly 8 AR bursts of 8 beats are issued and 256 words are written; `wgp_start` follows the last I$ write and not before; with an always-ready target the preload completes and the measured cycle count is reported; no deadlock under a 10,000-cycle watchdog (test limit, not a requirement).
   - **Priority**: must_have
   - **Model check**: SystemC LT `command_processor` + AXI BFM: 8 bursts, 64 beats, 256 words, `wgp_start` ordered after the last write; the model reports its cycle count, which is advisory (LT is not cycle-exact).

4. **ID**: TIME-004
   - **Requirement**: The full-chip TDM->LDS->WMMA->AXI4 acceptance run completes and its duration is measured and reported. The PRD's 1,035 cycles (~10.35 µs) from reset is an informational reference, not a pass/fail bound (Q-2). [INFORMATIONAL, PRD `speed_and_feeds`, SAD interpretation 5]
   - **Acceptance criteria**: The single-tile acceptance run completes from reset with correct data; the measured cycles and the implied time at 100 MHz are recorded with `measure.record("TIME-004", cycles, unit="cycles", test="full_chip_matmul")`; no threshold is applied and no latency failure is raised. Any future latency bound requires a new PRD requirement.
   - **Priority**: should_have
   - **Model check**: SystemC LT model reports its own cycle count for the same flow; the value is advisory and is not compared to 1,035 for pass/fail.

5. **ID**: TIME-005
   - **Requirement**: After the 16th compute cycle of an MFMA, the C store drains in 8 cycles (8 grants of 32 words); in steady state this store overlaps the next operation's operand read and compute. For N >= 2 back-to-back operations the amortized cadence is `16 + 8/N` cycles/op, which must stay at or below 17.78 cycles/op. [HARD, AD-3, PERF-002]
   - **Acceptance criteria**: Measure the last operation's drain from the end of compute to C-store completion: exactly 8 cycles (plus at most one arbitration stall per the 12/16 reservation). Measure the amortized cadence over N = 2, 4, 8, 64 operations and require <= 17.78 cycles/op for every N >= 2.
   - **Priority**: must_have
   - **Metric**: cycles; min -; max 8; unit cycles
   - **Model check**: SystemC LT `wmma` model timestamps the compute end and the C-store end; the model must report an 8-cycle drain and the same amortized cadence values.

6. **ID**: TIME-006
   - **Requirement**: The completion IRQ is a level: it is asserted no earlier than the last workgroup retires and no later than one cycle after `STATUS.DONE` is set, and it remains asserted until the next `CONTROL.START`; with `IRQ_EN[0] = 0` it is never asserted. [HARD, FR-HOST-2, AD-13]
   - **Acceptance criteria**: Waveform check: `irq` rises in the same cycle as or the cycle after `STATUS.DONE`; it stays high for at least 1024 cycles; the next START deasserts it; the `IRQ_EN = 0` run never asserts it; an ERROR completion does not assert it.
   - **Priority**: must_have
   - **Metric**: cycles; min -; max 1; unit cycles
   - **Model check**: SystemC LT `command_processor` model: the harness records the DONE and IRQ timestamps; the delta must be <= 1 cycle in the model's cycle accounting.

7. **ID**: TIME-007
   - **Requirement**: LDS port latency and conflict timing. A conflict-free lane access is requested in cycle n and returns 32 words in cycle n+1 (synchronous read registered at the port); the linear port transfers one 32-word row in the granted cycle; a same-bank/different-row lane access asserts `conflict` in the request cycle and is not served. [HARD, FR-MEM-1, AD-17, SAD S1]
   - **Acceptance criteria**: Measured request-to-`lds_rdata` latency is 1 cycle on both lane ports for conflict-free patterns; a conflicting pattern asserts `conflict` in the same cycle as `lds_req`; the linear port completes one 32-word transfer per granted cycle; no conflict is ever silently served with wrong data.
   - **Priority**: must_have
   - **Metric**: cycles; min 1; max 1; unit cycles
   - **Model check**: SystemC LT `lds` model reports the request-to-data latency and the conflict event timing; both must match the RTL contract.

8. **ID**: TIME-008
   - **Requirement**: AXI4 handshake timing. `ARVALID`/`AWVALID`/`WVALID` are held until the corresponding `READY`; VALID does not depend combinationally on READY; W beats of a burst are presented in order with `WLAST` at beat 8; R beats are accepted in order with `RLAST` at beat 8; at most one read and one write transaction are outstanding. [HARD, FR-MEM-4, AD-10]
   - **Acceptance criteria**: AXI VIP with randomized `RREADY`/`WREADY` back-pressure passes with zero protocol violations; the measured AR-to-first-R and AW-to-first-W turnaround is reported (advisory, no bound); no beat is dropped or duplicated under back-pressure.
   - **Priority**: must_have
   - **Model check**: SystemC LT AXI BFM applies the same back-pressure rules; the model's transaction log is checked for VALID stability and beat order.

---

## Physical Design Requirements

1. **ID**: PHYS-001
   - **Requirement**: Total mapped GPIO pads must not exceed the OPENFRAME budget: 44 pads total, GPIO[0] = `clk` and GPIO[1] = `rst_n` reserved, leaving 42 usable. The soft-IP deliverable keeps the 581-bit functional interface (AD-19) and maps 0 functional pads (no wrapper); any hardened wrapper requires explicit approval and must map at most 42 pads (the illustrative serialized bridge uses 31, leaving 11 spare). [HARD, OPENFRAME constraints, AD-19, R8]
   - **Acceptance criteria**: For the soft-IP deliverable: no `io_in/io_out/io_oeb` wrapper is produced and the `chip_top` port list is unchanged; pad-mapping count = 0 <= 42. For a future wrapper: a pad table with total mapped pads <= 42, no signal double-mapped, `io_oeb[43:0]` fully assigned (0 = output, 1 = input), and every unused `io_out` bit driven to 0.
   - **Priority**: must_have
   - **Model check**: not model-testable -- pad/package integration is a physical deliverable; the LT model has no package interface.

2. **ID**: PHYS-002
   - **Requirement**: The core footprint (standard cells plus banked LDS/I$ memories, excluding the pad ring) must not exceed 8.0 mm² (CON-4 ceiling); the PRD range is 4.0–8.0 mm². The OPENFRAME carrier die is fixed at 3520 x 5188 µm = 18.262 mm² and the user area is 3320 x 4988 µm = 16.560 mm² (100 µm core margin). The planned core is 4.5–6.5 mm² (advisory). [HARD, CON-4, SAD "Die area budget"]
   - **Acceptance criteria**: OpenROAD final floorplan/DB reports core footprint <= 8.0 mm² and <= 0.60 x 16.560 = 9.936 mm² (60% target utilization), with the die frame at 3520 x 5188 µm and the core margin >= 100 µm. Report the measured core area and utilization. The 4.0 mm² lower bound is reported; the shuttle carrier is larger by construction. If the human intended the whole carrier to be 4.0–8.0 mm², the requirement is unsatisfiable and must be escalated (see correction 6).
   - **Priority**: must_have
   - **Model check**: not model-testable -- physical design/floorplan.

3. **ID**: PHYS-003
   - **Requirement**: Zero DRC violations on every implemented layer: li1 and met1 through met4 (met4 is the maximum routing layer; met5 is harness/pad-layer metal and not a routing resource). Both Magic DRC and KLayout FEOL/BEOL checks must be clean. [HARD, CON-3, OPENFRAME metal stack]
   - **Acceptance criteria**: Magic DRC violation count = 0 and KLayout DRC violation count = 0 on the final GDS, reported per layer; no waived violations without a recorded human ruling.
   - **Priority**: must_have
   - **Model check**: not model-testable -- DRC is a layout check.

4. **ID**: PHYS-004
   - **Requirement**: Layout versus schematic must match with zero device and net deltas; tap-cell-only deltas are acceptable. [HARD, CON-3]
   - **Acceptance criteria**: LVS report shows `device_delta == 0` and `net_delta == 0` (tap cell deltas excluded and documented); the compared netlist is the synthesized `sky130_fd_sc_hd` netlist in the final GDS.
   - **Priority**: must_have
   - **Model check**: not model-testable -- LVS is a layout check.

5. **ID**: PHYS-005
   - **Requirement**: After metal fill insertion, li1 and met1–met4 meet the PDK minimum and maximum density targets on every layer. [HARD, CON-3, OPENFRAME metal stack]
   - **Acceptance criteria**: KLayout density report shows every implemented layer within the PDK density limits; the density violation count is 0; fill is inserted per layer on the final GDS.
   - **Priority**: must_have
   - **Model check**: not model-testable -- metal density is a layout check.

6. **ID**: PHYS-006
   - **Requirement**: Standard-cell usage must not exceed 500,000 cells, excluding the LDS and instruction RAM bulk arrays (CON-4); the planning range is 300,000–500,000 and the measured matrix core is 126,245 cells / 1.218 mm². The LDS and I$ banked arrays are tracked separately (PHYS-007/008). [HARD, CON-4]
   - **Acceptance criteria**: Post-synthesis cell count of the logic (excluding LDS/I$ arrays) <= 500,000; per-block counts reported; the WMMA receipt shows the measured 126,245 cells for the reference core; no unexplained growth from the planning estimate.
   - **Priority**: must_have
   - **Model check**: not model-testable -- synthesis receipts.

7. **ID**: PHYS-007
   - **Requirement**: The 4 KB LDS is implemented as 32 physical banks of 32 rows x 32 bits with per-bank 32:1 read muxes; a flat 1024-word x 32-bit multi-port flop array is rejected (it elaborates to roughly 3.3M cells, about an order of magnitude over budget). [HARD, CON-5, AD-16, SAD S1]
   - **Acceptance criteria**: The synthesized LDS structure is 32 banks; the LDS cell-equivalent count is within the 130,000–200,000 advisory envelope and is excluded from the 500,000 logic cap; the post-synthesis report proves no flat array and no per-bit multi-port mux expansion.
   - **Priority**: must_have
   - **Model check**: not model-testable -- synthesis structure.

8. **ID**: PHYS-008
   - **Requirement**: The 1 KB instruction RAM is implemented as a banked 256 x 32-bit memory with one write port and two read ports, separate from the command processor and the SIMD32 blocks; its cell-equivalent count is excluded from the 500,000 logic cap. [HARD, CON-5, FR-MEM-2, SAD S2]
   - **Acceptance criteria**: Post-synthesis report shows a 256x32 memory with 1W/2R ports, cell-equivalents within the 30,000–50,000 advisory envelope, and no I$ storage instantiated inside the CP or the SIMD32s.
   - **Priority**: must_have
   - **Model check**: not model-testable -- synthesis structure.

9. **ID**: PHYS-009
   - **Requirement**: Total power must not exceed 2,000 mW at 1.8 V, 100 MHz, corner `tt_025C_1v80`, in the single core domain; leakage is not separately budgeted. The 2 W bound implies approximately 1.11 A of core current. [HARD, CON-4]
   - **Acceptance criteria**: OpenROAD/OpenSTA power analysis with VCD activity reports total power <= 2,000 mW; dynamic and leakage are reported separately; the measured TDM reference (10.1 mW after P&R) is recorded; no per-block clock gating is required in RTL, but backend ICG cells are expected.
   - **Priority**: must_have
   - **Model check**: not model-testable -- power estimation is a backend activity; the LT model carries no power.

10. **ID**: PHYS-010
    - **Requirement**: The design uses the OPENFRAME metal stack li1 + met1–met5 with met4 as the maximum routing layer; no thick or triple-width metal beyond the standard stack; met5 is reserved for the harness/pad layer. The clock is routed on met3/met4 and the power grid on met4. [HARD, OPENFRAME constraints]
    - **Acceptance criteria**: OpenROAD DB reports max routing layer met4 and zero routes on met5; the clock and power layers match the plan; no custom layer map is used.
    - **Priority**: must_have
    - **Model check**: not model-testable -- physical routing.

11. **ID**: PHYS-011
    - **Requirement**: A single clock tree at 100 MHz with skew <= 0.5 ns; ICG cells at the block roots for `simd32` x2, `wmma`, `tdm`, `axi_master`, and the CP/AXI-Lite group, enabled by the block idle/busy signal; no RTL clock gating. [SHOULD, SAD "Clock tree physical planning", FR-RTL-1]
    - **Acceptance criteria**: CTS/OpenSTA report one clock domain and skew <= 0.5 ns; the netlist contains ICG cells on the named block roots and no clock-gating logic written in RTL.
    - **Priority**: should_have
    - **Model check**: not model-testable -- CTS/STA; the LT model has no clock tree.

12. **ID**: PHYS-012
    - **Requirement**: Power-domain assignment: all core logic on `vccd1`/`vssd1` (1.8 V); `vdda1`/`vssa1` (3.3 V analog) unused and tied off; a wrapper, if any, drives pads from `vddio`/`vssio` (3.3 V) with level shifters. The core supply grid must be planned for the ~1.11 A peak at 2 W and checked for IR drop and electromigration. [HARD, OPENFRAME power domains, CON-4]
    - **Acceptance criteria**: Power-domain report assigns every core instance to `vccd1`/`vssd1`; `vdda1`/`vssa1` have no loads; IR-drop and electromigration reports pass the PDK/flow limits on the final power grid.
    - **Priority**: must_have
    - **Model check**: not model-testable -- power-grid analysis.

13. **ID**: PHYS-013
    - **Requirement**: All RTL is Verilog-2005 and synthesizes through Yosys/OpenROAD Sky130 HD with no latches, no tri-states, no SystemVerilog constructs, one `always @(posedge clk)` clocking style, and an active-low synchronous reset. [HARD, FR-RTL-1, CON-2, CON-3, AD-15]
    - **Acceptance criteria**: Yosys `check` reports no problems; lint reports zero latches, zero tri-states, zero combinational loops and zero multi-driven nets; the synthesized hierarchy contains only `sky130_fd_sc_hd` cells and the banked memories; no `initial` block or SystemVerilog construct survives synthesis.
    - **Priority**: must_have
    - **Model check**: not model-testable -- lint/synthesis.

14. **ID**: PHYS-014
    - **Requirement**: The floorplan places the LDS at the core center, the WMMA adjacent to the LDS linear port, the two SIMD32 units flanking the LDS (short symmetric lane-port routes), the CP/AXI-Lite/AXI master on the host edge, and the TDM between the AXI master and the LDS. No hard macros exist in this run (flop-array memories), so no macro halos are required; reserve 5–10 µm channels between major blocks. [SHOULD, SAD "Floorplan strategy"]
    - **Acceptance criteria**: The placed block bounding boxes satisfy the adjacency plan; the LDS-to-WMMA and LDS-to-SIMD routes are within the planned channels; no block overlaps or halo violation; the floorplan is recorded with the P&R run.
    - **Priority**: should_have
    - **Model check**: not model-testable -- floorplan.

---

## MPW Submission Acceptance Criteria

**Submission status.** This run delivers soft IP (`chip_top`) and does not produce a
wrapper or a GDS submission; AD-19 preserves the 581-bit functional interface
rather than narrowing it to the 42 usable OPENFRAME pads. The criteria below are
the hard gates that apply **if** a tapeout is requested; they are not waived, and
MPW-006 currently blocks submission until a wrapper is explicitly approved.

1. **ID**: MPW-001
   - **Requirement**: A submission directory contains `gds/`, `def/`, `verilog/rtl/` and `verilog/gl/`, each populated with the final artifacts for the submitted top. [OPENFRAME submission structure]
   - **Acceptance criteria**: All four directories exist and are non-empty; `gds/` contains the top GDS, `def/` the final DEF, `verilog/rtl/` the RTL, and `verilog/gl/` the gate-level netlist; the precheck structure check passes.
   - **Priority**: must_have
   - **Model check**: not model-testable -- submission packaging.

2. **ID**: MPW-002
   - **Requirement**: The submitted GDS is valid: it exists, is larger than 1 KB, and contains valid geometry on the implemented layers. [OPENFRAME GDS validity]
   - **Acceptance criteria**: `gds/` file size > 1 KB; KLayout/Magic reads the file without errors; the layer map matches the Sky130 stack (li1, met1–met4, and the pad layers); the top cell name matches the wrapper.
   - **Priority**: must_have
   - **Model check**: not model-testable -- GDS packaging.

3. **ID**: MPW-003
   - **Requirement**: The wrapper port names match the shuttle's locked pad ports: `io_in[43:0]`, `io_out[43:0]`, `io_oeb[43:0]` (the `openframe_project_wrapper` interface), with every output driven and every OEB assigned (0 = output, 1 = input). [OPENFRAME wrapper contract]
   - **Acceptance criteria**: The wrapper module exposes exactly `io_in[43:0]`, `io_out[43:0]`, `io_oeb[43:0]` plus the shuttle's power/ground ports; all 44 `io_out` bits are driven (unused tied 0); all 44 `io_oeb` bits are assigned; the precheck port match passes.
   - **Priority**: must_have
   - **Model check**: not model-testable -- wrapper integration.

4. **ID**: MPW-004
   - **Requirement**: `vccd1`/`vssd1` are connected through the shuttle's power-connection macros in the wrapper and the core; the analog domain `vdda1`/`vssa1` is tied off (no analog content). [OPENFRAME power connection]
   - **Acceptance criteria**: The precheck power-connection check passes; `vccd1`/`vssd1` reach every core instance; `vdda1`/`vssa1` have no loads; the pad-ring `vddio`/`vssio` supply is connected per the harness rules.
   - **Priority**: must_have
   - **Model check**: not model-testable -- power connection.

5. **ID**: MPW-005
   - **Requirement**: The full MPW precheck suite passes: structure, GDS, KLayout DRC and Magic DRC. [OPENFRAME precheck]
   - **Acceptance criteria**: The precheck suite reports zero failures and zero unwaived warnings on the final submission directory; the DRC counts are 0 (PHYS-003) and the LVS counts are 0 (PHYS-004).
   - **Priority**: must_have
   - **Model check**: not model-testable -- precheck.

6. **ID**: MPW-006
   - **Requirement**: The functional interface must fit the shuttle pad budget (42 usable GPIO) or be carried by an explicitly approved wrapper. The 581-bit `chip_top` interface does not fit; a hardened submission therefore requires an approved wrapper (AD-19 Option B) with a mapped-pad count <= 42 and an on-die AXI4 target memory for the accelerator master. [HARD, OPENFRAME pads, AD-19, R8]
   - **Acceptance criteria**: Submission is accepted only when (a) a wrapper with <= 42 mapped pads exists and passes MPW-003/MPW-005, (b) the wrapper provides a target for the AXI4 master (the single-die shuttle has no external memory), and (c) the human has explicitly approved the interface change. Until then the submission gate is **FAIL/BLOCKED** and must be escalated, not silently bypassed.
   - **Priority**: must_have
   - **Model check**: not model-testable -- packaging/interface decision.

---

## Resource Budgets

### Area

| Item | Value | Basis / status |
|---|---|---|
| Standard-cell cap (LDS/I$ excluded) | 500,000 cells | HARD, CON-4 |
| Planning range | 300,000–500,000 cells | PRD `area_budget.notes` |
| `wmma` | 126,245 cells measured + ~10,000–15,000 pipelining | HARD receipt (1.218 mm² measured), pipelining advisory |
| `simd32` x2 | ~180,000 cells | advisory (largest logic block; synthesis risk R5) |
| `command_processor` | ~8,000 cells | advisory |
| `axi_master` | ~8,000 cells | advisory |
| `axi_lite_slave` | ~1,000 cells | advisory |
| `wgp_ctrl` / dispatch | ~8,000 cells | advisory |
| `mem_arb` | ~2,000 cells | advisory |
| `tdm` | ~4,500 cells measured | measured |
| `chip_top` glue | ~1,000 cells | advisory |
| **Logic subtotal (excl. LDS/I$)** | **~350,000 cells** (340–365k) | advisory; below the 500,000 cap |
| `lds` 4 KB (32 banks x 32 x 32) | ~130,000–200,000 cell-equivalents | excluded from the logic cap (PHYS-007) |
| `instruction_ram` 1 KB (256 x 32, 2R1W) | ~30,000–50,000 cell-equivalents | excluded from the logic cap (PHYS-008) |
| Core footprint | 4.5–6.5 mm² advisory (4.0–8.0 allowed; 8.0 ceiling enforced) | PHYS-002; full-chip P&R pending (CON-9) |
| Shuttle die | 3520 x 5188 µm = 18.262 mm² | fixed by OPENFRAME |
| Shuttle user area | 3320 x 4988 µm = 16.560 mm² | fixed by OPENFRAME |
| Target utilization | 40–60% of the user area | planning target (9.936 mm² at 60%) |

Notes: the matrix core and TDM numbers are measured; the SIMD32, CP, AXI and
buffer numbers are planning estimates and must be replaced by synthesis receipts.
The design is not area-closed until full-chip P&R runs on a host with more than
8 GB of memory (CON-9, SAD R6). The flat LDS implementation (~3.3M cells) is
rejected.

### Power

| Item | Value | Basis / status |
|---|---|---|
| Total power budget | <= 2,000 mW | HARD, CON-4 |
| Domain `vccd1` (core, 1.8 V) | <= 2,000 mW | single core domain (FR-CLK-1) |
| Domain `vdda1`/`vssa1` (3.3 V analog) | 0 mW (unused, tied off) | no analog content |
| Domain `vddio`/`vssio` (3.3 V I/O) | wrapper only, outside `chip_top` | AD-19 |
| Peak core current at 2 W / 1.8 V | ~1.11 A | derived |
| Leakage budget | not separately budgeted | PRD `power_budget.leakage_budget_mw = null` |
| Measured reference | TDM 10.1 mW after P&R at 100 MHz | PRD measured reference |
| Estimation method | OpenROAD/OpenSTA with VCD activity at `tt_025C_1v80` | no silicon data exists |

Notes: the 2 W bound is a total-power ceiling, not a per-block allocation; the
per-block figures above are advisory. Per-block clock gating (ICG cells) is
expected at the backend for the SIMD32s, WMMA, TDM and AXI/CP when idle; the RTL
contains no gating (FR-RTL-1). Power must be re-estimated after the LDS/I$
banked structures replace the flat arrays.

---

## Testability Requirements

- **FR-CORE-1/2 (SIMD32, wave32, EXEC, VGPR/SGPR):** directed per-lane VGPR/SGPR/VCC/SCC tests with `EXEC` = 0x00000000, 0x00000001, 0xAAAAAAAA, 0xFFFFFFFF and `WG_SIZE` = 1, 31, 32; compare the full architectural state to the reference after every instruction (INV-008). Self-checking cocotb testbench.
- **FR-CORE-3/4 (matrix core, MXFP4, int32):** the unit WMMA test (A = code 2, B = code 4, K = 32 => C = 256 in the x4 pipeline), the exhaustive E2M1 decode test (all 16 codes x all 16 codes), and the full-chip 16x16x32 matmul with all 256 C words compared byte-exactly (KPI-CORR-001, INV-001, INV-003). Trace points: LDS image after TDM staging and after the C store; VCD `wmma_a/b/c`, `wmma_bank`, `lds_*`.
- **FR-CORE-5 (2x SIMD32 integer path):** per-opcode directed tests for the integer VALU and PERF-005 rate measurement; no F16/FP32 arithmetic is tested or credited.
- **FR-MEM-1 (LDS):** bank/row map test over all 1024 words, conflict-free lane access (1-cycle read), injected bank conflict (must set `STATUS.ERROR` and abort the wave), simultaneous lane/linear-port arbitration, and the multi-tile double-buffer test (INV-002, INV-007, TIME-007, PERF-006).
- **FR-MEM-2 (instruction RAM):** preload 256 words and read back through both ports word-exact; concurrent fetch by both SIMDs; a branch-loop kernel proving the signed-11-bit PC/offset semantics; a second launch with a different image (INV-005).
- **FR-MEM-3 (TDM):** 64-word A and B copies followed by WMMA; a 256-word maximum-length copy; invalid/misaligned descriptor robustness; TDM versus WMMA linear-port arbitration (INV-010, PERF-007).
- **FR-MEM-4 (AXI4):** an AXI4 VIP/protocol checker on every full-chip test, with randomized `RREADY`/`WREADY` back-pressure, a write followed by a read of the same block, and the I$ preload's 8 back-to-back bursts (INV-006, TIME-008, PERF-004).
- **FR-HOST-1/2/3 (CSR, launch, completion):** CSR reset map and readback, START-while-busy, `IRQ_EN` 0/1, `GRID_X` = 1/2/8 => `WAVE_DONE` = 1/2/8, parameter latching at START, and the `STATUS.ERROR` path via an LDS conflict (INV-004, TIME-003, TIME-006).
- **FR-EXEC-1/2/3 (dispatch, ISA, end-of-program):** grid sizes 1/2/8, `WG_SIZE` 1/31/32, mixed vector and matrix workgroups, a wave that errors while another is running, and a directed test for every implemented opcode plus reserved-opcode no-op checks (INV-011, IFACE-006).
- **FR-CLK-1 / FR-RTL-1:** Yosys lint/synthesis for latches, tri-states and SystemVerilog; one-clock SDC; 2-cycle synchronous reset test (TIME-001, TIME-002, PHYS-013).
- **KPI verification and receipts:** PERF-001 (KPI-001), PERF-002 (KPI-PERF-001), INV-001/INV-002/INV-003 (KPI-CORR-001) and INV-012 (KPI-FUNC-001) each report a measured value through `orchestrator.harness.measure.record(<ID>, value, unit=..., test=...)`, appending to `$CORESMITH_MEASUREMENTS`; area and power use `coresmith frd verifier --kind eda --entry area_um2|power_mw`. A bounded item with no measured value is a `tool_error`, not a pass.
- **INV trace-point and first-divergence discipline:** every invariant test prints the first divergence as (case, workgroup, tile, K-block, row/column, lane, expected, actual) and dumps the relevant VCD-visible state (`lds_rdata`, `wmma_c`, `gmem_rdata`, `wave_done`, `status_*`, `irq`, `lds_grant`). The LDS/C trace points are: after TDM staging, after each MFMA's C store, after any SIMD LDS store, and at completion.
- **PHYS-001..014 verification:** Magic DRC, KLayout FEOL/BEOL DRC and density, LVS (`device_delta == 0`, `net_delta == 0`), OpenSTA timing/skew/power, and OpenROAD floorplan/utilization reports. No PHYS item is verified by simulation.
- **MPW-001..006 verification:** the shuttle precheck suite (structure + GDS + KLayout DRC + Magic DRC), wrapper port/OEB checks, and the power-connection check. MPW-006 is verified by the pad-mapping table and the explicit approval record.
- **Golden-model gap (R1/Q-4):** the acceptance artifact's `reference()` is the mission oracle for the matrix and vector paths, but it is self-authored from the same specification. Until a trusted independent Python golden model is supplied, block-level DV (WMMA decode/packing/accumulation) cannot rule out a shared misreading; this gap is recorded and must remain visible in validation DV results.

---

## Mission-Scale Acceptance Test (MANDATORY)

### MISSION-ACC-001 — Full-grid MXFP4 GEMM (8 workgroups x K=256) plus full-grid 32-lane vector add

**Machine-readable stimulus artifact:** `inputs/acceptance_stimulus.py`
(module-level `cases = [(name, stimulus), ...]`, `reference(case)` returning the
golden output, and pinned hashes). Executed by the Full Model DV gate (uarch)
and the RTL Acceptance DV gate.

| Case | Description | Size | SHA-256 (inputs + reference) |
|---|---|---|---|
| `mxfp4_gemm_16x16x256_grid8` | 8 workgroups, each `C_t[16][16] int32 = A[16][256] x B_t[256][16]`, K = 8 blocks of 32 | 64 MFMA ops, 2,048 int32 outputs | `4f35ea387349b50962603009537763855901abe3d18e5835be3ffe88747ac65a` |
| `vecadd_32lane_grid8_x16` | 8 workgroups x 32 lanes x 16 words/lane, `C = (A + B) mod 2^32` | 4,096 int32 lane-additions | `38df5a006c073255d6a1fc7b680af4772e0b13182f8c7d6309d34a9b59729461` |
| bundle | both cases in declared order | — | `801a42110ced93beeb65cde86b34be5a7d69e96e5b2b0e803d54783ac0d7adb9` |

**Scale (axis 1) — a complete unit of the mission, not one tile.** The mission
unit is a full grid of `GRID_X = 8` workgroups with `WG_SIZE = 32` and
`GRID_Y = GRID_Z = 1` (the maximum supported grid and workgroup size, FR-EXEC-1),
executing a K = 256 GEMM as 8 K-blocks of 32. Workgroup `t` computes one 16x16
int32 output tile over the full K extent; the run performs 8 x 8 = 64
back-to-back 16x16x32 MFMA operations (524,288 MAC), stages 2,048 bytes of A and
16,384 bytes of B through the TDM, writes 8,192 bytes of C back through the AXI4
master, and exercises the software cross-K accumulation and the per-tile
double-buffer schedule. The vector-add case adds the second mission path at full
grid: 8 workgroups x 32 lanes x 16 words = 4,096 exact int32 additions through
the AXI4 load/add/store path. A single 16x16x32 tile or one `V_ADD_I32` is a
sub-unit stimulus and is explicitly not acceptance scale; it remains a block
regression only.

**Content class (axis 2) — real-world/boundary-exercising, never flat.** Both
A and B contain all 16 E2M1 codes (0x0–0xF) in every case. Forced boundary
content: an all-max-positive row (`0x7` = +6.0, x2 = +12), an all-zero row
(`0x0`), an all-max-negative row (`0xF` = -6.0, x2 = -12), a negative-zero row
(`0x8`), an all-max-positive B column, an all-max-negative B column, an all-zero
B column, and a negative-zero entry; the per-32-element E8M0 block scales span
exponents 120..134 (including the extremes on A[0] blocks 0/1 and B[0] block 0
columns 0/1). The accumulator range reaches |C| = 36,708, so a zeroed,
truncated, saturating, or mis-decoded MAC tree cannot match the reference. The
vector-add inputs include `0x00000000`, `0x00000001`, `0x7FFFFFFF`,
`0x80000000`, `0xFFFFFFFF`, `0xFFFFFFFE`, `0x40000000`, `0xC0000000` and random
32-bit words, covering the int32 wrap corners. Everything is deterministic from
`SEED = 0x5EEDCDA5`; no external data file is used, and the pinned hashes above
make every gate/revise round compare like-for-like.

**Criterion (axis 3) — the pass bar on that stimulus.** Pass requires all of:

- All 2,048 int32 C words exactly equal `reference(case)["c_int32"]` (KPI-CORR-001
  extended to the full grid); the per-K-block C images are also compared at the
  LDS trace points, so a hardware `+=` that disagrees with AD-8's `C = A*B`
  contract is caught rather than hidden by software accumulation.
- All 4,096 vector-add outputs equal `(a + b) mod 2^32` (KPI-FUNC-001 extended
  to the full grid).
- `STATUS.DONE = 1`, `STATUS.BUSY = 0`, `STATUS.ERROR = 0`, `WAVE_DONE = 8`;
  the level IRQ is asserted and held with `IRQ_EN[0] = 1`.
- Zero unexpected AXI protocol violations and zero `INV-007` starvation/quota
  violations over the run.
- The first divergence, if any, is reported as (case, workgroup, tile, K-block,
  row, column, expected, actual).

**Runtime budget (model-level run).** The Python reference executes in ~0.04 s
measured (budget <= 2 s for both cases). The SystemC LT acceptance run must
complete within 120 s of wall clock on the uArch host. The RTL full-chip run is
estimated at 3,000–5,000 cycles (~30–50 µs at 100 MHz) from reset, derived from
~328 AXI bursts at ~9 cycles each (preload 8, staging 256, C writeback 64) plus
the overlapped compute; this is **advisory**, not a hard ceiling (Q-2;
PRD `latency_budget_us = null`).

**Execution.** The gate drives the host flow end-to-end: AXI4-Lite CSR
programming, the 1 KB kernel image at `KERNEL_PC` fetched by the CP, START,
TDM->LDS staging, the WMMA sequence with per-K-block accumulation in software,
C readback through the AXI4 master, and the vector-add path; the image is
preloaded by the same CP path (AD-12). If the generic gate's framed-stream
adapter does not cover an AXI4/AXI4-Lite chip top, it records an honest skip and
the chip-level cocotb/Verilator testbench with the AXI4/AXI4-Lite BFM runs this
same artifact. The acceptance is not waived and must not be replaced by a
single-tile test; if neither harness can run, acceptance is **undefined** and
must be escalated to the human rather than declared passed.

---

## Model-Level Evaluation

Every requirement above carries a `Model check` line. The evaluation is run on
the SystemC TLM loosely-timed model of the SoC at the end of the uArch stage,
before RTL, via the `model eval` harness (one verdict per FRD item, driven by
the measured workload numbers from the same acceptance artifact).

- **Cycle accounting.** The model's cycle counter at 10 ns/cycle stands in for
  RTL cycles for PERF-003, PERF-005, PERF-006, TIME-001..TIME-007. Loosely-timed
  models omit gate delay and some port-scheduling detail; therefore the
  cycle-based verdicts carry explicit margins: PERF-001 requires the model value
  in [1.024e11, 1.03e11]; PERF-002 requires >= 96.768e9 (5% guard); PERF-003
  allows a one-cycle queue edge (max <= 17) inside the 17.78-cycle amortized
  bound; PERF-006 allows a 5% guard on the aggregate rate. A model pass at the
  exact RTL threshold with no margin is not evidence.
- **Structural items.** IFACE-002/003 port lists, PHYS-001..014 and
  MPW-001..006 are **not model-testable** (elaboration, VIP, DRC/LVS, STA,
  synthesis, packaging); their model checks name the reason. The LT AXI BFM
  still verifies transaction behavior (INV-006, TIME-008, PERF-004).
- **Data items.** INV-001/002/003/009/012 are checked against
  `reference()` on the model's LDS/C values, with the first divergence printed.
  The acceptance artifact is the single source of stimulus and golden output for
  both the model gate and the RTL gate.
- **Bounded items.** Requirements with a `Metric` line (PERF-001..006,
  TIME-001/002/005/006/007) are judged only from a measured value; a pass/fail
  status without a value is a `tool_error`, not a pass.