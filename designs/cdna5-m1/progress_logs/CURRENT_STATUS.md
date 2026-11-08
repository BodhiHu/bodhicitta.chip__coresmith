# CDNA5-M1 — current status

**Date:** 2026-11-08
**Repo:** `coresmith/` (branch `bodhi/main`)
**Design root:** `coresmith/designs/cdna5-m1`
**Status:** AI-only RTL + operator/ROCm bring-up complete and reproducible;
backend flat P&R / full-WGP synthesis still open.

This file is the single place to read before continuing.  It records what is
actually implemented and measured, not what is planned.  The per-round logs in
this directory (`2026-11-07-round1.md` … `round8.md`) contain the detailed
history and commands.

---

## 1. Scope

CDNA5-M1 is an **AI-only** accelerator.  It has **no graphics, video, display,
raster, texture, JPEG/HEVC/AV1 codec, ray-tracing, audio, GPUVM/MMU or
graphics memory-format block or instruction**.  The removal table and the
enforcement checks are in [`spec/AI_SCOPE.md`](../spec/AI_SCOPE.md).

The implemented compute slice is:

* 1 WGP / 1 CU / 2× SIMD32, wave32, 32-lane EXEC mask
* 16×16×32 MXFP4 WMMA (E2M1, exact int32 accumulate), 512 MAC/cycle
  → **102.4 GFLOP/s** at 100 MHz
* 4 KB LDS (32 banks × 32 rows), 1 KB host-preloaded I$
* 1-D TDM (global → LDS), AXI4 128-bit master, AXI4-Lite host CSR
* serialized SFU (`exp2`, `rcp`)
* LDS softmax engine + `S_SOFTMAX` scalar command in the WGP
* Verilog-2005, single 100 MHz clock, active-low synchronous reset,
  Sky130 HD `tt_025C_1v80`

---

## 2. Verified results (measured on this host)

### 2.1 RTL / full-chip

| Check | Command | Measured result |
|---|---|---|
| SFU unit | `./scripts/check_sfu.sh` | **PASS**; exp2 max abs **3.53e-4**, rcp max rel **2.51e-4**, 4-cycle latency |
| Softmax engine | `./scripts/check_softmax.sh` | **PASS**; row sums **4064 / 4090 / 4036** |
| WGP softmax | `./scripts/check_wgp_softmax.sh` | **PASS**; one-hot first **1393**, other **87**, sum **4090** |
| Full-chip softmax | `./scripts/check_top_softmax.sh` | **PASS**; TDM → LDS → `S_SOFTMAX` → AXI, **940 cycles, row sum 4064** |
| Full-chip GEMM tile | `./scripts/check_wmma_top.sh` | **PASS**; 16×16×32 MXFP4, **256 cycles** |
| Full-chip vecadd regression | `tb_top` | **PASS**, 32 cycles |

The full-chip softmax path uses the real `cdna5_m1_top` boundary: AXI4-Lite
CSR writes, CP I$ preload, `S_TDM_COPY`, softmax engine over the LDS linear /
scalar port, `V_LDS_LD` + `V_MEM_ST`, AXI4 write-back and IRQ.

### 2.2 Operator model

`./scripts/run_operators.sh` builds `sim/` and `rocm/` and runs:

| Operator | Shape | Result |
|---|---|---|
| GEMM MXFP4 | 64×64×64 | **PASS**, exact int32, **512 cycles, 102.4 GFLOP/s** @100 MHz |
| Softmax FP16 | 8×128 | **PASS**, max error **1.716e-3** (tolerance 2e-3) |
| FlashAttention FP16 | seq=32, dim=16, causal | **PASS**, max error **1.004e-3** (tolerance 2e-2) |

The model mirrors the RTL WMMA E2M1 decode, 4 KB LDS, TDM and SFU.  It is a
functional/cycle model, **not** gate-level RTL.  FlashAttention is model-only;
there is no FP16 RTL matrix path.

### 2.3 CDNA5 ROCm source/API compatibility

`rocm/` provides HIP and HSA **source/API-level** shims, not a gfx1250 binary
runtime.  Five examples pass:

```text
PASS hip_saxpy (n=1024, 0 errors)
PASS hip_gemm_m1 (64x64x64 FP4, max_err=0)
PASS hip_softmax_m1 (8x128, row-sum err=4.548e-04)
PASS hip_flash_attention_m1 (seq=32 dim=16, err=0.000e+00)
PASS hsa_demo (agent/queue/signal/dispatch, 0 errors)
```

The exact compatibility matrix and non-claims are in
[`spec/ROCM_COMPAT.md`](../spec/ROCM_COMPAT.md): no AMDGPU ELF/HSACO, no ROCr
ABI, no native hipBLASLt/rocBLAS/MIOpen.

