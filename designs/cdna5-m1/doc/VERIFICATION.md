# CDNA5-M1 verification plan and results

Status: **bring-up smoke verification**. Three self-checking simulations run
on Icarus Verilog and pass. This document records the exact test plan, the
observed evidence, the reproduce commands, and the coverage gaps that must be
closed before the M1 can be called verified. It does not claim constrained
random, gate-level or multi-wave signoff.

Date of record: 2026-11-07. Design root:
`/workspace/菩提树/coresmith/designs/cdna5-m1`.

## 1. Scope

Verified today:

* `wmma` matrix core in isolation against a real `lds` instance.
* `cdna5_m1_top` full chip executing a 32-lane vector-add kernel loaded from
  `sw/vecadd.hex`.
* `cdna5_m1_top` full chip executing a TDM -> LDS -> WMMA -> global-memory
  MXFP4 kernel loaded from `sw/wmma_test.hex`.

Not verified today (see §7): constrained-random stimulus, both SIMDs under
load, grids > 1, wave sizes < 32, the F16/FP32 ISA subset, gate level, the
error paths, and the performance counters.

## 2. Toolchain and invocation model

| Item | Version / path |
|---|---|
| Simulator | Icarus Verilog 14.0 (devel) `s20260301-831-g1cb990b6f-dirty` |
| Yosys (not used by DV) | 0.70+344 (git sha1 2f2307ad6) |
| PATH used | `/opt/eda/oss-cad-suite/bin` |
| Language mode | `iverilog -g2005-sv` (Verilog-2005 + SV constructs used by the TBs) |
| Timescale | `1ns/1ps` in all three testbenches |
| Clock | 10 ns period (100 MHz) |

All commands below are run from the design root. `scripts/regress.sh` wraps
the three tests:

```bash
cd /workspace/菩提树/coresmith/designs/cdna5-m1
export PATH=/opt/eda/oss-cad-suite/bin:$PATH
scripts/regress.sh
```

The wrapper invokes `iverilog -g2005-sv -Irtl ...` three times, runs each
`vvp` image, and prints `REGRESSION PASSED` only if all three exit 0. It does
not grep for the `PASS` markers, so read the sim logs as well as the exit
status.

## 3. Test plan

| ID | Level | Testbench | DUT | Stimulus | Checker |
|---|---|---|---|---|---|
| V1 | unit | `tb/tb_wmma.v` | `wmma` + `lds` | A = 1.0, B = 2.0, K = 32 | all 256 C words = 256 |
| V2 | integration | `tb/tb_top.v` | `cdna5_m1_top` | vecadd, 32 lanes | C[i] = 1000 + 2i, STATUS.DONE, IRQ |
| V3 | integration | `tb/tb_wmma_top.v` | `cdna5_m1_top` | TDM + WMMA + copy-out | all 256 C words = 256, STATUS.DONE |
| V4 | random | TODO | all | constrained-random FP4/int | reference model (TODO) |
| V5 | gate level | TODO | netlist + SDF | V1-V3 | timing-aware TB (TODO) |

V1-V3 are directed, deterministic and self-checking. They use a behavioural
AXI4 slave with 1 MB of memory (`tb/tb_top.v:63-151`,
`tb/tb_wmma_top.v:63-136`); no external VIP or memory model is required.

### 3.1 What the unit test checks

`tb_wmma` instantiates `lds` and `wmma` back to back on the LDS linear port.
It writes 64 A words with `32'h22222222` (16 nibbles of E2M1 `0010` = 1.0)
and 64 B words with `32'h44444444` (E2M1 `0100` = 2.0). The expected result
uses the integer decode `{0,1,2,3,4,6,8,12}`:

```
C[i][j] = sum(k=0..31) A_2x * B_2x
        = 32 * (2 * 4) = 256        (integer pipeline, 4x real scale)
```

The TB reads C back 32 words per beat and compares every one of the 256 words
to 256, so it exercises all 16 k-steps, the accumulator path, the load beats
and the store beats.

### 3.2 What the full-chip vecadd test checks

`tb_top` loads `sw/vecadd.hex` via `$readmemh`, fills A[0..31] = i and
B[0..31] = 1000 + i in the behavioural memory, launches one workgroup with
`WG_SIZE=32`, and checks:

