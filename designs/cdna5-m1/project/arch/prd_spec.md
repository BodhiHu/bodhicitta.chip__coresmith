# PRD - CDNA5-M1 0.1 TFLOP/s MXFP4 AI Accelerator on Sky130
**Revision:** 1.0

## Summary
CDNA5-M1 is a scaled, synthesizable implementation of the AMD CDNA5 execution model targeting 0.1 TFLOP/s of MXFP4 throughput on the SkyWater Sky130 HD open PDK. It contains one WGP with one CU (two SIMD32 units, wave32), a 4 KB banked Local Data Share, a WGP-shared 16x16x32 MXFP4 matrix core (8192 MAC per operation, 512 MAC/cycle at 100 MHz = 102.4 GFLOP/s), a 1-D Tensor Data Mover for global-to-LDS staging, an AXI4 128-bit memory master, and an AXI4-Lite host CSR and command processor with a 1 KB preloaded instruction RAM. The design is Verilog-2005, single-clock at 100 MHz with active-low synchronous reset, targets a 4-8 mm^2 die and <=2 W, and is verified by a full-chip TDM->LDS->WMMA->AXI4 16x16x32 matmul and a full-chip 32-lane vector add. It is a bring-up vehicle derived from CDNA5, not binary-compatible with gfx-class hardware.

## Target Technology
- **PDK:** SkyWater Sky130A, sky130_fd_sc_hd (high-density standard-cell library)
- **Process:** 130 nm
- **Rationale:** The Sky130 HD open PDK is the signoff technology available for this run and supports a fully open Yosys/OpenROAD flow. The high-density library is selected for area efficiency at the modest 100 MHz target. Characterization corner is tt_025C_1v80 (1.8 V, 25 C). The measured reference matrix core is 126,245 cells / 1.218 mm^2 in this library, which fits the 300-500k-cell, 4-8 mm^2 envelope. Bring-up memories are flop arrays; production may map LDS and I$ to Sky130 1R1W SRAM macros. No OpenRAM generation is performed in this run.

## Speed & Feeds
- **Input data rate:** 12800 Mbps
- **Output data rate:** 12800 Mbps
- **Target clock:** 100 MHz
- **Latency budget:** None us
- **Throughput:** Matrix roofline: one 16x16x32 MXFP4 MFMA = 8192 MAC = 16,384 FLOP per operation, issued once every 16 cycles at 100 MHz, i.e. 512 MAC/cycle = 1024 FLOP/cycle = 102.4 GFLOP/s peak (1.024e11 FLOP/s, the measured PERF-001/PERF-002 bound). Sustained target is >=90% of peak (>=92.16 GFLOP/s) when A/B operands are fed from LDS. The matrix core is shared per WGP and processes one operation at a time; the two SIMD32 units do not each own a matrix core. The 2x SIMD32 integer vector path executes 32 lanes per SIMD per cycle (6.4 Gops/s aggregate for single-cycle integer ops); no separate vector FLOP target is fixed for this bring-up, and F16/FP32 vector arithmetic is out of scope. Global-memory feed: AXI4 128-bit data at 100 MHz = 12.8 Gbit/s (1.6 GB/s, 12800 Mbps) in each direction, in 128-byte INCR8 bursts. LDS feed: 32 words/cycle x 32 bits = 12.8 GB/s. No host-visible latency budget was fixed; the full-chip TDM->LDS->WMMA->AXI4 acceptance run completes in 1,035 cycles (~10.35 us) from reset.

## Area Budget
- **Max gate count:** 500000
- **Max die area:** 8.0 mm²
- **Notes:** Die target is 4-8 mm^2 including the pad ring. Standard-cell RTL budget is 300,000-500,000 cells; the 500,000-cell cap is the enforced ceiling. Bulk memories (4 KB LDS = 32 banks x 32 rows and 1 KB I$) are excluded from the std-cell cap and are flop arrays in this bring-up (production may use Sky130 1R1W SRAM macros). Measured reference: the matrix core is 126,245 cells / 1.218 mm^2 in sky130_fd_sc_hd. Planned split: matrix core ~126k cells; 2x SIMD32 the next largest block; LDS/I$, TDM, command processor and AXI/CSR logic share the remainder. Full-chip P&R remains to be run on a host with sufficient memory.

## Power Budget
- **Total power:** 2000 mW
- **Power domains:** core
- **Leakage budget:** None mW
- **Notes:** Total budget is <=2 W at 1.8 V, 100 MHz, corner tt_025C_1v80. The design is a single supply/clock domain; per-block clock gating is expected. Leakage is not separately budgeted (no customer constraint stated). No silicon power data exists; power is to be estimated with OpenROAD/OpenSTA. Measured reference: the TDM block after P&R at 100 MHz is 10.1 mW.

