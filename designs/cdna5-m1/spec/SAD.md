# CDNA5-M1 — System Architecture Document

| Field | Value |
|---|---|
| Product | CDNA5-M1, 0.1 TFLOP/s MXFP4 accelerator |
| Document | SAD, version 0.1 (architecture baseline) |
| Date | 2026-11-07 |
| Status | Matches the frozen RTL in `rtl/`; synthesis/P&R sections are planning targets |
| Related | `spec/PRD.md`, `spec/FRD.md`, `spec/ISA.md`, `spec/UARCH.md` |

## 1. Scope

This SAD describes the implemented system architecture: block partition,
interfaces, memory and CSR maps, clock/reset, dataflow, and the performance
model. It is written against the current Verilog-2005 RTL
(`rtl/cdna5_m1_top.v` and its children) and the frozen ISA/UARCH contracts.
Unmeasured targets are labelled **planned**. Where the RTL differs from
`UARCH.md`/`ISA.md`, the RTL is authoritative and the difference is listed in
§14 (and as DEV-xx in `spec/FRD.md` §9).

## 2. System context

The M1 is a single-clock accelerator subsystem attached to a host through
AXI4-Lite and to global memory through AXI4:

* **Host:** programs the CSRs, supplies the kernel image/data, starts, waits for IRQ.
* **Global memory:** kernel image (preloaded into I$), arguments, input/output tiles.
* **Chip:** one WGP / 1 CU / 2 SIMD32, 4 KB LDS, 16x16x32 WMMA, 1-D TDM, 1 KB I$, CP.

## 3. Block diagram

```
                    +-------------------------------------------------------+
   clk, rst_n ----->| cdna5_m1_top                                          |
 AXI4-Lite  ------>| axi_lite_slave --> command_processor ----------> irq |
 (host CSRs)        |                     |  CSR file / launch FSM        |
                    |                     |  I$ preload (8 x 128 B)       |
                    |                     |  64-bit cycle counter         |
                    |                     v  wgp_start, grid, wg_size     |
                    |  +-------------------------------------------------+ |
                    |  | wgp (1 CU)                                      | |
                    |  |  +-----------+   +-----------+   I$ 1 KB        | |
                    |  |  | simd32 #0 |   | simd32 #1 |   256x32, 2R     | |
                    |  |  | SALU/VALU |   | SALU/VALU |                   | |
                    |  |  | 16 VGPR/l |   | 16 VGPR/l |                   | |
                    |  |  +-----+-----+   +-----+-----+                   | |
                    |  |        | lane ports      |                       | |
                    |  |  +-----v-----------------v-----+                 | |
                    |  |  | LDS 4 KB, 32 banks x 32 rows |<---+           | |
                    |  |  | 2 lane ports + 1 linear      |    |           | |
                    |  |  +--------------^---------------+    |           | |
                    |  |          +------+------+     +-------+------+    | |
                    |  |          | wmma 16x16x32|    | tdm 1-D copy |    | |
                    |  |          | 512 MAC/cyc |     | 32-word blks |    | |
                    |  |          +-------------+     +--------------+    | |
                    |  |   mem_if: 128 B blocks, SIMD0 > SIMD1 > TDM    | |
                    |  +-------------------------+---------------------+ |
                    |      top arbiter: CP > WGP, 2-cycle cooldown        |
                    |                            v                          |
 AXI4 128-bit <---- |  axi_master (INCR8, 1 outstanding, 128 B)          |
 (global memory)    +-------------------------------------------------------+
```

## 4. Module hierarchy

| File | Module | Function |
|---|---|---|
| `rtl/cdna5_m1_top.v` | `cdna5_m1_top` | Chip boundary, AXI wiring, CP/WGP memory arbiter |
| `rtl/command_processor.v` | `command_processor` | CSR slave, launch FSM, I$ preload, STATUS/IRQ, cycle counter |
| `rtl/wgp.v` | `wgp` | 1-CU shell: I$, 2 SIMDs, LDS, WMMA, TDM, dispatch, mem arbiter |
| `rtl/simd32.v` | `simd32` | Per-wave SALU/SGPR, VALU/VGPR, EXEC/VCC/SCC sequencer |
| `rtl/lds.v` | `lds` | 4 KB banked scratchpad, 2 lane + 1 linear port, conflict detect |
| `rtl/wmma.v` | `wmma` | MXFP4 matrix core, `C[16][16] = A[16][32] x B[32][16]` |
| `rtl/tdm.v` | `tdm` | 1-D contiguous global-to-LDS copy |
| `rtl/axi_master.v` | `axi_master` | AXI4 128-bit master, INCR8 |
| `rtl/axi_lite_slave.v` | `axi_lite_slave` | AXI4-Lite to CSR bridge |
| `rtl/cdna5_m1_defs.vh` | — | Opcodes and parameters (`WAVE_SIZE=32`, `VGPR_NUM=16`, `SGPR_NUM=32`) |
| `rtl/fp4_funcs.vh` | — | MXFP4 E2M1 decode helpers (`{0,1,2,3,4,6,8,12}`) |

