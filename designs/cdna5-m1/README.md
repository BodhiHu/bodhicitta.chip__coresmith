# CDNA5-M1 — 0.1 TFLOP/s MXFP4 accelerator (CDNA5-derived, Sky130 bring-up)

> **中文摘要**：本目錄是基於 AMD CDNA 5 架構（白皮書 + CDNA5 ISA 手冊）設計的
> 0.1 TFLOP/s 級 AI 算力芯片，工藝、PDK 與 EDA 流程沿用 `coresmith/`（Sky130
> 130 nm、Yosys / OpenROAD / Magic / netgen / KLayout）。晶片以 1 個 WGP
> （1 CU = 2 x SIMD32）為核心，Matrix Core 每週期 512 個 MXFP4 MAC，在
> 100 MHz 下達到 **102.4 GFLOP/s = 0.1 TFLOP/s**；另提供完整 RTL、驗證、
> 合成與後端腳本。詳細中文說明見 `doc/` 與本節。
>
> **目前結果**：三項 RTL 自我檢查全部 PASS（WMMA 單元、全芯片 vecadd、
> 全芯片 TDM→LDS→WMMA→AXI）；`tdm` 區塊完成 OpenROAD 布局佈線，
> 100 MHz 下 WNS/TNS = 0，功耗 10.1 mW，detailed-route DRC = 0；
> `wmma` 完成 Sky130 合成，126,245 cells / 1.218 mm²。CoreSmith 的
> `make preflight` 回傳 `ok: true`，daemon 已啟動，需求階段已推進到
> decomposition。DeepSeek 已跑通 CoreSmith 架構階段（28 個 PRD 問題 →
> `prd_spec.md` 16 KB → `sad_spec.md` 76 KB），GUI 在 20910/20911。
> **限制**：WMMA 125k-cell 的 P&R 正在 15 GB 主機上重跑；`tdm` 的
> KLayout DRC 已為 0，netgen LVS 尚待處理（1.25M flat references），
> 詳見 `doc/BACKEND.md`。

## What this is

`cdna5-m1` is a scaled, synthesizable implementation of the AMD **CDNA 5**
execution model:

* wave32, one PC per wave, 32-bit `EXEC` mask;
* SALU/SGPR + VALU/VGPR split, one SIMD32 = 32 lanes;
* a **Work-Group Processor (WGP)** containing a CU (2 x SIMD32) with shared
  LDS and a matrix core;
* Local Data Share (LDS), Tensor Data Mover (TDM), instruction cache preload;
* a 16x16x32 **MXFP4** matrix core (the 0.1 TFLOP/s engine);
* AXI4 host control (AXI4-Lite) and AXI4 global memory.

It is derived from, but not binary-compatible with, `gfx`-class CDNA 5
hardware. The encoding is a compact 32-bit subset defined in
[`spec/ISA.md`](spec/ISA.md); the execution model, data formats, memory
hierarchy and work-group semantics follow the AMD CDNA5 ISA manual and
whitepaper in `amd_cdna5/`.

## Why 0.1 TFLOP/s

```
Matrix core:  512 FP4 MAC/cycle x 2 FLOP/MAC x 100 MHz = 102.4 GFLOP/s
Vector dot8:  2 SIMD x 32 lanes x 8 MAC x 2 x 100 MHz   = 102.4 GFLOP/s
INT8 dot4:    2 SIMD x 32 lanes x 4 MAC x 2 x 100 MHz   =  51.2 GOPS
int32 ALU:    2 SIMD x 32 lanes x 1 op  x 100 MHz        =   6.4 GOPS
```

`0.1 TFLOP/s` is the **MXFP4** (E2M1) matrix number, matching AMD's headline
metric for MI455X (OCP MXFP4). The full arithmetic, roofline and bandwidth
analysis is in [`doc/PERFORMANCE.md`](doc/PERFORMANCE.md).

The M1 ships **one CU (half of a CDNA5 WGP)** to land exactly on the target
with a 130 nm standard-cell budget. A full CDNA5 WGP (2 CUs) would be
~0.2 TFLOP/s at the same clock; the matrix core itself is shared per WGP in
the real architecture, so the M1 keeps the matrix throughput of a small WGP
while cutting vector area.

## Architecture

```
AXI4-Lite host CSRs
       |
  command_processor  (kernel launch, 1 KB I$ preload, completion IRQ)
       |
  wgp  (1 CU)
   ├── icache 1 KB (256 x 32, dual read)
   ├── simd32 #0   wave32: SALU+SGPR, 32-lane VALU, 16 VGPR/lane
   ├── simd32 #1
   ├── lds 4 KB, 32 banks x 32 rows (2 lane ports + 1 linear port)
   ├── wmma 16x16x32 MXFP4 -> int32, 512 MAC/cycle
   └── tdm 1-D contiguous global->LDS copy
       |
  memory arbiter -> AXI4 master (128-bit, 8-beat INCR)
```

