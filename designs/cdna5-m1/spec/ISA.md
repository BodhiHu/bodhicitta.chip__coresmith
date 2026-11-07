# CDNA5-M1 Instruction Set Architecture (subset)

Status: **frozen for RTL**. This is a compact, implementable subset of the
AMD "CDNA5" ISA (see `amd_cdna5/amd-instinct-cdna5-instruction-set-architecture.pdf`).
It preserves the CDNA5 execution model (wave32, one PC per wave, EXEC mask,
SGPR/VGPR split, SALU/VALU split, LDS, WGP-level matrix core, TDM) but uses a
fixed 32-bit encoding that is **not** binary compatible with gfx-class CDNA5
hardware. The ISA is a design contract, not a claim of encoding compatibility.

## Machine model

| Property | CDNA5 | M1 implementation |
|---|---|---|
| Wave size | 32 work-items | 32 |
| SIMD per CU | 2 x SIMD32 | 2 x SIMD32 |
| CU per WGP | 2 | 1 (M1 ships one CU = half a WGP) |
| SIMD lanes | 32 | 32 |
| VGPRs / lane | up to 1024 | 16 (architectural, parameterisable) |
| SGPRs / wave | 128 | 32 (architectural, parameterisable) |
| EXEC mask | 32 bit | 32 bit |
| LDS / WGP | 320 KB | 4 KB (bring-up), parameterisable to SRAM macros |
| Instruction memory | I$, 64 KB | 1 KB preloaded I$ (bring-up) |
| Tensor data mover | 5-D | 1-D contiguous copy (bring-up) |
| Matrix core | WMMA 16x16xK | WMMA 16x16x32 FP4 / INT4 |

The M1 is a **CDNA5-derived 1-CU compute slice** sized to hit 0.1 TFLOP/s
(MXFP4) at 100 MHz in SkyWater Sky130. A full CDNA5 WGP is two such CUs.

## Instruction encoding

Every instruction is one 32-bit word, except `*_IMM32` forms which consume a
second literal word.

```
31      26 25 24    20 19    15 14    10 9      5 4       0
+---------+--+--------+--------+--------+--------+---------+
| opcode  |I |  dst   |  src0  |  src1  |  src2  |  flags  |
+---------+--+--------+--------+--------+--------+---------+
```

* `opcode[5:0]` — see table.
* `I` — next 32-bit word is a literal (`src1` becomes the literal).
* `dst`, `src0..src2` — SGPR or VGPR index (register file selected by opcode).
* `flags[1:0]` — `00` none, `01` negate src1, `10` absolute src1, `11` reserved.
* For branch/offset forms `src2:flags` carries a signed 11-bit word offset.

Sources may name SGPRs in vector instructions (uniform scalar operand, read
from `src` field). The convention used by this subset:

* Scalar opcodes read/write SGPRs.
* Vector opcodes read/write VGPRs, except a source explicitly marked `sN` in
  the table, which reads SGPR `N` and broadcasts it to all lanes.
* `ss0`/`ss1` in assembly = SGPR operand; `vs0` = VGPR operand.

## Scalar instructions (`opcode[5:4] == 2'b00`)