## Dataflow
- **Topology:** hybrid
- **Bus protocol:** AXI4 memory master (128-bit) + AXI4-Lite host CSR slave
- **Data width:** 128 bits
- **Buffering:** Host preloads the 1 KB instruction RAM. The TDM copies A/B tiles from global memory into the 4 KB LDS in 128-byte blocks; the WGP-shared matrix core reads A/B operands from LDS and writes the int32 C tile back to LDS; the vector path moves results from LDS to global memory through the AXI4 master. LDS is 32 banks x 32 rows x 32 bits with two lane ports (one per SIMD32) and one linear port shared by the matrix core and TDM. AXI4 uses INCR8 (128-byte) bursts with one outstanding transaction; flow control is AXI ready/valid back-pressure plus LDS port arbitration. No AXI-Stream, no cache hierarchy, no L2.
- **DMA required:** True
- **Notes:** Host control path: AXI4-Lite CSRs CONTROL, STATUS, KERNEL_PC, ARG_PTR, GRID_X, GRID_Y, GRID_Z, WG_SIZE, IRQ_EN, CYCLE and WAVE_DONE. The grid supports up to 8 workgroups; each workgroup has up to 32 work-items and executes as one wave32. Kernel flow: host writes I$ image and CSRs, sets CONTROL.START, the command processor preloads 1 KB of instructions, workgroups launch, and completion sets STATUS.DONE, increments WAVE_DONE and raises a level IRQ when enabled.

## Functional Requirements
- FR-CORE-1: Implement one WGP containing one CU with exactly two SIMD32 execution units; each SIMD32 executes one wave32 (32 work-items) with a single PC and a 32-bit EXEC mask. [HARD, original requirements; architect QA 1,3]
- FR-CORE-2: Each SIMD32 provides 16 VGPRs per lane, 32 SGPRs per wave, VCC and SCC; vector ALU writes are EXEC-masked per lane. [HARD, architect QA 7]
- FR-CORE-3: Provide a WGP-shared MXFP4 matrix core that computes C[16][16] int32 = A[16][32] x B[32][16], 8192 MAC per operation, at 512 MAC/cycle peak and a 16-cycle cadence; the core is shared by both SIMD32 units and processes one operation at a time. [HARD, original requirements; architect QA 3]
- FR-CORE-4: Decode MXFP4 E2M1 operands and accumulate exactly in int32; the E8M0 shared block scale is applied by software or the epilogue, not inside the MAC tree. [HARD, architect QA 3,6]
- FR-CORE-5: Non-matrix execution uses the 2x SIMD32 integer vector path (32 lanes per SIMD per cycle); F16 and FP32 vector arithmetic are out of scope for this bring-up. [HARD, architect QA 3,8]
- FR-MEM-1: Implement a 4 KB LDS organized as 32 banks x 32 rows x 32 bits, with two lane ports (one per SIMD32) and one linear port shared by the matrix core and the TDM; only conflict-free access patterns are supported. [HARD, architect QA 2,3,7]
- FR-MEM-2: Implement a 1 KB instruction RAM (256 x 32-bit, two read ports) that the host preloads before kernel launch. [HARD, architect QA 2,4,7]
- FR-MEM-3: The TDM engine performs 1-D contiguous copies from global memory to LDS in 32-word (128-byte) units, with 128-byte global and 32-word LDS alignment. [HARD, architect QA 3,5]
- FR-MEM-4: Provide an AXI4 global-memory master with 128-bit data, 32-bit address, INCR8 (128-byte) bursts and one outstanding transaction. [HARD, architect QA 5]
- FR-HOST-1: Provide an AXI4-Lite host slave with a 32-bit CSR interface exposing CONTROL, STATUS, KERNEL_PC, ARG_PTR, GRID_X, GRID_Y, GRID_Z, WG_SIZE, IRQ_EN, CYCLE and WAVE_DONE. [HARD, architect QA 5]
- FR-HOST-2: The command processor must preload the 1 KB instruction RAM, start the grid, set STATUS.DONE and clear BUSY on completion, increment WAVE_DONE, and raise a level IRQ when IRQ_EN is set. [HARD, architect QA 5,6]
- FR-HOST-3: Host-visible launch parameters (KERNEL_PC, ARG_PTR, GRID_X/Y/Z, WG_SIZE) are latched at CONTROL.START and define the launched grid and workgroup configuration. [HARD, architect QA 5]
- FR-EXEC-1: The grid supports 1 to 8 workgroups; each workgroup has 1 to 32 work-items and executes as one wave32 on an available SIMD32. [HARD, architect QA 5,7]
- FR-EXEC-2: Implement the frozen 32-bit ISA subset covering scalar/control, vector integer, LDS, WMMA, TDM and S_ENDPGM operations as documented in spec/ISA.md; binary compatibility with CDNA5 gfx encodings is not required. [HARD, original requirements; architect QA 5]
- FR-EXEC-3: A workgroup completes at S_ENDPGM; completion is counted in WAVE_DONE and reported to the host. [HARD, architect QA 5]
- FR-CLK-1: The chip is a single 100 MHz clock domain with an active-low synchronous reset; no asynchronous reset and no second clock domain. [HARD, architect QA 1]
- FR-RTL-1: All RTL is Verilog-2005 and must synthesize through the open-source Yosys/OpenROAD Sky130 HD flow with no latches, no tri-state and no SystemVerilog constructs. [HARD, architect QA 1,2]
- FR-PERF-1: The matrix core must sustain one 16x16x32 MXFP4 MFMA per 16 cycles at 100 MHz, providing 102.4 GFLOP/s peak (1.024e11 FLOP/s, 2 FLOP/MAC). [HARD, architect QA 3,6]
- FR-PERF-2: Sustained matrix throughput must be at least 90% of peak (>=92.16 GFLOP/s) when operands are fed from LDS. [HARD, architect QA 3]
- FR-VER-1: Provide self-checking RTL simulation for (a) the WMMA unit, (b) a full-chip 32-lane vector add, and (c) a full-chip TDM->LDS->WMMA->AXI4 write matmul, all passing at 100 MHz. [HARD, architect QA 6]

