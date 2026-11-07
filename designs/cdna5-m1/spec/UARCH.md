# CDNA5-M1 microarchitecture and RTL contract

This file is the frozen RTL contract for the M1 design. It mirrors the
CDNA5 work-group processor hierarchy at 1/8 the WGP scale:

```
                        +--------------------------------------+
  AXI4-Lite  ---------->| command_processor (CP)               |
  (host CSRs)           |  CSR file, launch sequencer, I$ load |
                        +------------------+-------------------+
                                           |
                        +------------------v-------------------+
                        | wgp (1 CU, 2 x SIMD32)               |
                        |  +---------+  +---------+            |
  AXI4 master <-------->|  | simd32  |  | simd32  |  I$ 1 KB   |
  (128-bit)    mem_if   |  | SALU+   |  | SALU+   |  (2R)      |
                        |  | VALU    |  | VALU    |            |
                        |  | VGPR    |  | VGPR    |            |
                        |  +----+----+  +----+----+            |
                        |       |            |                 |
                        |  +----v------------v----+  +-------+ |
                        |  | LDS 4 KB, 32 banks   |<-| WMMA  | |
                        |  | 2 lane ports + 1 lin |  | 16x16 | |
                        |  +----------^-----------+  +-------+ |
                        |             |  +-------+             |
                        |             +--| TDM   |             |
                        |                +-------+             |
                        +------------------+-------------------+
                                           |
                                    +------v------+
                                    | axi_master  |
                                    +-------------+
```

## Clocking / reset

* Single clock `clk`, 100 MHz nominal (Sky130 sign-off target).
* Active-low **synchronous** reset `rst_n`. No async resets, no latches, no
  tri-states. Every register is `always @(posedge clk)`.
* All memories are synchronous read (1-cycle). Write is synchronous.

## Instruction fetch

The CP preloads a 1 KB instruction RAM (`icache`) with 256 words from
`KERNEL_PC` before launch. The SIMD PC is a **word index** 0..255. Fetch is
sequential; branches are word-relative. Both SIMDs read the same 256x32 RAM
through two independent read ports. A production CDNA5 would replace this
preload with an I$ and miss handling; the interface (PC -> 32-bit word) is
identical.

## `simd32` (2 instances)

One SIMD32 owns one wave at a time (M1 bring-up; a production CDNA5 SIMD
holds up to 64 resident waves, which is a scheduling concern, not an ISA one).

Ports:

```verilog
module simd32 (
  input  clk, rst_n,
  // launch / status
  input        launch,
  input  [7:0] kernel_pc,          // word index
  input  [15:0] wg_id, wg_size,
  input  [31:0] arg_ptr, lds_base,
  output       busy, done, error,
  // instruction port
  output [7:0]  imem_addr,
  input  [31:0] imem_data,
  // LDS lane port (byte addresses, one per lane)
  output        lds_req, lds_we,
  output [1023:0] lds_addr,        // 32 x 32 bit byte address
  output [1023:0] lds_wdata,
  input  [1023:0] lds_rdata,
  input         lds_ready, lds_conflict,
  // global memory block port (128 B)
  output        gmem_req, gmem_we,
  output [31:0] gmem_addr,
  output [1023:0] gmem_wdata,
  input  [1023:0] gmem_rdata,
  input         gmem_ready,
  // descriptor hand-off to WGP units
  output        wmma_req,
  output [31:0] wmma_a, wmma_b, wmma_c,
  input         wmma_done,
  output        tdm_req,
  output [31:0] tdm_src, tdm_dst, tdm_len,
  input         tdm_done,
  // cycle counter
  input  [63:0] cycle
);
```

Behavior:

1. `launch` seeds `PC`, `EXEC`, SGPRs (s0..s4 per ISA.md), clears VGPRs? No —
   VGPRs are undefined at launch (software initialises). Starts FETCH.
2. FSM: `IDLE -> FETCH -> FETCH_WAIT -> DEC -> EXEC -> ...`. One instruction
   in flight per SIMD; memory/WMMA/TDM instructions park in `WAIT` until the
   unit returns ready.
3. `done` pulses one cycle after `S_ENDPGM`; `busy` deasserts. `error` latches
   on LDS conflict or illegal opcode until reset.
4. Vector write-back happens in `EXEC`; because fetch+decode take two cycles,
   back-to-back dependent instructions do not need a bypass network.
5. `VCC` and `SCC` are per-SIMD state.

## `salu` (inside `simd32`)

SGPR file: 32 x 32-bit (parameter `SGPR_NUM`). Handles all scalar opcodes.
Branches are resolved in `DEC/EXEC` and update the SIMD PC. `S_ENDPGM` ends the
wave. `S_CBRANCH_SCC` and `S_BRANCH` add a signed 11-bit word offset.

## `valu` (inside `simd32`)

32 lanes. Per lane, a 32-bit datapath implements the integer/VALU subset and
the two dot products. Dot units are combinational:

* `V_DOT4_I32_IU8`: 4 x signed 8x8 multiply -> 32-bit add tree.
* `V_DOT8_I32_IU4`: 8 x signed 4x4 multiply -> 32-bit add tree (MXFP4 raw).

Packed F16 add/mul/FMA are implemented in `fp16_lane` and instantiated only
when `ENABLE_F16=1` (default 1). `V_CVT_F32_I32` is a bring-up F16 conversion.

## `lds`

4 KB: 32 banks x 32 rows x 32-bit.

* Lane ports (2): each port supplies 32 byte addresses and one 32-bit write
  data per lane. Bank = `addr[6:2]`, row = `addr[11:7]`. Reads are
  combinational from the synchronous bank array and registered at the port.
  `conflict` is asserted when two lanes of the same port hit one bank with
  different rows; the M1 software model guarantees conflict-free patterns and
  the SIMD raises `error` on a conflict.
