# CoreSmith designs

| Design | Process / tools | What it is |
|---|---|---|
| [`cdna5-m1`](cdna5-m1/README.md) | Sky130, CoreSmith PDK + Yosys/OpenROAD/Magic/netgen | CDNA5-derived 0.1 TFLOP/s MXFP4 AI accelerator (1 WGP / 1 CU / 2x SIMD32 + 16x16x32 matrix core) |

Each design directory is self-contained:

* `spec/` — PRD/FRD/SAD/ISA/microarchitecture contracts
* `rtl/`, `tb/`, `sw/` — implementation, self-checking tests, assembler + kernels
* `syn/`, `pnr/` — synthesis and physical-design evidence produced with the
  CoreSmith Sky130 deployment
* `scripts/` — one-command regression and flow drivers

The designs use the same pinned PDK and EDA toolchain that CoreSmith itself
uses (`coresmith/scripts/pdk-version.env`, `.pdk/sky130A`, Yosys/OpenROAD/
Magic/netgen/KLayout).  They are not part of the CoreSmith engine; they are
reference designs that exercise it.
