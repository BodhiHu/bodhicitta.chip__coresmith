# CDNA5-M1 backend: Sky130 synthesis, P&R, DRC/LVS

Status: **flow skeleton + partial measurements**. Scripts and constraints
exist; `tdm`, `axi_lite_slave` and the full `wmma` matrix core are synthesized
and measured (Sky130 HD). The `wmma` netlist is 126,245 cells / 1.218 mm²
after the C-store mux fix and the shared-adder rewrite; the earlier OOM is
recorded in §4.2 for provenance. The `lds` register array expands to ~3.3M
cells and needs SRAM macros, so it is not a P&R target. There are **no P&R,
DRC, LVS, timing or power signoff results yet**. Unmeasured numbers are marked
`TODO(measure)`; `spec/UARCH.md` budgets are labelled `PLANNING` and are not
results.

Last updated: 2026-11-07, design root
`/workspace/菩提树/coresmith/designs/cdna5-m1`.

## 1. Toolchain

| Tool | Version / path | Status |
|---|---|---|
| Yosys | 0.70+344 (sha1 2f2307ad6), `/opt/eda/oss-cad-suite/bin/yosys` | available |
| Icarus Verilog | 14.0 (devel) `s20260301-831-g1cb990b6f-dirty` | available |
| OpenROAD | source `/opt/openroad-src`; Bazel arm64 build (patched `lef_keywords.cpp` + `def_keywords.cpp` `char fc` -> `int fc` for aarch64) | installed at `/opt/install/OpenROAD/bin/openroad` |
| OpenSTA | source `src/sta`, CMake, CUDD 3.0 | `/opt/openroad-src/src/sta/build/sta` (3.1.0) |
| Magic | built from source (8.3 revision 695) | `/opt/magic-install/bin/magic` (>= 8.3.411) |
| OpenROAD wrapper | `coresmith/scripts/openroad-nix.sh` (nix) | needs Nix, absent here |
| Magic | 8.3 rev 105 (`magic -dnull -noconsole`) | available |
| netgen | 1.5.133 | available |
| KLayout | 0.28.16 | available |
| PDK | `coresmith/.pdk/sky130A`, pin `c6d73a35f524070e85faff4a6a9eef49553ebc2b` | available |

PDK pin comes from `coresmith/scripts/pdk-version.env` (`SKY130_PDK_COMMIT`).
The flow scripts default `PDK_ROOT` to `coresmith/.pdk` and accept an override.

## 2. PDK collateral used

```
PDK_ROOT=/workspace/菩提树/coresmith/.pdk
LIB=$PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
TECH_LEF=$PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd/techlef/sky130_fd_sc_hd__nom.tlef
CELL_LEF=$PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd/lef/sky130_fd_sc_hd.lef
CELL_GDS=$PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd/gds/sky130_fd_sc_hd.gds
MAGIC_RC=$PDK_ROOT/sky130A/libs.tech/magic/sky130A.magicrc
KLAYOUT_DRC=$PDK_ROOT/sky130A/libs.tech/klayout/drc/sky130A.lydrc
KLAYOUT_LVS=$PDK_ROOT/sky130A/libs.tech/klayout/lvs/sky130.lvs
Corner: sky130_fd_sc_hd, tt_025C_1v80, 1.8 V, 100 MHz (10 ns) target
```

`ss`/`ff` corners, IR-drop and OCV derates are `TODO(measure)`.

## 3. Flow drivers

| File | Purpose |
|---|---|
| `scripts/synth.sh <wmma\|simd32\|wgp\|top>` | write `syn/<b>/synth.ys`, run Yosys, emit netlist/JSON/log |
| `scripts/pnr.tcl` | OpenROAD floorplan/PDN/place/CTS/route/reports |
| `scripts/run_pnr.sh <wmma\|simd32>` | set env, call OpenROAD with `scripts/pnr.tcl` |
| `scripts/gds_drc_lvs.sh <block>` | Magic DEF->GDS/DRC/extract, netgen LVS |
| `constraints/{wmma,simd32}.sdc` | 100 MHz SDC |
| `scripts/regress.sh` | iverilog bring-up regression (`doc/VERIFICATION.md`) |
| `syn/<b>/`, `pnr/<b>/` | generated evidence |