### 2.4 EDA / synthesis

| Block | Cells | Area | Notes |
|---|---:|---:|---|
| `wmma` | 126,245 | 1,218,412.3 µm² | matrix core |
| `tdm` | 4,476 | 36,216.0 µm² | 1-D mover |
| `axi_lite_slave` | 397 | 3,783.6 µm² | host CSR |
| `sfu` | 1,728 | 12,714.7 µm² | exp2/rcp |
| `softmax_engine` | 4,410 | 33,388.3 µm² | serial restoring divider |

`tdm` P&R: WNS/TNS **0.00 ns**, **10.1 mW**, **0 route DRC**;
KLayout DRC **0 violations**.  `make preflight` returns **`"ok": true`**.

### 2.5 Current backend limits (do not overclaim)

* **WMMA flat P&R does not converge.**  At 45% utilization detailed route
  stalls at 126,726 violations; at 30% it reaches 255,357 → 355,997.  The
  2,096-pin block with 1,024-bit LDS read/write buses is the congestion
  source.  A routeable build needs narrower buses, SRAM macros, or a
  hierarchical/chiplet partition.
* **Full `wgp` synthesis does not finish** within 600 s.  The serial divider
  removed the softmax-specific timeout, but the unrolled WMMA creates a very
  large ABC problem (the last background run exited 124).  No WGP area/timing
  figure is claimed.
* **TDM LVS is not complete.**  KLayout DRC is 0; KLayout LVS reaches the
  comparison section but was OOM-killed, and netgen LVS is still open.
* **SFU is not a standalone SIMD instruction.**  It is used by
  `softmax_engine` but is not exposed via `simd32` directly.
* **FlashAttention is model-level.**  No FP16 RTL datapath.
* **gfx1250 binary compatibility is out of scope.**  The ROCm path is
  source/API-level only.

---

## 3. Repository map

```text
designs/cdna5-m1/
  README.md                  design overview + status
  spec/
    PRD.md FRD.md SAD.md ISA.md UARCH.md
    AI_SCOPE.md              AI-only scope, graphics removal table
    ROCM_COMPAT.md           HIP/HSA compatibility matrix and limits
  doc/
    CDNA5-M1_Architecture.docx  editable architecture Word document
    BACKEND.md PERFORMANCE.md VERIFICATION.md OPERATORS.md
    CORESMITH_INTEGRATION.md
  rtl/
    cdna5_m1_top.v command_processor.v axi_lite_slave.v axi_master.v
    wgp.v simd32.v lds.v wmma.v tdm.v sfu.v softmax_engine.v
    cdna5_m1_defs.vh fp4_funcs.vh
  tb/
    tb_top.v tb_wmma_top.v tb_wmma.v tb_sfu.v tb_softmax_engine.v
    tb_wgp_softmax.v tb_top_softmax.v
  sw/
    asm.py vecadd.s/hex wmma_test.s/hex softmax.s/hex softmax_top.s/hex
  sim/                       M1 functional/cycle model + operator runner
  rocm/                      HIP/HSA headers, shim, examples, CMake
  scripts/
    env.sh check_sfu.sh check_softmax.sh check_wgp_softmax.sh
    check_top_softmax.sh check_wmma_top.sh run_operators.sh
    synth.sh run_pnr.sh pnr.tcl regress.sh patch_lvs_cdl.py
  syn/                       synthesis scripts/reports (netlists ignored)
  pnr/                       P&R reports + KLayout DRC report
  progress_logs/             per-round logs + this file
  project/                   CoreSmith project DB + arch/ docs
```

### What is intentionally not committed

Large/regenerable artifacts are ignored by
[`designs/cdna5-m1/.gitignore`](../.gitignore): `syn/*/*_netlist.v`,
`syn/*/*.json`, `syn/*/yosys.log`, `syn/*/synth.ys`, `pnr/*/*.gds`,
`pnr/*/*.def`, `pnr/*/*_pnr.v`, `pnr/*/*.pwr.v`, `pnr/*/*.cdl`,
`pnr/*/*.cir`, `pnr/*/*.spice`, `pnr/*/*.lvsdb`, `sim/build/`,
`rocm/build/`.  They can be regenerated with the scripts above.  The KLayout
DRC report and summaries are tracked.

The CoreSmith project DB (`project/.coresmith/`) is ignored; the rendered
architecture documents under `project/arch/` are tracked.

---

## 4. Reproduce

### 4.1 Existing arm64 host

See [`SETUP-ARM64.md`](../../../SETUP-ARM64.md).  Then:

