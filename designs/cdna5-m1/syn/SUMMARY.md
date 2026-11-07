# Sky130 synthesis results

Tool: Yosys 0.70+344, Liberty `sky130_fd_sc_hd__tt_025C_1v80.lib`,
PDK pin `c6d73a35f524070e85faff4a6a9eef49553ebc2b`.

| Block | Cells | Area (`stat -liberty`) | Notes |
|---|---:|---:|---|
| `wmma` | 126,245 | 1,218,412.304 um^2 (1.218 mm^2) | 512 FP4 MAC/cycle; 12,288 `edfxtp` + 50 `dfxtp` |
| `tdm` | 4,476 | 36,215.984 um^2 (0.036 mm^2) | 1,093 DFF |
| `sfu` | 1,728 | 12,714.694 um^2 (0.013 mm^2) | exp2/rcp, 145 `dfxtp`, 4-cycle latency; standalone block, not yet instantiated in WGP |
| `softmax_engine` | 5,622 | 39,034.938 um^2 (0.039 mm^2) | row-wise stable softmax over LDS, 304 `dfxtp`; standalone AI block, integration point documented |
| `axi_lite_slave` | 397 | 3,783.629 um^2 | smoke block |
| `lds` | not completed | - | 4 KB register array expands to ~3.3 M generic cells before ABC; must use SRAM macros |
| `simd32` | not completed | - | ABC did not converge (32 per-lane write-enabled VGPR words); needs a per-lane split or macro RF |

Large netlists/logs are intentionally ignored by git (see `.gitignore`); the
commands in `scripts/synth.sh` reproduce them.  Raw logs remain in the
working tree under `syn/<block>/`.
