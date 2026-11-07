# ROCm / HIP / HSA compatibility shim

This directory provides **source/API-level** CDNA5 ROCm compatibility for the
M1 bring-up.  It is deliberately not a ROCm binary runtime:

| Layer | Status |
|---|---|
| HIP runtime API subset (`hipMalloc`, `hipMemcpy`, `hipMemset`, streams, events, device props, `hipLaunchKernelGGL`) | supported by the shim |
| HIP C++ source (`__global__`, `threadIdx`, ...) | compiles with g++; kernels run serially on the host |
| HSA runtime API subset (agents, signals, queues, memory, dispatch) | supported by the shim |
| gfx1250/ROCm binary compatibility, ROCr ABI, hipBLASLt/rocBLAS/MIOpen | **not supported** |
| M1 device operators (FP4 GEMM, Softmax, FlashAttention) | callable from HIP kernels via `m1::` |

Examples:

```bash
cmake -S rocm -B rocm/build && cmake --build rocm/build -j4
for x in hip_saxpy hip_gemm hip_softmax hip_flash_attention hsa_demo; do ./rocm/build/$x; done
```

Measured output:

```text
PASS hip_saxpy (n=1024, 0 errors)
PASS hip_gemm_m1 (64x64x64 FP4, max_err=0)
PASS hip_softmax_m1 (8x128, row-sum err=4.5e-04)
PASS hip_flash_attention_m1 (seq=32 dim=16, err=0.0)
PASS hsa_demo (agent/queue/signal/dispatch, 0 errors)
```

`hip_gemm/softmax/flash_attention` are HIP host API + M1 device kernels;
`hip_saxpy` is a standard HIP kernel on the host backend; `hsa_demo` exercises
the HSA shim.  See `../spec/ROCM_COMPAT.md` for the compatibility matrix and
limitations.