`synth.sh` supports `wmma`, `simd32`, `wgp`, `top`; `lds` and `tdm` were run
with the same Yosys line directly (adding them is `TODO(flow)`).

## 4. Synthesis

### 4.1 Command and script

```bash
cd /workspace/菩提树/coresmith/designs/cdna5-m1
export PATH=/opt/eda/oss-cad-suite/bin:$PATH
scripts/synth.sh wmma            # -> syn/wmma/synth.ys, syn/wmma/yosys.log
```

`syn/<block>/synth.ys` executes: `read_verilog -Irtl <srcs>; hierarchy -top
<top>; synth -top <top> -flatten; dfflibmap -liberty $LIB; abc -liberty $LIB;
opt_clean; stat; write_verilog -noattr syn/<b>/<top>_netlist.v;
write_json syn/<b>/<top>_netlist.json`.

For a block not in the script:

```bash
LIB=$PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
yosys -p "read_verilog -Irtl rtl/tdm.v; hierarchy -top tdm; synth -top tdm -flatten; \
  dfflibmap -liberty $LIB; abc -liberty $LIB; opt_clean; stat -liberty $LIB; \
  write_verilog -noattr syn/tdm/tdm_netlist.v" | tee syn/tdm/yosys.log
```

### 4.2 Measured results in this tree

| Block | Log | Cells | DFF | Area (`stat -liberty`) | Status |
|---|---|---|---|---|---|
| `tdm` | `syn/tdm/yosys.log` | 4476 | 1093 | **36,215.984 um^2** | complete, netlist written |
| `axi_lite_slave` smoke | manual | 397 | 121 | 3,783.6288 um^2 | complete |
| `lds` | `syn/lds/yosys.log` | 3,302,712 pre-ABC | - | `TODO(measure)` | **incomplete**, log stops at ABC |
| `wmma` (pre-fix) | `syn/wmma_yosys.log` | `TODO(measure)` | - | `TODO(measure)` | **killed at elaboration**, exit 137 |
| `wmma` (post-fix) | `syn/wmma/yosys.log` | **126,245** | 12,288 `edfxtp` + 50 `dfxtp` | **1,218,412.3 um^2 (1.218 mm^2)** | complete, netlist `syn/wmma/wmma_netlist.v` |
| `simd32` | `syn/simd32/yosys.log` | `TODO(measure)` | - | `TODO(measure)` | ABC did not finish (VGRP memory write-enable expansion); needs a per-lane synthesis split |
| `wgp` | - | `TODO(measure)` | - | `TODO(measure)` | blocked on wmma/lds |
| top | - | `TODO(measure)` | - | `TODO(measure)` | blocked on blocks |

The area column is from `yosys -p "read_verilog syn/tdm/tdm_netlist.v;
stat -liberty $LIB"` on the committed netlist. The `tdm` run used 43.62 MB
peak and 1.31 s. The pre-fix `wmma` run was OOM-killed after the frontend converted the
register arrays; even `read_verilog; hierarchy; stat` died with exit 137 on
the 7.8 GB host, and `syn/wmma_yosys.log` stops before `proc`/`stat`, so no
pre-fix cell count exists. At 10:49 the C-store mux was changed from a 256:1
to an 8:1 slice (`rtl/wmma.v:126`) and a fresh run was started; at the time
of writing it is still running (RSS ~5.6 GB, log at the frontend warnings), so the
result is `TODO(measure)`.

### 4.3 Why `wmma`/`lds` blow up, and required fixes

* (Fixed 10:49) the old `c_word[0..31]` mux over `acc[0..255]` with `st_cnt`
  was a 32 x 32-bit **256:1 mux** plus a 1024-bit concatenation; this drove
  the pre-fix OOM. The current RTL slices `acc[{1'b0,st_cnt[2:0]}*32 + ci]`
  (`rtl/wmma.v:126`), an 8:1 mux.
* (Open) `rtl/wmma.v:91-93` keeps `a_mat` (512), `b_mat` (512) and
  `acc` (256 x 32b) as flop arrays.
* `rtl/lds.v` is a 32x32 x 32-bit reg array with two 32-lane combinational
  read ports; Yosys sees 3.3M cells before ABC.