### 4.1 `command_processor`

FSM `C_IDLE -> C_PRE -> C_FILL -> C_RUN`. `CONTROL.START` sets `start_pending`;
the CP issues eight 128-byte AXI reads from `KERNEL_PC`, writes 256 words into
the I$, then pulses `wgp_start` with `grid_x`/`wg_size`/`arg_ptr`. `wgp_done`
sets `STATUS.DONE`, clears `BUSY`, increments `WAVE_DONE`, and raises `irq` if
enabled; `wgp_error` sets `ERROR` without `irq`. The cycle counter increments
every clock.

### 4.2 `wgp`

I$ is a 256 x 32 register array with two read ports, written only by the CP.
Dispatch tracks `pending = GRID_X` and gives SIMD0 the first free slot, else
SIMD1; `done` asserts when `pending == 0` and both SIMDs idle, `error` is their
OR. Priority: LDS SIMD0 > SIMD1 > linear; WMMA/TDM one outstanding each, SIMD0
first, TDM waits for WMMA; mem_if SIMD0 > SIMD1 > TDM with 2-cycle cooldown.

### 4.3 `simd32`

One wave per SIMD. FSM `S_IDLE -> S_FETCH -> S_FETCH_W -> S_DEC -> {S_EXEC |
S_LDS_W | S_GMEM_W | S_WMMA_W | S_TDM_W}` (literals add
`S_LIT_FETCH`/`S_LIT_W`). ALU instructions retire every 4 cycles; write-back in
`EXEC` removes the bypass network. `EXEC` gates vector writes; `VCC`/`SCC` are
per-SIMD; `S_ENDPGM` pulses `done`.

### 4.4 `lds`

32 banks x 32 rows x 32-bit; `bank = addr[6:2]`, `row = addr[11:7]`. Reads are
combinational from the bank array and registered at the granted port; writes
are synchronous. The linear port uses row `addr[9:5]` across all banks. One port
is granted per cycle; a lane-port conflict blocks the port and raises `conflict`.

### 4.5 `wmma`

FSM `S_IDLE -> S_LA (4 x 32-word loads + S_LW gaps) -> S_COMP (16 cycles) ->
S_ST (8 x 32-word stores) -> S_DONE`. A is 64 words, B is 64 words, C is 256
int32 words, all 32-word aligned in LDS. Each compute cycle evaluates two
K-slices for 256 outputs (512 FP4 MAC/cycle). v1 computes `C = A*B`.

### 4.6 `tdm`

FSM `S_IDLE -> S_GRD -> S_LWR -> ... -> S_DONE`; for each 32-word chunk it
issues one 128-byte AXI read and writes 32 words into one LDS row through the
linear port. `len` is a multiple of 32 and <= 256 words; the source is
128-byte aligned and the destination 32-word aligned. No bounds checks.

### 4.7 `axi_master` / `axi_lite_slave`

`axi_master`: one INCR8 burst (`AxLEN=7`, `AxSIZE=4`, `AxBURST=01`),
128-byte aligned, one outstanding, 128-byte block assembly. `BRESP`/`RRESP`
are not checked in the bring-up. `axi_lite_slave`: single 32-bit writes and
reads, `WSTRB` ignored, OKAY responses, `addr[7:0]` decode.

## 5. Address maps

### 5.1 Global memory (bring-up software image)

The hardware imposes only 128-byte alignment for AXI4 blocks and TDM sources.
The layout below is the convention used by the current kernels and testbenches.