```
C[i] = A[i] + B[i] = 1000 + 2*i,  i = 0..31
STATUS[1] == 1 (DONE), irq asserted, no timeout
```

This covers the AXI4-Lite CSR writes, the CP I$ preload (8 x 128 B blocks),
WGP launch, SIMD fetch/decode/execute, `V_MEM_LD`, `V_ADD_I32`, `V_MEM_ST`,
`S_ENDPGM`, the memory arbiter and the AXI4 read/write burst machines.

### 3.3 What the full-chip WMMA test checks

`tb_wmma_top` loads `sw/wmma_test.hex`. The kernel TDM-copies A (64 words at
0x4000) to LDS word 0 and B (64 words at 0x4100) to LDS word 64, issues
`S_WMMA` with A=0, B=64, C=128, then loops 8 times copying the 256-word C
tile to global 0x5000 with `V_LDS_LD` + `V_MEM_ST`. A and B are filled with
the same 1.0 / 2.0 patterns as the unit test, so every one of the 256 C words
must equal 256.

This covers TDM -> LDS, use of the LDS linear port by TDM and WMMA and of the
lane port by the SIMD, `S_WMMA` at non-zero LDS bases, the 16x16 int32 store
beats, `V_LDS_LD`, `V_MEM_ST`, branch/loop control (`S_ADD_U32`, `S_SUB_U32`,
`S_CMP_LT_U32`, `S_CBRANCH_SCC`, `S_BRANCH`) and the WGP descriptor hand-off
for TDM and WMMA. It does not exercise concurrent TDM/WMMA contention.

## 4. Results

All three tests pass with zero `FAIL` lines in the full logs. The end-of-sim
time is Icarus' `$finish` timestamp in the 1 ps precision unit; dividing by
10 ns gives the simulated cycle count.

| ID | Observed PASS line | End of sim | Cycles | FAIL lines |
|---|---|---|---|---|
| V1 | `PASS tb_wmma` | 3,180,000 ps | 318 | 0 |
| V2 | `PASS tb_top (vecadd, 32 cycles)` | 4,850,000 ps | 485 | 0 |
| V3 | `PASS tb_wmma_top (16x16x32 MXFP4, 256 cycles)` | 10,350,000 ps | 1035 | 0 |

**Read the parenthesised numbers carefully.** In V2 and V3 the number printed
by the PASS line is the IRQ polling loop counter (`i` in the TB), not the
total simulated cycle count and not a performance result. The total cycle
counts are the end-of-sim values. V2 polled 32 cycles for the IRQ; V3 polled
256. The simulations ended at 485 and 1035 cycles after time 0, including
reset, I$ preload, CSR setup and host handshakes. The three tests were re-run
after the 2026-11-07 10:49 `rtl/wmma.v` C-store fix; the same PASS lines and
cycle counts were observed.

Supporting debug lines observed in the logs (cosmetic, not checkers):

```
V1: DEBUG word64=44444444
    DEBUG acc0=256 a0=2 b0=4 b1=4
V2: SDBG s0=00001000 s1=00002000 s2=00003000 v01=00000001 v11=000003e9
    WDBG aw=1 w=8 b=1 ar=10 r=80 mem3000=000003e8 v20=000003e8 s2=00003000
V3: DBG tdm_st=2 tdm_dn=2 wmm_st=1 wmm_dn=1 aw=8 w=64 mem5000=00000100 ldsC=00000100
```

`mem5000=00000100` is 0x100 = 256, the expected C value in the integer
pipeline. V3 moved 2 TDM blocks (A and B), 1 WMMA and 8 C store blocks; the
AW/W counters show 8 write bursts of 8 beats.

## 5. Reproduce commands

Run each test from the design root. The unit test needs only `lds.v` and
`wmma.v`; the full-chip tests need all of `rtl/*.v`.