## Constraints
- CON-1: Target PDK is SkyWater Sky130A with the sky130_fd_sc_hd standard-cell library, corner tt_025C_1v80, 1.8 V supply. [HARD, architect QA 1]
- CON-2: RTL must be Verilog-2005 with an active-low synchronous reset and a single 100 MHz clock domain. [HARD, architect QA 1; original requirements]
- CON-3: The signoff flow is the open-source Yosys/OpenROAD (OpenLane-style) Sky130 flow. [HARD, architect QA 1]
- CON-4: Die area must be 4-8 mm^2; standard-cell usage must not exceed 500,000 cells; total power must not exceed 2 W at 100 MHz. [HARD, architect QA 4; original requirements]
- CON-5: Bring-up LDS and I$ are flop arrays; no OpenRAM generation is performed in this run. Production LDS/I$ may map to Sky130 1R1W SRAM macros. [HARD, architect QA 2]
- CON-6: The TDM implements 1-D contiguous copies only; the CDNA5 5-D descriptor engine, bounds checks and multicast are out of scope. [HARD, architect QA 3]
- CON-7: F16 and FP32 vector arithmetic are out of scope for this bring-up. [HARD, architect QA 8]
- CON-8: The ISA is a frozen custom 32-bit subset; binary compatibility with CDNA5 gfx-class hardware is not a goal. [HARD, architect QA 5,8]
- CON-9: Full-chip place-and-route requires a host with more than 8 GB of memory and remains pending; block-level P&R results are the current evidence. [HARD, architect QA 8]

## Open Items
- Q-1: Production SRAM macro selection (Sky130 1R1W) for the 4 KB LDS and 1 KB I$, and full-chip P&R on a larger host, remain open. [architect QA 8]
- Q-2: No host-visible latency budget was fixed (kernel-start to first instruction, AXI read request to first beat, LDS load to MFMA operand ready, kernel completion). The full-chip TDM->LDS->WMMA->AXI4 acceptance run takes 1,035 cycles (~10.35 us) from reset; confirm whether a formal latency bound is required. [architect QA 5,6]
- Q-3: Required non-matrix SIMD32 throughput is not fixed beyond the 32-lane vector add; no vector FP4/INT8 dot-product rate is specified for this bring-up. [architect QA 3,8]
- Q-4: The acceptance reference is a software integer model; confirm whether a trusted independent Python golden model is supplied for validation DV, or whether self-authored testbench oracles are accepted. [architect QA 6]

---

## Sizing Q&A (Traceability)
### Which Sky130 PDK variant and standard-cell library is the target: sky130hd (high density) or sky130hs (high speed)?
**Category:** technology
**Answer:** _(not answered)_