| Base | Size | Content | Used by |
|---|---|---|---|
| `0x0000_0000` | 1 KB (256 words) | Kernel image, preloaded into I$ | All kernels |
| `0x0000_1000` | 128 B | `A[0..31]` int32 | UC-1 vecadd |
| `0x0000_2000` | 128 B | `B[0..31]` int32 | UC-1 vecadd |
| `0x0000_3000` | 128 B | `C[0..31]` int32 | UC-1 vecadd |
| `0x0000_4000` | 256 B (64 words) | Matrix A: 16 x 32 MXFP4 nibbles | UC-2 matmul |
| `0x0000_4100` | 256 B (64 words) | Matrix B: 32 x 16 MXFP4 nibbles | UC-2 matmul |
| `0x0000_5000` | 1 KB (256 words) | Matrix C: 16 x 16 int32 | UC-2 matmul |

`KERNEL_PC` is the global byte address of the image and must be 128-byte
aligned (the CP always reads eight 128-byte blocks). The wave PC always starts
at I$ word 0, so `KERNEL_PC` is not a code offset.

### 5.2 LDS map (byte addresses)

| Range | Words | Content |
|---|---|---|
| `0x000-0x0FF` | 64 | A tile (16 rows x 16 B packed MXFP4) |
| `0x100-0x1FF` | 64 | B tile (32 rows x 8 B packed MXFP4) |
| `0x200-0x5FF` | 256 | C tile (16 x 16 int32) |
| `0x600-0xFFF` | 640 | Free for double buffering / scratch |

WMMA and TDM bases are 32-word (128-byte) aligned. A 16x16x32 tile uses 1.5 KB,
leaving 2.5 KB for a second stage.

### 5.3 Instruction memory

| Property | Value |
|---|---|
| Size | 1 KB = 256 x 32-bit words |
| Write port | CP only (`ic_we`, `ic_addr[7:0]`, `ic_wdata[31:0]`) |
| Read ports | Two, one per SIMD, synchronous (1 cycle) |
| PC | 8-bit word index 0..255 |
| Branch | Signed 11-bit word offset relative to the next PC |
| Cache behaviour | None (preload only; no miss handling) |

## 6. Clock and reset

* One clock: `clk`, 100 MHz nominal (10.0 ns), single domain.
* One reset: `rst_n`, **active-low synchronous**, sampled on `posedge clk`,
  asserted for >= 2 clocks. No asynchronous reset; no reset synchroniser.
* All flip-flops are `always @(posedge clk)`; memories are synchronous read and
  write; no latches, tri-states, or clock gating in RTL.
* Reset state: CSRs and cycle counter at their reset values (§7), all FSMs
  idle, `irq` low, `STATUS=0`. I$, LDS, and VGPRs are undefined until software
  preloads/initialises them; the CP preloads the I$ before the first launch.

## 7. CSR map

AXI4-Lite 32-bit registers, decode `addr[7:0]`, 4 KB window (mirrored every
256 bytes). Unimplemented offsets read 0 and ignore writes.

| Offset | Name | Access | Reset | Description |
|---|---|---|---|---|
| `0x00` | `CONTROL` | RW | `0x0000_0000` | bit0 `START` (write 1 to launch; launch pulse self-clears, bit reads back as written); bit1 `SOFT_RESET` reserved (stored, no function in RTL) |
| `0x04` | `STATUS` | RO | `0x0000_0000` | bit0 `BUSY`, bit1 `DONE`, bit2 `ERROR` (sticky until next launch) |
| `0x08` | `KERNEL_PC` | RW | `0x0000_0000` | Global byte address of the 1 KB kernel image (128 B aligned) |
| `0x0C` | `ARG_PTR` | RW | `0x0000_0000` | Byte address passed to the wave as `s1` |
| `0x10` | `GRID_X` | RW | `0x0000_0001` | Workgroups to launch, 1..8 (`[7:0]`) |
| `0x14` | `GRID_Y` | RW | `0x0000_0001` | Reserved; write 1. Ignored by the RTL |
| `0x18` | `GRID_Z` | RW | `0x0000_0001` | Reserved; write 1. Ignored by the RTL |
| `0x1C` | `WG_SIZE` | RW | `0x0000_0020` | Work-items per workgroup, 1..32 (`[15:0]`) |
| `0x20` | `IRQ_EN` | RW | `0x0000_0000` | bit0: assert `irq` on completion |
| `0x24` | `CYCLE_LO` | RO | `0x0000_0000` | Free-running clock counter `[31:0]` |
| `0x28` | `CYCLE_HI` | RO | `0x0000_0000` | Clock counter `[63:32]` |
| `0x2C` | `WAVE_DONE` | RO | `0x0000_0000` | Completed launches (RTL counts one per launch; see §14) |
| `0x30` | `ID` | RO | `0x4344_4E35` | ASCII "CDN5" |