```bash
cd /workspace/菩提树/coresmith/designs/cdna5-m1
export PATH=/opt/eda/oss-cad-suite/bin:$PATH

# V1 -- wmma unit test (expect "PASS tb_wmma")
iverilog -g2005-sv -Irtl -o /tmp/tb_wmma.vvp rtl/lds.v rtl/wmma.v tb/tb_wmma.v
vvp /tmp/tb_wmma.vvp | tee /tmp/tb_wmma.log

# V2 -- full-chip vecadd (expect "PASS tb_top (vecadd, 32 cycles)")
iverilog -g2005-sv -Irtl -o /tmp/tb_top.vvp rtl/*.v tb/tb_top.v
vvp /tmp/tb_top.vvp | tee /tmp/tb_top.log

# V3 -- full-chip TDM + WMMA (expect "PASS tb_wmma_top (16x16x32 MXFP4, 256 cycles)")
iverilog -g2005-sv -Irtl -o /tmp/tb_wmma_top.vvp rtl/*.v tb/tb_wmma_top.v
vvp /tmp/tb_wmma_top.vvp | tee /tmp/tb_wmma_top.log

# all three through the wrapper
scripts/regress.sh
```

Checking pass/fail from the logs:

```bash
grep -c FAIL /tmp/tb_wmma.log /tmp/tb_top.log /tmp/tb_wmma_top.log   # expect 0 0 0
grep -h '^PASS' /tmp/tb_wmma.log /tmp/tb_top.log /tmp/tb_wmma_top.log
```

The testbenches print `DEBUG`, `SDBG`, `VDBG`, `WDBG`, `LDSDBG`, `ADBG` and
`LDBG` lines in the pass path. They are leftovers from bring-up and do not
affect the result; a clean-up is tracked in §8.

## 6. Opcode coverage of the current tests

| Exercised | Not exercised (see §7) |
|---|---|
| `S_MOV_B32`, `S_ADD_U32`, `S_SUB_U32`, `S_CMP_LT_U32` | `S_AND_B32`, `S_OR_B32`, `S_XOR_B32`, `S_SHL_B32`, `S_SHR_B32` |
| `S_BRANCH`, `S_CBRANCH_SCC`, `S_ENDPGM` | `S_BARRIER`, `S_WAITCNT`, `S_GET_WG_ID`, `S_GET_WG_SIZE`, `S_LDS_ADDR`, `S_CSR_READ`, `S_SET_EXEC`, `S_MOV_B64` |
| `V_ADD_I32`, `V_LDS_LD`, `V_MEM_LD`, `V_MEM_ST` | `V_NOP`, `V_MOV_B32`, `V_SUB_I32`, bitwise/shift/mul, `V_CMP_LT_I32`, `V_CNDMASK`, `V_MBCNT_LO_U32` |
| `S_TDM_COPY`, `S_WMMA` | `V_DOT4_I32_IU8`, `V_DOT8_I32_IU4`, all F16, `V_CVT_F32_I32`, `V_LDS_ST`, `V_LDS_LD_IDX`, `V_LDS_ST_IDX`, `V_READFIRSTLANE_B32` |

The ISA has 51 scalar/vector opcodes defined between 0x00 and 0x3A; the three
tests exercise 13 of them and both special-unit ops (S_TDM_COPY, S_WMMA), i.e.
roughly a quarter. There is no opcode-coverage
instrumentation, so the table is a manual audit.

## 7. Coverage gaps

The current suite is a bring-up smoke test. Known gaps, in priority order:

1. **No constrained-random verification.** Every test is directed with one
   fixed pattern (A = 1.0, B = 2.0 or sequential ints). There is no random
   stimulus, no seed management, no reference model and no scoreboard beyond
   a hard-coded expected value.
2. **No F16 or FP32 vectors.** The ISA lists `V_ADD_F16`, `V_MUL_F16`,
   `V_FMA_F16`, `V_CVT_F32_I32` and `V_CVT_F16_F32`, but `rtl/simd32.v` has no
   decode case for them: they fall through to the default and write 0.
   (`spec/UARCH.md` claims an `ENABLE_F16`/`fp16_lane` block; the RTL does not
   contain one. This UARCH/RTL mismatch is a design bug to resolve, not only
   a test gap.)
3. **No negative or corner FP4 values.** The tests use only +1.0 and +2.0,
   so the sign bit, +/-0, 0.5, 1.5, 3, 4 and 6 are unverified in both the
   WMMA and (future) dot8 path. The integer decode x2 scaling is only
   observed for two magnitudes.
4. **No INT8/INT4 dot-product tests.** `V_DOT4_I32_IU8` and `V_DOT8_I32_IU4`
   are completely untested, including two's-complement negatives and the
   `vd += ...` accumulate semantics.