Detailed block diagram, memory map, CSR map and dataflow:
[`spec/SAD.md`](spec/SAD.md).  Microarchitecture and RTL contract:
[`spec/UARCH.md`](spec/UARCH.md).

## Verification (measured)

| Test | Scope | Result |
|---|---|---|
| `tb/tb_wmma.v` | WMMA unit against a real LDS: A=1.0, B=2.0, K=32 -> C=256 | **PASS** (318 cycles) |
| `tb/tb_top.v` | full chip: AXI4-Lite launch, I$ preload, 32-lane vector add, IRQ | **PASS** (485 cycles from reset) |
| `tb/tb_wmma_top.v` | full chip: TDM -> LDS -> WMMA -> vector read -> AXI write | **PASS** (1,035 cycles from reset) |

Reproduce (uses the OSS-CAD-Suite binaries installed for CoreSmith):

```bash
cd coresmith/designs/cdna5-m1
export PATH=/opt/eda/oss-cad-suite/bin:$PATH

# WMMA unit
iverilog -g2005-sv -Irtl -o /tmp/tb_wmma.vvp rtl/lds.v rtl/wmma.v tb/tb_wmma.v
vvp /tmp/tb_wmma.vvp

# full chip vecadd
iverilog -g2005-sv -Irtl -o /tmp/tb_top.vvp rtl/*.v tb/tb_top.v
vvp /tmp/tb_top.vvp

# full chip MXFP4 matmul
iverilog -g2005-sv -Irtl -o /tmp/tb_wmma_top.vvp rtl/*.v tb/tb_wmma_top.v
vvp /tmp/tb_wmma_top.vvp
```

`scripts/regress.sh` runs all three and reports pass/fail.

## Assemble a kernel

```bash
python3 sw/asm.py sw/vecadd.s -o sw/vecadd.hex
python3 sw/asm.py sw/wmma_test.s -o sw/wmma_test.hex
```

The ISA subset and instruction semantics are in [`spec/ISA.md`](spec/ISA.md);
the assembler is `sw/asm.py`.

## Backend / process

Everything physical uses the **CoreSmith Sky130 deployment**:

* PDK: `.pdk/sky130A` (SkyWater Sky130 HD, `sky130_fd_sc_hd`, tt_025C_1v80),
  pinned by `coresmith/scripts/pdk-version.env`;
* synthesis: Yosys 0.70+ with the Sky130 Liberty;
* P&R: OpenROAD, script adapted from
  `coresmith/orchestrator/pdk_templates/sky130/pnr_reference.tcl`;
* GDS/DRC/LVS: Magic 8.3, netgen 1.5, KLayout 0.28;
* timing: OpenSTA at 100 MHz (`constraints/*.sdc`).

Synthesis and P&R scripts and measured reports live in `syn/`, `pnr/` and
[`doc/BACKEND.md`](doc/BACKEND.md).  The full-chip netlist is large; the
signoff P&R target is the matrix core (`wmma`) and the SIMD (`simd32`) block,
with full-chip area/timing estimated from the block results and reported in
`doc/BACKEND.md` / `syn/`.

Measured so far (Yosys 0.70, Sky130 HD tt_025C_1v80):

| Block | Cells | Chip area | Notes |
|---|---|---|---|
| `wmma` | 126,245 | 1.218 mm² | 512 FP4 MAC + 256 int32 acc; 8,192 flop bits |
| `tdm` | 4,476 | 0.036 mm² | 1-D copy engine; P&R WNS 0.00 ns @100 MHz, 10.1 mW, 0 route DRC |
| `simd32` | (running) | | 32-lane SIMD, 16 VGPR/lane |

The full-chip area target (~3 mm²) uses the matrix core above, two SIMD32
slices, 4 KB LDS + 1 KB I$ as Sky130 SRAM macros (2 KB macro = 0.284 mm²),
and the control/AXI/TDM logic.

## Directory map

| Path | Contents |
|---|---|
| `spec/` | PRD, FRD, SAD, ISA, UARCH (frozen contracts) |
| `rtl/` | Verilog-2005 chip, WGP, SIMD32, LDS, WMMA, TDM, CP, AXI |
| `tb/` | iverilog self-checking testbenches |
| `sw/` | assembler and kernel images (`vecadd`, `wmma_test`) |
| `constraints/` | 100 MHz SDC |
| `syn/` | Yosys scripts, netlists, area/timing logs |
| `pnr/` | OpenROAD scripts, DEF/GDS, DRC/LVS reports |
| `doc/` | performance, verification, backend write-ups |
| `scripts/` | one-command regression and flow drivers |