### Which Sky130 SRAM macros are permitted for the 4 KB LDS and any other on-die memories, and what port/bank configuration (1RW, 1R1W, 2R1W)?
**Category:** technology
**Answer:** _(not answered)_

### Must the Verilog-2005 RTL synthesize through the open-source Yosys/OpenROAD (OpenLane) Sky130 flow?
**Category:** technology
**Answer:** _(not answered)_

### Does the 0.1 TFLOP/s target count 2 FLOP per MXFP4 MAC, and is it a peak roofline or a sustained target?
**Category:** speed_and_feeds
**Answer:** _(not answered)_

### What is the concrete cycles-per-16x16x32-MXFP4-MFMA target the microarchitecture must hit?
**Category:** speed_and_feeds
**Answer:** _(not answered)_

### What exactly does the '1-D TDM' multiplex, and what is its slot schedule?
**Category:** speed_and_feeds
**Answer:** _(not answered)_

### How many clock domains are there, and are they all 100 MHz?
**Category:** speed_and_feeds
**Answer:** _(not answered)_

### What AXI4 data width and read/write bandwidth must the memory interface sustain?
**Category:** speed_and_feeds
**Answer:** _(not answered)_

### What non-matrix (SIMD/VALU) throughput is required from the 2x SIMD32 pipes?
**Category:** speed_and_feeds
**Answer:** _(not answered)_

### What LDS port/bank configuration and bandwidth does the 4 KB LDS need, and do MFMA operands come from LDS or from VGPRs?
**Category:** speed_and_feeds
**Answer:** _(not answered)_

### What latency budgets apply (host command to kernel start, AXI read request to first beat, LDS load to MFMA operand ready, kernel completion)?
**Category:** speed_and_feeds
**Answer:** _(not answered)_

### Pin the die-area and standard-cell budget: what is the maximum die area, utilization, and the standard-cell flip-flop/gate cap?
**Category:** area
**Answer:** _(not answered)_

### How should the die area be split across the MFMA, 2x SIMD32 VALU, 4 KB LDS, register files, and AXI/control blocks?
**Category:** area
**Answer:** _(not answered)_

### How large is the vector register file per SIMD32 (VGPRs/AGPRs, SGPRs), and how many wave32 work-items must be resident per SIMD32?
**Category:** area
**Answer:** _(not answered)_

### What is the instruction/program storage size and form: instruction RAM, I-cache, or microcode ROM?
**Category:** area
**Answer:** _(not answered)_

### Confirm the 2 W budget: at what core voltage, activity level, and workload, and what leakage share is allowed?
**Category:** power
**Answer:** _(not answered)_

### What power-domain and clock-gating structure is required?
**Category:** power
**Answer:** _(not answered)_

### What is the operand and result dataflow: AXI4 -> ? -> MFMA, and where does the accumulator live?
**Category:** dataflow
**Answer:** _(not answered)_

### What are the AXI4 memory master parameters: address width, max burst length, outstanding transactions, ID width, and read/write channel usage?
**Category:** dataflow
**Answer:** _(not answered)_

### What must the AXI4-Lite host interface expose: register count, command queue depth, interrupt/status bits, and host-visible memories?
**Category:** dataflow
**Answer:** _(not answered)_

### What buffering/FIFO depths are required between AXI4, LDS, and the MFMA, and what is the back-pressure strategy?
**Category:** dataflow
**Answer:** _(not answered)_

### What are the numeric semantics: MXFP4 decode, E8M0 shared-scale application, accumulation precision/rounding, and output format?
**Category:** dataflow
**Answer:** _(not answered)_

### Which CDNA5 ISA subset must be implemented (MFMA shapes, VALU ops, LDS ops, scalar/control ops), and is binary compatibility with an existing compiler/toolchain required?
**Category:** dataflow
**Answer:** _(not answered)_

### What are the maximum design extents the RTL must stay correct at: GEMM M/N/K per kernel, number of MFMA ops (K-accumulation depth) per kernel, and maximum program length?
**Category:** dataflow
**Answer:** _(not answered)_

### What is the mission-scale acceptance test: the complete, real-content stimulus at the accelerator's full operating scale?
**Category:** validation_kpi
**Answer:** _(not answered)_

### What is the numeric correctness pass criterion on that mission-scale stimulus?
**Category:** validation_kpi
**Answer:** _(not answered)_

### What throughput and latency KPIs must validation DV measure on the mission-scale stimulus?
**Category:** validation_kpi
**Answer:** _(not answered)_

### Is there a golden reference model for validation, and what exactly does it model?
**Category:** validation_kpi
**Answer:** _(not answered)_