| Op | Mnemonic | Semantics |
|---|---|---|
| 0x00 | `S_NOP` | no operation |
| 0x01 | `S_MOV_B32 sd, simm32/ssrc` | `sd = src` |
| 0x02 | `S_ADD_U32 sd, ss0, ss1/imm` | `sd = ss0 + ss1` |
| 0x03 | `S_SUB_U32 sd, ss0, ss1/imm` | `sd = ss0 - ss1` |
| 0x04 | `S_AND_B32 sd, ss0, ss1/imm` | bitwise and |
| 0x05 | `S_OR_B32 sd, ss0, ss1/imm` | bitwise or |
| 0x06 | `S_XOR_B32 sd, ss0, ss1/imm` | bitwise xor |
| 0x07 | `S_SHL_B32 sd, ss0, ss1/imm` | shift left |
| 0x08 | `S_SHR_B32 sd, ss0, ss1/imm` | logical shift right |
| 0x09 | `S_CMP_LT_U32 ss0, ss1/imm` | `SCC = ss0 < ss1` |
| 0x0A | `S_CBRANCH_SCC simm11` | `if (SCC) PC += simm11` |
| 0x0B | `S_BRANCH simm11` | `PC += simm11` |
| 0x0C | `S_ENDPGM` | wave complete |
| 0x0D | `S_BARRIER` | wait for all waves in workgroup (NOP for 1-wave WG) |
| 0x0E | `S_WAITCNT imm` | wait for outstanding memory (structural, usually NOP) |
| 0x0F | `S_GET_WG_ID sd` | `sd = workgroup id` |
| 0x10 | `S_GET_WG_SIZE sd` | `sd = workgroup size` |
| 0x11 | `S_MOV_B64` | reserved; not implemented |
| 0x12 | `S_LDS_ADDR sd, ss0` | `sd = LDS byte address of word ss0` (bring-up helper) |
| 0x13 | `S_CSR_READ sd, imm` | read implementation CSR (cycle counter) |
| 0x14 | `S_TDM_COPY` | tensor data mover copy; descriptor in `s[dst..dst+2]`: src global byte address, dst LDS word address, word count (multiple of 32) |
| 0x15 | `S_WMMA` | matrix core; descriptor in `s[dst..dst+2]`: A LDS word, B LDS word, C LDS word. Fixed 16x16x32 FP4 |
| 0x16 | `S_GET_LANE_BASE sd` | lane base of this wave (0) |
| 0x17 | `S_SET_EXEC imm` | `EXEC = imm32` (immediate form) |
| 0x18 | `S_SOFTMAX` | row-wise softmax engine; descriptor in `s[dst..dst+1]`: LDS base word, element count (2..64, even). Input signed Q4.12, output Q0.12, in place |

## Vector instructions (`opcode[5:4] == 2'b01`)

All lanes in `EXEC` execute; inactive lanes write nothing. `lane_id` is the
lane index 0..31.

| Op | Mnemonic | Semantics |
|---|---|---|
| 0x20 | `V_NOP` | no operation |
| 0x21 | `V_MOV_B32 vd, vs0/simm32` | `vd = vs0` |
| 0x22 | `V_ADD_I32 vd, vs0, vs1/imm` | wrap-around add |
| 0x23 | `V_SUB_I32 vd, vs0, vs1/imm` | subtract |
| 0x24 | `V_AND_B32` | bitwise and |
| 0x25 | `V_OR_B32` | bitwise or |
| 0x26 | `V_XOR_B32` | bitwise xor |
| 0x27 | `V_SHL_B32` | shift left |
| 0x28 | `V_SHR_B32` | logical shift right |
| 0x29 | `V_MUL_I32` | low 32 bits of signed product |
| 0x2A | `V_CMP_LT_I32 vd, vs0, vs1` | `VCC[lane] = vs0 < vs1`, `vd` = 1/0 |
| 0x2B | `V_CNDMASK vd, vs0, vs1, vs2` | `vd = vs2 ? vs1 : vs0` |
| 0x2C | `V_MBCNT_LO_U32 vd` | `vd = lane_id` |
| 0x2D | `V_DOT4_I32_IU8 vd, vs0, vs1` | `vd += sum_{k=0..3} int8(vs0[k]) * int8(vs1[k])` |
| 0x2E | `V_DOT8_I32_IU4 vd, vs0, vs1` | `vd += sum_{k=0..7} int4(vs0[k]) * int4(vs1[k])` (MXFP4 raw) |
| 0x2F | `V_CVT_F32_I32` | reserved; not implemented in the bring-up RTL |
| 0x30 | `V_LDS_LD vd, ss0` | `vd = LDS[ss0 + lane_id*4]` (32 consecutive words) |
| 0x31 | `V_LDS_ST ss0, vs0` | `LDS[ss0 + lane_id*4] = vs0` |
| 0x32 | `V_MEM_LD vd, ss0` | `vd = global[ss0 + lane_id*4]`, 128-byte aligned |
| 0x33 | `V_MEM_ST ss0, vs0` | `global[ss0 + lane_id*4] = vs0` |
| 0x34 | `V_ADD_F16` | reserved; F16 vector path is not implemented in the bring-up RTL |
| 0x35 | `V_MUL_F16` | reserved; not implemented |
| 0x36 | `V_FMA_F16` | reserved; not implemented |
| 0x37 | `V_CVT_F16_F32` | reserved; not implemented |
| 0x38 | `V_LDS_LD_IDX vd, vs0` | indexed LDS load at per-lane byte address `vs0` |
| 0x39 | `V_LDS_ST_IDX vs0, vs1` | indexed LDS store |
| 0x3A | `V_READFIRSTLANE_B32 vd, vs0` | broadcast lane 0 (bring-up) |

