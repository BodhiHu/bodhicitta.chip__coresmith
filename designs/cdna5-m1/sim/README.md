# M1 functional / cycle model

`m1_sim.hpp/.cpp` models the CDNA5-M1 AI slice at operator granularity:

* 4 KB LDS (32 banks x 32 rows), 1-D TDM (`tdm_copy`);
* 16x16x32 MXFP4 WMMA with the exact E2M1 decode and int32 accumulate
  (16 cycles/op, 512 MAC/cycle);
* a reconfigurable FP16 matrix tile used by the Softmax/FlashAttention
  datapath (128 MAC/cycle, `M*N*K/128 + 8` cycles);
* a serialized SFU row engine for `exp2` / reciprocal;
* stable row-wise Softmax.

Operators (`run_operators.cpp`):

| Operator | Shape | Check | Result |
|---|---|---|---|
| GEMM MXFP4 | 64x64x64 | exact int32 vs CPU FP4 reference | PASS, 512 cycles, **102.4 GFLOP/s** @100 MHz |
| Softmax FP16 | 8 x 128 | vs double reference, row sums | PASS, max err 1.7e-3 |
| FlashAttention FP16 | seq=32, dim=16, causal | vs CPU float reference | PASS, max err 1.0e-3 |

Build/run:

```bash
cmake -S sim -B sim/build && cmake --build sim/build -j4
./sim/build/run_operators
```

The model is a **functional/cycle model**, not gate-level RTL.  The matrix
core math matches `rtl/wmma.v` and the RTL full-chip `tb_wmma_top` test; the
FP16 tile and SFU are the AI datapath target, with the synthesizable SFU in
`rtl/sfu.v`.