Host launch sequence: program `KERNEL_PC`, `ARG_PTR`, `GRID_X`, `WG_SIZE`,
`IRQ_EN`; then write `CONTROL = 1`. Poll `STATUS.BUSY`/`DONE` or wait for
`irq`.

## 8. Dataflow

### 8.1 Launch and instruction preload

```
host -> CONTROL.START
  CP: 8 x (AXI AR 128 B -> 32 words -> I$)          [C_PRE/C_FILL]
  CP: wgp_start pulse, STATUS.BUSY=1, DONE=0
  WGP: pending = GRID_X; launch SIMD0 (then SIMD1) with wg_id, wg_size, arg_ptr
```

### 8.2 UC-1 vector add

```
global A --V_MEM_LD(128 B)--> VGPR v0
global B --V_MEM_LD(128 B)--> VGPR v1
v0 + v1  --V_ADD_I32-------> VGPR v2
v2       --V_MEM_ST(128 B)--> global C
S_ENDPGM -> wave done -> WGP done -> CP: DONE=1, BUSY=0, IRQ
```
Measured in RTL simulation: PASS (446 clocks START->IRQ; 485 from reset release).

### 8.3 UC-2 MXFP4 matrix multiply

```
global A (64 words) --S_TDM_COPY--> LDS A --+
global B (64 words) --S_TDM_COPY--> LDS B --+--> S_WMMA
                                              C = A*B -> LDS C (256 words)
LDS C --V_LDS_LD(32 words)--> VGPR --V_MEM_ST--> global C (8 blocks)
software: apply E8M0 block scale and the x4 integer-pipeline rescale
```
Measured in RTL simulation: PASS (996 clocks START->IRQ for the full image; 1035 from reset release).

### 8.4 Completion and error

```
all waves retire -> wgp.done -> CP: STATUS.DONE=1, BUSY=0, WAVE_DONE++,
                                  irq = IRQ_EN[0]
LDS conflict     -> simd.error -> wgp.error -> CP: STATUS.ERROR=1, BUSY=0,
                                  no irq
```

## 9. Performance model

All rates at 100 MHz (10 ns). "Measured" means RTL simulation on 2026-11-07;
"planned" means target only.

| Item | Value | Derivation / basis | Status |
|---|---|---|---|
| Matrix peak | **102.4 GFLOP/s** | 8192 MAC / 16 cycles = 512 MAC/cycle = 1024 FLOP/cycle | Specified |
| Matrix sustained (1 core) | 51.2 GFLOP/s | 8192 MAC / 32-cycle cadence (7 load + 16 compute + 8 store + 1 done) | Planned |
| Vector FP4 peak | **102.4 GFLOP/s** | 2 x 32 x 8 MAC per cycle, 2 FLOP/MAC | Specified |
| Vector FP4 sustained | 25.6 GFLOP/s | 4-cycle instruction interval per SIMD | Planned |
| INT8 peak | **51.2 GOPS** | 2 x 32 x 4 MAC per cycle, 2 ops/MAC | Specified |
| INT8 sustained | 12.8 GOPS | 4-cycle instruction interval per SIMD | Planned |
| AXI4 bandwidth | 1.6 GB/s | 128-bit x 100 MHz; 128 B per INCR8 burst | Specified |
| LDS bandwidth | 12.8 GB/s | 32 words/cycle x 4 B (one port granted per cycle) | Specified |
| I$ fetch bandwidth | 400 MB/s per SIMD | 32-bit per port per cycle | Specified |
| Instruction interval | 4 cycles / SIMD | fetch + fetch-wait + decode + execute | Structural |
| WMMA issue-to-issue | ~32 cycles core, ~40 SIMD | 4 load beats (3 S_LW gaps) + 16 compute + 8 store + 1 done + handshake | Structural |
| UC-1 latency | **446 clocks** (485 from reset) | START write to `irq`, instrumented bench | Measured |
| UC-2 latency | **996 clocks** (1035 from reset) | START write to `irq`, instrumented bench | Measured |

Illustrative cycle budget for one `S_WMMA` (LDS idle, no contention):

```
S_LA(32w A)  S_LW  S_LA(32w A)  S_LW  S_LA(32w B)  S_LW  S_LA(32w B)   7
S_COMP x 16 (2 K-slices x 256 outputs x 1 MAC)                        16
S_ST x 8 (32 int32 words/cycle)                                        8
S_DONE                                                                 1
total                                                                 32
```

