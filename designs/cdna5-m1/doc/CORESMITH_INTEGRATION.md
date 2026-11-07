# Driving CDNA5-M1 with CoreSmith

The design is intentionally shaped like a CoreSmith project so the engine can
take it over once a worker LLM is configured.  This page records exactly what
is wired to CoreSmith today and what is deliberately manual.

## What uses CoreSmith

* **PDK and process**: `.pdk/sky130A` from the pinned
  `coresmith/scripts/pdk-version.env` commit, Sky130 HD
  (`sky130_fd_sc_hd`, tt_025C_1v80, 1.8 V).
* **Frontend EDA**: the OSS-CAD-Suite binaries documented by
  `coresmith/SETUP.md` (Yosys 0.70, Verilator 5.055, iverilog).
* **Backend EDA**: OpenROAD, Magic, netgen, KLayout from the CoreSmith
  deployment.  The P&R script is adapted from
  `coresmith/orchestrator/pdk_templates/sky130/pnr_reference.tcl`; the DRC/LVS
  commands follow `drc.tcl` / `lvs_setup.tcl` in the same directory.
* **Preflight**: `make preflight` in the CoreSmith root validates the PDK and
  tools.  `scripts/regress.sh` here validates the design.

## What is manual (and why)

The engine's module builds (`coresmith build module`) are driven by an LLM
worker (`CORESMITH_LLM_PROVIDER`).  This bring-up environment has no provider
credentials, so RTL, testbenches and kernels are authored in this repository
and verified with the same deterministic tools the engine shells out to.  No
`build module` receipt is claimed.

To run the engine flow later:

```bash
export CORESMITH_PROJECT_ROOT=$PWD/designs/cdna5-m1/project
mkdir -p "$CORESMITH_PROJECT_ROOT/.coresmith"
cat > "$CORESMITH_PROJECT_ROOT/.coresmith/env" <<'ENV'
CORESMITH_LLM_PROVIDER=claude
CORESMITH_MODEL=sonnet-5
ENV
coresmith daemon start

# Requirements are registered as structured items, not markdown files:
coresmith prd add "0.1 TFLOP/s MXFP4 at 100 MHz" --id KPI-001 --kind KPI \
  --priority must_have --acceptance "102.4 GFLOP/s -- WMMA block peak" --json
coresmith frd add "Matrix core sustains 102.4 GFLOP/s MXFP4" --id PERF-001 \
  --priority must_have --metric flops --min 102400000000 --unit flop/s \
  --acceptance "measured WMMA throughput" --json

# Architecture artifacts must be valid .coresmith/*_spec.json documents
# (the human-readable PRD/FRD/SAD are not accepted by `register`):
coresmith register block_diagram --file .coresmith/block_diagram.json --json
coresmith register sad --file .coresmith/sad_spec.json --json
coresmith register uarch --block wmma --file spec/uarch_wmma.md --json
coresmith target bind wmma --file targets/wmma.json --json
```

The block diagram / uarch / target files are intentionally not committed: the
engine expects the architect to write them per run, and stale registrations
would be worse than none.  The frozen contracts in `spec/` are the source of
truth for a future registration.

## Turning the manual flow into engine evidence

1. Add `.coresmith/env` with a working worker binding.
2. Register `spec/PRD.md`, `spec/FRD.md`, `spec/SAD.md` (see commands above).
3. Register a block diagram with the blocks `wgp`, `wmma`, `simd32`, `lds`,
   `tdm`, `command_processor`; contracts for `wgp <-> axi_master`.
4. Bind `wmma` to `rtl/wmma.v` (top `wmma`), `simd32` to `rtl/simd32.v`
   (top `simd32`), and `wgp` to `rtl/wgp.v` (top `wgp`).
5. `coresmith build module wmma --seed-rtl rtl/wmma.v --json` etc.  A recorded
   build requires the worker to run the module graph; seeding RTL only skips
   RTL generation, not lint/DV/synth/timing evidence.

Until then, `scripts/regress.sh`, `scripts/synth.sh`, `scripts/run_pnr.sh`
and `scripts/gds_drc_lvs.sh` produce the deterministic evidence recorded in
`doc/VERIFICATION.md` and `doc/BACKEND.md`.