`TODO(rtl)` in order: (1) confirm the new 8:1 C slice synthesizes; (2) infer A/B memories; (3) if needed,
split the dot into 4 x 8x16 sub-cores; (4) replace the LDS reg array with a
4 KB SRAM macro or banked memories (3-port requirement means 4 x 1 KB 1RW
banks plus external arbitration, or a custom 2W/3R macro). The LDS is the
largest backend risk after WMMA.

### 4.4 PLANNING budgets (not measured)

From `spec/UARCH.md:219-228`: 2 x `simd32` ~180 k cells, LDS ~30 k flops,
WMMA ~90 k, TDM/I$/CP ~25 k, AXI+CSR ~15 k, top **~340 k**. Targets only;
replace with `TODO(measure)` after the RTL fixes.

## 5. 100 MHz SDC

`constraints/wmma.sdc` (same shape as `simd32.sdc`):

```tcl
create_clock -name clk -period 10.0 [get_ports clk]
set_clock_uncertainty -setup 0.50 [get_clocks clk]
set_clock_uncertainty -hold  0.15 [get_clocks clk]
set_input_delay  -clock clk 2.0 [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]
set_output_delay -clock clk 2.0 [all_outputs]
set_max_fanout 16 [current_design]
set_max_transition 1.5 [current_design]
```

The 0.50 ns setup uncertainty is a pre-CTS placeholder to revisit after CTS
(`TODO(measure)`). `rst_n` is synchronous and excluded; there is no async
reset and no CDC. Add `set_driving_cell`/`set_load` before top-level signoff
(`TODO(flow)`). STA must run on the routed netlist + SPEF; `scripts/pnr.tcl`
writes `timing_setup.rpt`, `timing_hold.rpt`, `timing_wns.rpt`,
`timing_tns.rpt`.

## 6. Block P&R plan

Order: `tdm` flow smoke test (netlist exists) -> `wmma` (90 k datapath) ->
`simd32` (~180 k) -> `wgp`/top. `run_pnr.sh` supports only `wmma`/`simd32`;
adding `tdm` is `TODO(flow)` so the flow can be validated before WMMA lands.

```bash
cd /workspace/菩提树/coresmith/designs/cdna5-m1
export PDK_ROOT=/workspace/菩提树/coresmith/.pdk
export OPENROAD_BIN=/path/to/openroad      # TODO(measure) until installed
scripts/run_pnr.sh wmma                    # syn/wmma/wmma_netlist.v
scripts/run_pnr.sh simd32
```

OpenROAD steps in `scripts/pnr.tcl`:

| Step | Settings |
|---|---|
| Read | tech LEF, cell LEF, tt_025C_1v80 lib, netlist, SDC |
| Floorplan | util 0.35 (env `UTILIZATION`), aspect 1.0, core space 2, `unithd` |
| Tracks/pins | li1/met1-met5 pitches; `place_pins` met3 horizontal / met2 vertical |
| Taps/PDN | `tapvpwrvgnd_1` distance 14; met1 followpins + met4 straps (pitch 27.14) |
| Place | `global_placement -density 0.60`, detailed, `repair_design`, `set_wire_rc` |
| CTS | clkbuf 4/8/16, root 8, sink clustering, propagated clock, `repair_clock_nets` |
| Route | signal met1-met4, clock met3-met4, global 50 iters, detailed, SPEF |
| Outputs | `_routed.def`, `_pnr.v`, `_pwr.v`, setup/hold/wns/tns/power reports |

First-run risks: no `wmma` netlist; LDS is not a macro; top AXI pin assignment
is unconstrained; 0.35 utilization may be too aggressive for a
register-dominated block at 100 MHz (`TODO(measure)`).

### 6.1 Floorplan/area planning estimate

Using the measured `tdm` area per cell (`36215.984 / 4476 = 8.09 um^2/cell`)
as a cross-check only:

| Block | PLANNING cells | Estimated cell area | At 35% util | Status |
|---|---|---|---|---|
| tdm | 4.5 k | 36 k um^2 | ~0.10 mm^2 | measured area; floorplan `TODO` |
| wmma | 90 k | ~728 k um^2 | ~2.1 mm^2 | ESTIMATE, `TODO(measure)` |
| simd32 | 180 k | ~1.46 mm^2 | ~4.2 mm^2 | ESTIMATE, `TODO(measure)` |
| top | 340 k | ~2.75 mm^2 | ~7.9 mm^2 | ESTIMATE, `TODO(measure)` |