## Matrix core

`S_SOFTMAX` hands the row `s[dst] .. s[dst]+len/2-1` in LDS to the serialized
softmax engine (`rtl/softmax_engine.v`): it finds the row max, computes
`exp2(x-max)` with the SFU, sums, divides once and writes the normalized
row back in place.  It is a WGP-level AI command, not a lane instruction.

`S_WMMA` executes `C[16][16] += A[16][32] x B[32][16]` where A, B are
**MXFP4 (E2M1)** nibbles and C is int32. A and B are staged in LDS as packed
nibbles (two FP4 per byte, low nibble first). The operation takes 16 cycles
(2 K-slices per cycle, 512 FP4 MAC/cycle) and writes C back to LDS as 256
int32 words. Software applies the E8M0 block scale afterwards (the M1 matrix
core accumulates exact scaled integers; see UARCH).

## Data formats

* MXFP4 E2M1: `{sign, exp[1:0], mant[0]}`; values 0, 0.5, 1, 1.5, 2, 3, 4, 6.
  The M1 decodes to the integer sequence `{0,1,2,3,4,6,8,12}` (x2 scaling) so
  a dot product is exact integer; the x4 product scaling is removed by the
  consumer.
* INT8/INT4: two's complement.
* F16: IEEE binary16 (vector add/mul/FMA).

## Addressing

* `EXEC` is initialised to `(1 << wg_size) - 1` (full mask for wg_size == 32).
* LDS byte address space: 4 KB, 32 banks x 32 rows. Bank = `addr[6:2]`,
  row = `addr[11:7]`. Conflict-free access requires the 32 lane addresses to
  cover 32 distinct banks, which the contiguous `V_LDS_*` forms guarantee.
* Global memory is 32-bit little-endian, 128-byte block transfers.
* Branch offsets are in 32-bit instruction words, relative to the next PC.

## Wave/workgroup state

At wave launch the SIMD seeds:

```
s0 = workgroup_id
s1 = arg_ptr          (byte address of the kernel argument block)
s2 = lds_base         (LDS byte address of the workgroup's LDS slice, 0)
s3 = workgroup_size
s4 = lane_base        (0)
PC = kernel_pc
EXEC = wg_size == 32 ? 0xffffffff : (1<<wg_size)-1
```

This replaces the CDNA5 dispatch/user-SGPR path in the M1 bring-up software
model. A production CDNA5 dispatch would populate the same state from a
dispatch packet.

## Assembly syntax

```
; comment
        s_mov_b32 s0, 0x1000
        v_mov_b32 v0, 0
        v_mbcnt_lo_u32 v1
        v_add_i32 v0, v0, v1
        ...
```

The assembler (`sw/asm.py`) emits a little-endian hex file consumed by the
cocotb harness. Literal forms append a second word.


## Implementation status (RTL v1)

Implemented and verified in `rtl/`:

* scalar ALU and control flow (`S_*` 0x00-0x18 except 0x11),
* integer/bitwise vector ALU (`V_*` 0x20-0x2E),
* LDS and global block loads/stores, TDM copy, WMMA, softmax (0x30-0x33,
  0x38-0x3A, 0x14, 0x15, 0x18),
* EXEC mask, SCC/VCC, wave32.

Reserved in v1 (decode as NOP, no side effects): F16 vector ops 0x34-0x37,
F16 conversion 0x2F, `S_MOV_B64`.  The CDNA5 architecture keeps these in the
ISA; the M1 bring-up targets the MXFP4 matrix path that carries the
0.1 TFLOP/s headline.
