# OpenROAD place-and-route results

Tool: OpenROAD (source build, 2026-11-07 HEAD, aarch64), OpenSTA 3.1.0,
Sky130 `sky130_fd_sc_hd` tt_025C_1v80, 100 MHz (10 ns).

## `tdm`

| Metric | Value |
|---|---|
| Cells | 4,476 |
| Die area | 192,114 um^2 (0.192 mm^2) |
| Setup WNS / TNS | 0.00 ns / 0.00 ns |
| Hold WNS | met (see `tdm/timing_hold.rpt`) |
| Total power | 10.1 mW |
| Detailed-route DRC | 0 (`tdm/route_drc.rpt` empty) |
| GDS | `tdm/tdm_mapped.gds` (KLayout, 110 MB) |
| KLayout DRC (sky130A_mr.drc) | **0 violations** (`tdm/klayout_drc.txt`) |

Magic DRC / netgen LVS on the GDS remain open: Magic's flatten path reads
1.25 M instance references, and KLayout LVS rejects the Yosys CDL pin
format.  The raw GDS/DEF/netlists are ignored by git; the reports are kept.

## `wmma`

126,245 cells / 1.218 mm2.  P&R on the 15 GB / 8-core host at 45% and 30%
utilization completed placement, CTS and global route, but flat detailed
routing did not converge (126,726 violations at 45%; 255,357 -> 355,997 at
30%).  The 2,096-pin block with 1,024-bit LDS read/write buses is the
congestion source; split the buses or map them to SRAM macros, or use a
hierarchical partition, before retrying.