Datapath logic is denser than `tdm` control logic, so treat these as +/-50%
and replace with `report_design_area` after the first run. No die area is
measured yet.

## 7. DRC / LVS

Canonical path (DEF -> GDS via Magic, DRC via Magic, extraction + netgen LVS):

```bash
cd /workspace/菩提树/coresmith/designs/cdna5-m1
export PDK_ROOT=/workspace/菩提树/coresmith/.pdk
scripts/gds_drc_lvs.sh wmma
```

The script (1) reads tech LEF/cell LEF/cell GDS + `pnr/wmma/wmma_routed.def`
and writes `wmma.gds`; (2) flattens, `drc catchup`, `drc listall count total`
-> `magic_drc.rpt` (signoff needs 0); (3) `extract all; ext2spice lvs` ->
`wmma.spice`; (4) runs
`netgen -batch lvs "pnr/wmma/wmma.spice wmma" "syn/wmma/wmma_netlist.v wmma" pnr/wmma/lvs_setup.tcl pnr/wmma/lvs.rpt`
with fill/tap/decap ignored and power pins removed. Signoff needs "Circuits
match uniquely".

KLayout alternatives (same run sets):

```bash
klayout -b -rd input=pnr/wmma/wmma.gds -rd report=pnr/wmma/klayout_drc.txt \
  -r $PDK_ROOT/sky130A/libs.tech/klayout/drc/sky130A.lydrc
klayout -b -rd input=pnr/wmma/wmma.gds -rd schematic=syn/wmma/wmma_netlist.v \
  -rd top_cell=wmma -rd report=pnr/wmma/klayout_lvs.txt \
  -r $PDK_ROOT/sky130A/libs.tech/klayout/lvs/sky130.lvs
```

KLayout LVS of post-route GDS needs a matching extracted schematic/CDL;
Magic + netgen is primary because `gds_drc_lvs.sh` already wires it end to
end. **No DRC/LVS has run** (no routed DEF). `TODO(measure)`: DRC count per
block, LVS match, antenna and density/fill reports.

## 8. Area and power estimation method

**Area.** Report two independent numbers: (1) pre-P&R Yosys
`stat -liberty $LIB`, a cell sum excluding wiring/fillers/straps; (2)
post-P&R OpenROAD `report_design_area` plus the DEF die area from
`initialize_floorplan`. Cross-check with `cell count x 8.09 um^2/cell` from
`tdm` (§6.1), clearly labelled estimate.

**Power.** OpenSTA inside OpenROAD on the routed netlist + SPEF at
`tt_025C_1v80`, 100 MHz, activity from a VCD:

```tcl
# after detailed_route + estimate_parasitics -global_routing
read_power_activities -scope tb_top/dut -vcd /tmp/tb_top.vcd
report_power -corner tt_025C_1v80 > pnr/wmma/power.rpt
```

Activity from the two bring-up kernels is short and not representative, so
that number is a lower bound; a 10+ kernel launch suite is `TODO(measure)`.
Power includes internal + switching + leakage, and CTS clock power. IR-drop /
EM are `TODO(measure)`.

**Timing.** `report_checks -path_delay max/min`, `report_wns`, `report_tns`
after SPEF; signoff needs WNS >= 0 and hold >= 0 at 10 ns with the final SDC.
`TODO(measure)`.

## 9. Signoff checklist and TODO placeholders

| Item | Target | Current |
|---|---|---|
| Yosys `wmma` completion | no OOM | pre-fix **exit 137**; post-fix run in flight |
| Yosys `lds` completion | < 30 k cells or 1 macro | **3.3M cells**, `TODO(rtl)` |
| `wmma` / `simd32` area | `TODO(measure)` | not measured |
| Top area / die | `TODO(measure)` | not measured |
| 100 MHz setup/hold WNS | >= 0 ns | `TODO(measure)` |
| DRC (Magic/KLayout) | 0 violations | `TODO(measure)` |
| LVS (netgen/KLayout) | match | `TODO(measure)` |
| Power (tt, 100 MHz, VCD) | `TODO(measure)` | not measured |
| Antenna/density/fill | clean | `TODO(measure)` |
| `ss`/`ff` corners | clean | `TODO(measure)` |
| OpenROAD install | pinned, on PATH | **FAILED/interrupted** (bazel), `TODO(measure)` |
| LDS macro | 4 KB, 3-port or banked | not selected |