* Linear port (1): one 32-word row (`bank 0..31`, row `addr[6:2]`), used by
  WMMA and TDM; always conflict-free, 32 words/cycle.
* Arbitration: lane port 0 > lane port 1 > linear port. A port that is not
  granted sees `ready=0`. LDS is live during WMMA/TDM sequences.

## `wmma`

Fixed `C[16][16] (int32) += A[16][32] (MXFP4) x B[32][16] (MXFP4)`, 16 cycles
of compute (512 MAC/cycle), plus 4 cycles to load A/B (128 words) and 8 cycles
to store C (256 words) through the LDS linear port.

FSM: `IDLE -> LD_A (2 cyc) -> LD_B (2) -> COMPUTE (16) -> ST_C (8) -> DONE`.
Accumulators are cleared at the start of a WMMA (C = A*B, not +=, in v1; the
ISA text says accumulate; the RTL implements C = A*B and software can add C
afterwards — see README "known deviations").

## `tdm`

1-D contiguous copy, `len` words (multiple of 32, <= 256) from a 128-byte
aligned global address to an LDS word address. Uses one gmem block transfer per
32 words and the LDS linear port. This is the bring-up subset of the CDNA5
5-D TDM (descriptors, bounds checks and multicast are future work).

## `command_processor`

AXI4-Lite CSR slave at the chip boundary. Register map:

| Offset | Name | Access | Meaning |
|---|---|---|---|
| 0x000 | CONTROL | RW | bit0 START (self-clearing), bit1 SOFT_RESET |
| 0x004 | STATUS | RO | bit0 BUSY, bit1 DONE, bit2 ERROR |
| 0x008 | KERNEL_PC | RW | byte address of kernel code (1 KB preload) |
| 0x00C | ARG_PTR | RW | byte address of the kernel argument block |
| 0x010 | GRID_X | RW | workgroups (1..8) |
| 0x014 | GRID_Y | RW | reserved, must be 1 |
| 0x018 | GRID_Z | RW | reserved, must be 1 |
| 0x01C | WG_SIZE | RW | work-items per workgroup (1..32) |
| 0x020 | IRQ_EN | RW | bit0 interrupt enable |
| 0x024 | CYCLE_LO | RO | cycle counter low |
| 0x028 | CYCLE_HI | RO | cycle counter high |
| 0x02C | WAVE_DONE | RO | number of completed waves |

Launch sequence: CP copies 1 KB from `KERNEL_PC` into the I$ (8 block reads of
128 B), then hands workgroups to the WGP. Grid workgroups are assigned to the
two SIMDs alternately. `DONE` is set when all workgroups retire; `irq` is
asserted for one cycle (level held until CONTROL.START is written again).

## `axi_master`

* AXI4, 128-bit data, 32-bit address, INCR bursts of 8 beats (128 B).
* One outstanding transaction. `mem_if` request: `req, we, addr[31:0]`
  (128 B aligned), `wdata[1023:0]`, `rdata[1023:0]`, `ready`.
* Read: AR (len=7) -> 8 x R beats -> assemble. Write: AW + 8 x W beats + B.
* `mem_if` arbitration is round-robin between CP, SIMD0, SIMD1 and TDM, with
  CP (I$ preload) highest priority so a launch is never starved.

## Chip top

`cdna5_m1_top` pins:

```verilog
input clk, rst_n;
// AXI4-Lite host control
input  [31:0] s_axil_awaddr;  input s_axil_awvalid; output s_axil_awready;
input  [31:0] s_axil_wdata;   input [3:0] s_axil_wstrb;
input         s_axil_wvalid;  output s_axil_wready;
output [1:0]  s_axil_bresp;   output s_axil_bvalid; input s_axil_bready;
input  [31:0] s_axil_araddr;  input s_axil_arvalid; output s_axil_arready;
output [31:0] s_axil_rdata;   output [1:0] s_axil_rresp;
output        s_axil_rvalid;  input s_axil_rready;
// AXI4 global memory
output [31:0] m_axi_awaddr; output [7:0] m_axi_awlen;
output [2:0]  m_axi_awsize; output [1:0] m_axi_awburst;
output        m_axi_awvalid; input m_axi_awready;
output [127:0] m_axi_wdata;  output [15:0] m_axi_wstrb;
output        m_axi_wlast;   output m_axi_wvalid; input m_axi_wready;
input  [1:0]  m_axi_bresp;   input m_axi_bvalid; output m_axi_bready;
output [31:0] m_axi_araddr;  output [7:0] m_axi_arlen;
output [2:0]  m_axi_arsize;  output [1:0] m_axi_arburst;
output        m_axi_arvalid; input m_axi_arready;
input  [127:0] m_axi_rdata;  input [1:0] m_axi_rresp;
input         m_axi_rlast;   input m_axi_rvalid; output m_axi_rready;
output        irq;
```

## Chip-level resource budget (target)

| Block | Target cells (sky130) | Notes |
|---|---|---|
| 2 x simd32 (incl. VGPR) | ~180 k | 64 lanes, 16 VGPR/lane |
| LDS 4 KB | ~30 k flops | SRAM macro in full config |
| WMMA | ~90 k | 512 FP4 MAC + 256 int32 acc |
| TDM / IC$ / CP | ~25 k | |
| AXI + CSR | ~15 k | |
| **Total** | **~340 k** | 0.1 TFLOP/s MXFP4 @ 100 MHz |

The block-level synthesis and P&R results in `syn/` and `pnr/` are the
authoritative numbers; this table is the planning budget.