5. **No multi-wave or multi-workgroup stress.** All launches use
   `GRID_X=1`, `WG_SIZE=32`. SIMD1 is never dispatched in the TBs (`u_simd0`
   appears in all probes), the alternation logic in `rtl/wgp.v:240-252` is
   unverified, and `wg_size < 32`/`EXEC` masking is untested.
6. **No LDS stress.** No bank-conflict case, no `V_LDS_ST`, no indexed
   `V_LDS_LD_IDX`/`V_LDS_ST_IDX`, no wrap-around addresses, and the
   `lds_conflict -> error` path in `simd32` is not exercised. The LDS model
   is a plain register array; its synthesis behaviour is a separate risk.
7. **No TDM boundary cases.** Only two 64-word copies are run. The maximum
   `len` of 256 words, `len=32`, unaligned source addresses, a length that is
   not a multiple of 32, and back-to-back TDM copies are untested.
8. **No AXI stress.** Only OKAY responses, full `WSTRB=4'hf` writes, and no
   backpressure are used. `SLVERR`/`DECERR`, `RREADY`/`BREADY` stalls, 4-beat
   and 16-beat bursts, unaligned addresses and read-after-write ordering are
   unverified. There are no AXI protocol assertions.
9. **No reset/error injection.** Reset during a kernel, `SOFT_RESET`, illegal
   opcodes, overflow/underflow of the CSR counters and the WGP `error` latch
   are untested.
10. **No gate-level or timing simulation.** There is no netlist simulation,
    no SDF annotation and no multi-corner check; the RTL may pass while the
    synthesized design fails setup/hold at 100 MHz or behaves differently for
    uninitialised memories.
11. **No formal or assertion-based verification.** No SVA/PSL properties, no
    lint beyond Yosys elaboration, no X-propagation checks.
12. **No coverage metrics.** No line, branch, toggle, FSM state/transition or
    functional covergroups. The pass/fail line is the only metric.
13. **No performance-counter test.** `CYCLE_LO/HI`, `WAVE_DONE`, `IRQ_EN`
    and the interrupt-clear behaviour are not read back in any test.
14. **No long-running soak.** Kernels are 5-8 instructions; there is no test
    with a long loop, many waves or sustained AXI traffic.

## 8. Definition of done

The M1 is "verified" when all of the following hold; the current suite only
partially satisfies item 1 for three directed cases.

1. **Unit level (per block).** Every opcode in `spec/ISA.md` has at least one
   directed test, with corner values for E2M1/INT4/INT8 (both signs, zero,
   max magnitude) and an independent reference. WMMA is checked for all 16
   k-steps with random A/B and a software model.
2. **Random level.** Constrained-random tests with a seed-controlled
   generator, functional coverage bins for operand classes, and a scoreboard
   for both SIMDs; at least 10k WMMA tiles and 10k wave launches per seed.
3. **Integration level.** `GRID_X=1..8`, `WG_SIZE=1..32`, both SIMDs active,
   EXEC masking, back-to-back waves, and the dispatch/arbitration fairness
   cases.
4. **System level.** AXI VIP with protocol assertions, error injection,
   backpressure, partial `WSTRB`, reset during operation, and the full CSR
   map including `CYCLE_LO/HI` and `WAVE_DONE`.
5. **Coverage closure.** 100% opcode decode, 100% FSM states/transitions,
   100% line/branch, and documented functional coverage goals; no `X` on
   checked outputs.
6. **Gate level.** Netlist + SDF simulation of V1-V3 at 100 MHz for
   `tt_025C_1v80` and at least one `ss` corner, all passing.
7. **Regression.** `scripts/regress.sh` plus the random and gate-level suites
   run clean from a clean checkout with pinned tool versions; logs are
   archived with the release.
8. **Cleanliness.** Debug `$display` output is removed from the pass path;
   the three tests print only their `PASS` line and summary counters.
9. **Backend link.** The block netlists and P&R used for gate-level sim are
   the same artifacts signed off in `doc/BACKEND.md` (DRC/LVS/STA).

Until items 2-9 are met, the three PASS lines are evidence of bring-up
correctness only, not of a verified design.