## 10. Resource budget (planned, Sky130)

| Block | Cells / flops | Notes |
|---|---|---|
| 2 x `simd32` (incl. VGPR/SGPR) | ~180 k cells | 64 lanes, 16 VGPR/lane, 32 SGPR/wave |
| LDS 4 KB | ~30 k flops | 32 x 32 x 32-bit array; synthesis expansion is the top area risk; SRAM macro later |
| WMMA | ~90 k cells | 512 FP4 MAC + 256 int32 accumulators |
| TDM / I$ / CP | ~25 k cells | 1 KB I$, 64-bit counter, launch FSM |
| AXI4 / AXI4-Lite / CSR | ~15 k cells | 128-bit master, 32-bit slave |
| **Total** | **~340 k** | Target <= 6.0 mm² core, <= 16 mm² die |

These are planning numbers; synthesis is in progress under `syn/` and no
completed area report exists. No timing, power, P&R, or silicon result exists.

## 11. Error handling

| Condition | Detection | Effect |
|---|---|---|
| LDS bank conflict | `lds.conflict` on a lane port | SIMD sets sticky `error`, aborts the wave; WGP `error`; CP sets `STATUS.ERROR`, clears `BUSY`, no IRQ |
| Illegal opcode | Not detected | Undefined behaviour (falls through to a zero result); must not be used |
| AXI `BRESP`/`RRESP` error | Not checked | Treated as OKAY in the bring-up RTL |
| TDM out-of-range `len`/address | Not checked | Software contract (len multiple of 32, <= 256, aligned) |
| New START while busy | `STATUS.BUSY` | Launch request ignored until the current launch completes |

## 12. Design constraints and coding rules

* **Verilog-2005** RTL; no SystemVerilog constructs, classes, interfaces, or `always_ff`.
* Single clock, active-low synchronous reset; no latches, tri-states, async paths, or delays.
* Memories are synchronous-read; I$ and LDS are inferred register arrays (SRAM-macro portable).
* Parameterise via `rtl/cdna5_m1_defs.vh`; the frozen ISA encoding changes only with a spec revision. `sw/asm.py` is the sole image source (256-word kernels).

## 13. Verification status

| Test | Scope | Result | Notes |
|---|---|---|---|
| `tb_top` | Full chip, UC-1 vecadd, 32 lanes | **PASS** | 446 clocks START->IRQ (485 from reset) |
| `tb_wmma` | WMMA unit against a real `lds` | **PASS** | A=1.0, B=2.0, K=32 => C=256 |
| `tb_wmma_top` | Full chip, UC-2 TDM + WMMA + readback | **PASS** | 996 clocks START->IRQ (1035 from reset) |

No timing-annotated, gate-level, power, or silicon verification exists. The
PASS strings in the in-repo benches print loop indices rather than elapsed
clocks; the clock counts above come from instrumented copies of the same
benches with the same RTL.

## 14. Known deviations and open items

The RTL is authoritative; `UARCH.md` and `ISA.md` contain a few stale claims
(tracked as DEV-xx in `spec/FRD.md` §9). The architecturally significant ones:

1. **WMMA does not accumulate:** `C = A*B` in v1 (ISA says `C += A*B`).
2. **No F16/FP32 vector arithmetic:** opcodes 0x34–0x37 and 0x2F are reserved, not implemented, and not trapped.
3. **No illegal-opcode trap:** only LDS conflicts raise `ERROR`.
4. **`WAVE_DONE` counts completed launches**, not individual waves.
5. **`CONTROL.SOFT_RESET` is unimplemented** (read-back only).
6. **Fixed-priority arbitration:** CP > WGP; SIMD0 > SIMD1 > TDM; SIMD0 lane port > SIMD1 lane port > linear.
7. **TDM is 1-D** with no bounds checks; 5-D descriptors, multicast, and LDS<->DRAM transfers are future work.
8. **No hardware MXFP4 block scale:** int32 C is 4x the nominal FP4 product; software applies the E8M0 scale.
9. **I$ is a 1 KB preload RAM**, not a cache (no misses, no refills).
10. **AXI4-Lite `WSTRB` is ignored**; only full-word writes are supported.
11. **No AXI protocol checker or error-response handling** yet.

Open items: full-chip synthesis and timing/power closure, an AXI VIP, grid=8,
`wg_size<32` DV, LDS-conflict DV, dot-product DV, and a multi-tile TDM/WMMA
benchmark. See `spec/FRD.md` §10.
