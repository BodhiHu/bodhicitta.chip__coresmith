#!/usr/bin/env bash
# Copyright (c) 2026 CDNA5-M1 project.
# SPDX-License-Identifier: MIT
#
# gds_drc_lvs.sh <block> -- DEF -> GDS (Magic), DRC (Magic), LVS (netgen).
# Requires pnr/<block>/<block>_routed.def from scripts/run_pnr.sh.
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
cd "$HERE"
BLOCK=${1:-wmma}
MAGIC_BIN=${MAGIC_BIN:-magic}
NETGEN_BIN=${NETGEN_BIN:-netgen}
CORESMITH=$(cd "$HERE/../.." && pwd)
PDK=${PDK_ROOT:-$CORESMITH/.pdk}
export PDK_ROOT=$PDK
TECH_LEF=$PDK/sky130A/libs.ref/sky130_fd_sc_hd/techlef/sky130_fd_sc_hd__nom.tlef
CELL_LEF=$PDK/sky130A/libs.ref/sky130_fd_sc_hd/lef/sky130_fd_sc_hd.lef
CELL_GDS=$PDK/sky130A/libs.ref/sky130_fd_sc_hd/gds/sky130_fd_sc_hd.gds
MAGIC_RC=$PDK/sky130A/libs.tech/magic/sky130A.magicrc
OUT=pnr/$BLOCK
DEF=$OUT/${BLOCK}_routed.def
[ -f "$DEF" ] || { echo "missing $DEF; run scripts/run_pnr.sh $BLOCK" >&2; exit 1; }

# ---- DEF -> GDS
cat > "$OUT/def2gds.tcl" <<TCL
lef read {$TECH_LEF}
lef read {$CELL_LEF}
gds read {$CELL_GDS}
def read {$PWD/$DEF}
load $BLOCK
select top cell
gds write {$PWD/$OUT/$BLOCK.gds}
puts "GDS written"
quit -noprompt
TCL
"$MAGIC_BIN" -dnull -noconsole -rcfile "$MAGIC_RC" "$OUT/def2gds.tcl" 2>&1 | tee "$OUT/magic_gds.log"

# ---- DRC
cat > "$OUT/drc.tcl" <<TCL
lef read {$TECH_LEF}
lef read {$CELL_LEF}
gds read {$CELL_GDS}
def read {$PWD/$DEF}
load $BLOCK
flatten ${BLOCK}_flat
load ${BLOCK}_flat
select top cell
drc catchup
set n [drc listall count total]
set rpt [open {$PWD/$OUT/magic_drc.rpt} w]
puts \$rpt "Design: $BLOCK"
puts \$rpt "DRC count: \$n"
puts \$rpt [drc listall why]
close \$rpt
puts "DRC violations: \$n"
quit -noprompt
TCL
"$MAGIC_BIN" -dnull -noconsole -rcfile "$MAGIC_RC" "$OUT/drc.tcl" 2>&1 | tee "$OUT/magic_drc.log"

# ---- LVS: Magic extraction
cat > "$OUT/extract.tcl" <<TCL
lef read {$TECH_LEF}
lef read {$CELL_LEF}
gds read {$CELL_GDS}
def read {$PWD/$DEF}
load $BLOCK
select top cell
extract all
ext2spice lvs
ext2spice -o {$PWD/$OUT/$BLOCK.spice}
puts "SPICE written"
quit -noprompt
TCL
"$MAGIC_BIN" -dnull -noconsole -rcfile "$MAGIC_RC" "$OUT/extract.tcl" 2>&1 | tee "$OUT/magic_extract.log"

# ---- LVS: netgen
cat > "$OUT/lvs_setup.tcl" <<'TCL'
permute default
property default
property parallel none
ignore class sky130_fd_sc_hd__fill_*
ignore class sky130_fd_sc_hd__tapvpwrvgnd_*
ignore class sky130_fd_sc_hd__decap_*
permute pin VPWR
permute pin VGND
permute pin VPB
permute pin VNB
property VPWR delete
property VGND delete
property VPB delete
property VNB delete
TCL
"$NETGEN_BIN" -batch lvs "$OUT/$BLOCK.spice $BLOCK" "syn/$BLOCK/${BLOCK}_netlist.v $BLOCK" "$OUT/lvs_setup.tcl" "$OUT/lvs.rpt" 2>&1 | tee "$OUT/netgen_lvs.log" || true
echo "=== results ==="
[ -f "$OUT/magic_drc.rpt" ] && head -3 "$OUT/magic_drc.rpt"
[ -f "$OUT/lvs.rpt" ] && tail -5 "$OUT/lvs.rpt"