```bash
cd /workspace/菩提树/coresmith
source designs/cdna5-m1/scripts/env.sh
make preflight

cd designs/cdna5-m1
./scripts/check_all.sh
```

`check_all.sh` runs the SFU, softmax engine, WGP softmax, full-chip
softmax, full-chip GEMM tile and the operator/ROCm examples.  Expected: all
PASS; full-chip softmax 940 cycles / sum 4064; GEMM tile 256 cycles; ROCm
5/5.  The individual scripts are listed in the table in section 2.1.

### 4.2 Docker (Ubuntu 24.04 / arm64)

The toolchain install is captured in
[`Dockerfile_ubuntu2404_arm64`](../../../Dockerfile_ubuntu2404_arm64).  Build and
run from the `coresmith/` root:

```bash
docker build --platform linux/arm64 \
  -f Dockerfile_ubuntu2404_arm64 \
  -t coresmith-arm64 .

docker run --rm -it --platform linux/arm64 \
  -v "$PWD":/opt/coresmith \
  coresmith-arm64
```

Inside the container:

```bash
cd /opt/coresmith
source designs/cdna5-m1/scripts/env.sh
make preflight
cd designs/cdna5-m1
./scripts/check_top_softmax.sh
./scripts/run_operators.sh
```

The Docker build compiles OpenROAD/OpenSTA/Magic and downloads Sky130, so it
needs a large disk, several GB of RAM and network access.  Build time is
dominated by OpenROAD Bazel.

**Verification note:** this environment has no Docker/Podman executable, so
the Dockerfile was not built here.  It is a direct transcription of the
verified `SETUP-ARM64.md` steps; the host-side toolchain and all design checks
above were run and passed.  Treat the first Docker build as a toolchain
bring-up step and pin `OPENROAD_REF`/`BAZELISK_VERSION` if long-term
reproducibility matters.

### 4.3 Architecture Word document

The complete architecture document is
[`doc/CDNA5-M1_Architecture.docx`](../doc/CDNA5-M1_Architecture.docx).  Its six
diagrams are native Word VML groups, so they can be clicked and edited in
Word (text, position, color, grouping).  Regenerate it with:

```bash
cd designs/cdna5-m1
../../venv/bin/python scripts/generate_architecture_docx.py
```

### 4.4 GUI

```bash
cd designs/cdna5-m1
../../venv/bin/python gui/app.py --host 0.0.0.0 --port 20910
# CoreSmith read-only dashboard, separate process:
CORESMITH_PROJECT_ROOT=$PWD/project \
  ../../venv/bin/python ../../orchestrator/vscode-ext/serve.py --port 20911
```

* Design console: <http://127.0.0.1:20910/>
* CoreSmith dashboard: <http://127.0.0.1:20911/>

Both were verified HTTP 200 in this session.  The console's **AI operators**
tab runs the RTL checks and the operator/ROCm examples.

---

## 5. Git state

Recent commits (newest first):

| Commit | Content |
|---|---|
| `66d6e34` | full-chip GEMM check + objective closure evidence |
| `156f26c` | GUI softmax card update |
| `d0bc78b` | serial restoring divider |
| `e059716` | full-chip TDM→softmax→AXI path |
| `637f7c8` | S_SOFTMAX assembler/ISA docs + ignore generated synth script |
| `c8dac10` | S_SOFTMAX assembler support |
| `5cdeaf2` | console runs RTL SFU/softmax checks |
| `ce58b55` | S_SOFTMAX wired into WGP |
| `96761d1` | console RTL SFU/softmax cards |
| `e257a49` | LDS softmax engine + test + synthesis |

Earlier: `23c0b2e`, `a386785`, `581f05a`, `cb9f23f`, `18a14c0`, `980eed2`.

`git status` is clean after this status file and the Dockerfile are committed.

---

## 6. Next work (in priority order)

1. **WMMA routeability**: split the 1,024-bit LDS read/write buses (e.g.
   4 × 256-bit or 8 × 128-bit), or map LDS/I$ to Sky130 SRAM macros; rerun
   P&R at 30–40% utilization.
2. **WGP synthesis**: hierarchical synthesis or a non-unrolled/sequential
   WMMA variant, so ABC stays under the time budget.
3. **LVS**: a sequential netgen flow or a cleaned CDL for the `tdm` GDS.
4. **FlashAttention RTL**: define an FP16/BF16 matrix datapath or explicitly
   commit to an FP4 attention numeric scheme.
5. **ROCm mapping layer**: hipBLASLt/rocBLAS call-site mapping to the M1
   kernels; still source/API-level, not binary.

Do not mark the backend as signed off until P&R, LVS and timing are actually
complete.