## Known deviations from a production CDNA5 part

* **One CU**, not a full 2-CU WGP; the matrix core carries the AI throughput.
* **100 MHz Sky130** instead of 2.4 GHz N2/N3; the architecture is identical,
  the process is two generations behind (that is the point of the
  CoreSmith-based bring-up).
* **Integer exact accumulation** in the matrix core (decoded E2M1 integers);
  the OCP MX block scale (E8M0) is applied by the epilogue/software, not in
  the MAC tree.  This makes the RTL exactly testable against integer models.
* **LDS 4 KB** and **I$ 1 KB** instead of 320 KB / 64 KB; both are
  parameterisable and would map to Sky130 SRAM macros in a full build.
* **TDM is 1-D contiguous**; the CDNA5 descriptor is 5-D with bounds checks
  and multicast.  The data path is the same, the descriptor engine is future
  work.
* F16/FP32 vector ops are reserved in the bring-up RTL; the MXFP4 matrix and
  integer vector paths are implemented.
* No binary compatibility with CDNA5 `gfx` encodings.

## Status

* [x] CoreSmith toolchain + Sky130 PDK; `make preflight` -> `{"ok": true}`
* [x] `coresmith daemon` running; requirements stage registered and advanced to `decomposition`
* [x] ISA/uarch freeze
* [x] RTL: chip, CP, WGP, 2x SIMD32, LDS, WMMA, TDM, AXI4/Lite
* [x] Unit + full-chip functional simulation (3/3 PASS)
* [x] Sky130 synthesis: `wmma` 126,245 cells / 1.218 mm²; `tdm` 4,476 cells / 0.036 mm²
* [x] OpenROAD P&R on `tdm`: WNS 0.00 ns @100 MHz, 10.1 mW, 0 route DRC; valid GDS generated by KLayout
* [x] KLayout DRC on the `tdm` GDS: **0 violations** (`pnr/tdm/klayout_drc.txt`)
* [ ] netgen LVS / Magic extraction on the `tdm` GDS — KLayout LVS pin/format issues; Magic extraction very slow on the 1.25 M-reference GDS
* [ ] P&R on `wmma` (126 k cells) — needs a larger memory budget
* [ ] Full-chip GDS/DRC/LVS — blocked by host memory (see `doc/BACKEND.md`)
* [ ] Full-chip PPA roll-up

See [`doc/VERIFICATION.md`](doc/VERIFICATION.md) and
[`doc/BACKEND.md`](doc/BACKEND.md) for the current evidence and commands.

### CoreSmith + DeepSeek evidence

* `CORESMITH_LLM_PROVIDER=claude`, `CORESMITH_MODEL=deepseek-flash`,
  `ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic` in
  `coresmith/.env.local`; `@anthropic-ai/claude-code` 2.1.319 installed.
* The architecture graph ran end-to-end on DeepSeek: 28 PRD questions,
  architect feedback, then `project/arch/prd_spec.md` (16 KB) and
  `project/arch/sad_spec.md` (76 KB) were generated by `deepseek-flash`.
* Browser consoles:
  * design console: `http://127.0.0.1:20910/`
    (`designs/cdna5-m1/gui/app.py`; requirements intake, architecture/run,
    evidence, progress logs)
  * CoreSmith run dashboard: `http://127.0.0.1:20911/`
    (`orchestrator/vscode-ext/serve.py`, read-only trajectory/review)

### CoreSmith setup evidence

```text
$ source designs/cdna5-m1/scripts/env.sh
$ cd coresmith && make preflight
{"ok": true, "errors": [], "warnings": ["CORESMITH_ALLOW_NO_OPENRAM=1 ..."]}

$ coresmith daemon start --project-root .../project
daemon started pid=... port=...
$ coresmith stage status --json
stage: requirements, blocked_by: [MISSING_ARTIFACT prd, frd]
$ coresmith prd add "0.1 TFLOP/s MXFP4 at 100 MHz" --id KPI-001 ...
$ coresmith frd add "Matrix core sustains 102.4 GFLOP/s ..." --id PERF-001 ...
$ coresmith frd edit PERF-001 --derives-from KPI-001
$ coresmith stage next
{"advanced": true, "stage": "decomposition"}
```

The local arm64 install (OSS-CAD-Suite + apt Magic/netgen/KLayout + source
OpenROAD/OpenSTA + manual Sky130 PDK) is documented in
[`../../SETUP-ARM64.md`](../../SETUP-ARM64.md).