First complete run once RTL fixes and OpenROAD land:

```bash
cd /workspace/菩提树/coresmith/designs/cdna5-m1
export PATH=/opt/eda/oss-cad-suite/bin:$PATH
export PDK_ROOT=/workspace/菩提树/coresmith/.pdk
export OPENROAD_BIN=/path/to/openroad
scripts/synth.sh wmma && scripts/synth.sh simd32
scripts/run_pnr.sh wmma && scripts/run_pnr.sh simd32
scripts/gds_drc_lvs.sh wmma && scripts/gds_drc_lvs.sh simd32
```

Do not report a PPA number until the log/report exists under `syn/` or
`pnr/` and is cited here.


## 8. Backend run log (2026-11-07)

CoreSmith preflight is green with the local deployment:

```text
$ source designs/cdna5-m1/scripts/env.sh
$ cd coresmith && make preflight
{"ok": true, "errors": [], "warnings": ["CORESMITH_ALLOW_NO_OPENRAM=1 ..."]}
```

OpenROAD was built from `The-OpenROAD-Project/OpenROAD` HEAD (2026-11-07)
with Bazel on aarch64 after two lexer patches (`char fc` vs `EOF`).  OpenSTA
3.1.0 was built from `src/sta` with CUDD 3.0.

### 8.1 Pre-layout STA (OpenSTA 3.1.0, tt_025C_1v80, 100 MHz)

| Block | WNS | Note |
|---|---|---|
| `tdm` | -17.97 ns | `syn/tdm` netlist, no buffer insertion |
| `wmma` | -199.43 ns | critical path is a single inverter driving **8,196** `edfxtp` enables; fanout repair is required before this number is meaningful |

These are **pre-layout, unrepaired** numbers.  A 8,196-fanout enable net and a
1024-bit mux do not represent a 100 MHz signoff; `repair_design` / CTS in
`scripts/pnr.tcl` insert the buffer trees.  Do not quote the raw WNS as a
timing result.

### 8.2 P&R

**`tdm` P&R is complete** (OpenROAD, 2026-11-07):

| Metric | Value |
|---|---|
| Cells | 4,476 |
| Die area | 192,114 um^2 (utilization 2% due to the auto-floorplan) |
| Setup WNS / TNS @100 MHz | **0.00 / 0.00 ns** |
| Total power (tt, 100 MHz) | **10.1 mW** |
| Detailed-route DRC | 0 (`route_drc.rpt` empty) |
| GDS | `pnr/tdm/tdm_mapped.gds` (110 MB, KLayout DEF+LEF+cell GDS; valid GDSII, top cell `tdm`) |

The 125k-cell `wmma` place-and-route is being re-run on the upgraded
15 GB / 8-core host (`pnr/wmma/pnr.log`).

**GDS/DRC/LVS status.**  The DEF was converted to a valid 110 MB GDS by
KLayout (`pnr/tdm/tdm_mapped.gds`).  KLayout's Sky130 DRC deck
(`sky130A_mr.drc`) ran in 24 s and reported **0 DRC violations**
(`pnr/tdm/klayout_drc.txt`); the OpenROAD detailed-route DRC report is also
empty.  LVS is still open: KLayout LVS rejects the Yosys CDL's missing/
unconnected cell pins (even after the power-pin patcher), and Magic's SPICE
extraction of the 1.25 M-reference flat GDS is very slow.  Netgen LVS is a
follow-up; it needs a cleaner CDL or a hierarchical extraction.

`scripts/gds_drc_lvs.sh <block>` is the ready handoff:

```bash
./scripts/run_pnr.sh tdm
./scripts/gds_drc_lvs.sh tdm
# pnr/tdm/tdm.gds, magic_drc.rpt, lvs.rpt
```
