# CDNA5-M1 — CDNA5 ROCm compatibility statement

| Field | Value |
|---|---|
| Document | ROCm compatibility matrix and shim specification, revision 1.1 (2026-11-07) |
| Applies to | `rocm/` (shim, built), `sim/` (M1 model) |
| Related | `spec/ISA.md`, `spec/UARCH.md`, `spec/SAD.md`, `spec/AI_SCOPE.md`, `doc/OPERATORS.md`, `rocm/README.md` |
| Verdict | HIP **source/API** compatibility via a host-execution shim (supported, 5 examples pass); the **HSA runtime API subset** is supported; **gfx1250 binaries are not supported**; ROCm libraries are **not native** — their operators map onto M1 kernels. |

## 0. Status and evidence

**What exists.** `rocm/` contains a working source-level shim
(`include/hip/hip_runtime.h`, `include/hsa/hsa.h`, `src/hip_shim.cpp`,
`src/hsa_shim.cpp`, `CMakeLists.txt`) and five examples. It builds, and on
2026-11-07 the built binaries were re-run with these results:

```text
PASS hip_saxpy            (n=1024, 0 errors)          -- plain HIP kernel, host backend
PASS hip_gemm_m1          (64x64x64 FP4, max_err=0)   -- HIP API + m1::gemm_fp4
PASS hip_softmax_m1       (8x128, row-sum err=4.5e-04)
PASS hip_flash_attention_m1 (seq=32 dim=16, err=0.0)
PASS hsa_demo             (agent/queue/signal/dispatch, 0 errors)
```

**What it is not.** This is a **host-execution** shim, not a device runtime:
`hipLaunchKernelGGL` expands to a host call that runs the kernel body once
(with `threadIdx = blockIdx = 0`), and the M1 operators execute on the C++
functional/cycle model in `sim/`. There is **no device dispatch, no code-object
loader, no AQL ring doorbell, and no gfx1250 decoder**. No AMD ROCm component
has been used, and no ROCm library has been linked.

**Consequence for reading this document.** Rows marked **S** are implemented
and exercised by the examples above; **P** rows are implemented with limits
stated in the row; **N** rows do not exist. "Supported" never means binary
compatibility with ROCm.

## 1. Compatibility levels

| Level | Name | Exact claim |
|---|---|---|
| **L0** | HIP C++ source / API | Host code written against the shim headers **compiles and runs**; kernels compile only inside the M1 subset (§2.1, §6) and execute on the host/model, not on the RTL |
| **L1** | HSA runtime API | A subset of `hsa.h` — agents, queues, signals, memory, `hsa_ext_submit` — is implemented over the model's launch path |
| **L2** | Code object / ABI / ISA binary | **None.** No AMDGPU ELF, no HSACO, no gfx1250 machine code, no msgpack descriptor, no `.m1co` container. Kernels are linked C++ functions |
| **L3** | ROCm libraries / frameworks | **No native libraries.** hipBLASLt/rocBLAS/MIOpen call sites can only be served by an operator-mapping layer, which is not implemented |

L0 does **not** imply L2: source compatibility is a compile-time property of the
shim headers; binary compatibility is a property of the instruction set, and the
M1 ISA is a custom 32-bit subset explicitly **not** compatible with any gfx
encoding (`spec/ISA.md`).

## 2. Compatibility matrix

Legend: **S** implemented and exercised · **P** implemented with limits ·
**N** not implemented · **X** rejected at load. S/P never implies binary
compatibility with AMD ROCm.

### 2.1 HIP (L0)

| Feature | CDNA5 ROCm (gfx1250) | CDNA5-M1 | Status |
|---|---|---|---|
| HIP C++ host source (`#include <hip/hip_runtime.h>`) | Yes | Shim header subset; links against `librocm_shim` | S |
| `kernel<<<grid, block, shmem, stream>>>(...)` | Device dispatch | Macro: `threadIdx/blockIdx` globals set, kernel body called **once on the host**; kernels loop internally | P |
| `threadIdx`, `blockIdx`, `blockDim`, `gridDim` | Hardware | `dim3` globals; only `blockDim.x`/`gridDim.x` are meaningful and are not enforced | P |
| Kernel source written to the M1 subset | Yes | Compiles with the host compiler (`g++`) | S |
| Unmodified CUDA/HIP kernels (shuffles, textures, atomics, `double`) | Yes | Not supported; `__shfl_*`/`__ballot` do not exist in the shim | N |
| `hipcc` / Clang `amdgcn` device backend | Yes | No `amdgcn` target; the shim is a host library | N |
| `warpSize` / `blockDim.x` | 64 or 32 / up to 1024 | **32**; not enforced at runtime (nothing is scheduled) | P |
| `gridDim.x` | large | ≤ 8 workgroups at RTL level; ignored by the shim | P |
| `__shared__` / dynamic LDS | 64 KB / 320 KB | ≤ 4 KB at RTL level; the model owns a 4 KB LDS (`m1::kLdsWords = 1024`) | P |
| `__syncthreads()` | Yes | No-op (one wave per workgroup; `S_BARRIER` is a NOP) | P |
| `__shfl_*`, `__ballot`, warp reductions | Yes | Absent from the shim and the ISA; reduce through LDS | N |
| Atomics, textures, surfaces, images | Yes | No atomic or image hardware (graphics path removed, `AI_SCOPE.md` §2) | N |
| `printf`, device `malloc`/`new`, exceptions | Yes / limited | Host `printf` only; no device heap | P |
| Dynamic parallelism, cooperative groups, HIP Graphs | Yes | Not supported | N |

### 2.2 HIP runtime API (host side)

| API group | M1 | Notes |
|---|---|---|
| `hipInit`, `hipGetDevice`, `hipSetDevice`, `hipGetDeviceCount` | S | One device, id 0 |
| `hipGetDeviceProperties` | S | 1 CU, 2 SIMD32, wave32, 4 MiB `totalGlobalMem`, 4 KB LDS, 1 KB I$, 100 MHz, `warpSize=32` |
| `hipMalloc`, `hipFree`, `hipHostMalloc` | S | Plain `malloc`/`free`: device memory **is** host memory; no arena, no offsets, no pinning |
| `hipMemcpy` (H2D/D2H/D2D), `hipMemset` | S | `memcpy`/`memset`; the `hipMemcpyKind` argument is ignored |
| `hipDeviceSynchronize` | S | Trivial: kernel bodies run synchronously on the host |
| `hipStreamCreate/Destroy`, `hipEventCreate/Record/Synchronize/ElapsedTime` | S/P | Handles exist; timings are host-side, not hardware timestamps |
| `hipGetErrorString` | S | Error strings |
| `hipModuleLoad`, `hipModuleGetFunction`, `hipModuleLaunchKernel` | N | No code-object loader; kernels are linked C++ functions |
| `hipMemcpyAsync`, `hipMemcpy2D/3D`, `hipMallocPitch`, `hipMallocManaged` | N | 1-D synchronous copies only; no MMU, no migration |
| `hipIpcGetMemHandle`, peer access, `hiprtc*` | N | Single device; no runtime compiler |

### 2.3 HSA runtime API (L1)

| API | M1 | Notes |
|---|---|---|
| `hsa_init`, `hsa_shut_down` | S | Reference-counted |
| `hsa_system_get_info`, `hsa_agent_get_info`, `hsa_iterate_agents` | S | One GPU agent reported as "CDNA5-M1", plus one CPU agent |
| `hsa_queue_create`, `hsa_queue_destroy` | S | Handle only: no ring buffer, no read/write indices, no doorbell; the handle is ignored by submit |
| `hsa_signal_create/destroy/load/store/wait` | S | 64-bit counters; `hsa_signal_wait_scacquire` with condition and timeout |
| `hsa_memory_allocate/free/copy` | S | Same arena as `hipMalloc` |
| `hsa_ext_submit(queue, packet)` | S | **Project-specific** struct and call: invokes a function pointer synchronously (not upstream AQL) |
| `hsa_executable_*`, `hsa_code_object_reader` | N | No code-object API at all |
| `hsa_ext_program_*`, `hsa_ext_image_*`, `hsa_amd_*` | N | Not implemented |
| AQL ring semantics (indices, doorbell, barrier packets) | N | Only the packet *shape* is honoured, by `hsa_ext_submit` |

### 2.4 Binary / code object (L2) — the decisive rows

| Feature | M1 | Consequence |
|---|---|---|
| **gfx1250 machine code (CDNA5 ISA)** | **N — not supported** | No decoder exists; M1 RTL implements 0x00–0x3A of a different 32-bit fixed encoding. No translation layer exists or is planned |
| AMDGPU ELF (`.co`, `.hsaco`) | **X** | No loader exists; nothing in the shim reads ELF |
| msgpack kernel descriptor (`KernargSegmentSize`, `WavefrontSize`, `NumVGPRs`, …) | **N** | No metadata is consumed; kernel arguments are normal C++ parameters |
| MFMA / `V_MFMA_*` | **N** | The matrix core is `S_WMMA`, fixed 16x16x32 FP4 (`spec/ISA.md` 0x15) |
| wave64, 1024 VGPR/lane, AGPR | **N** | wave32, 16 VGPR/lane, no AGPR |
| `roc-obj*`, `comgr`, `llvm-mc -arch=amdgcn`, CDNA5 cycle models | **N** | Different container/ISA; gfx1250 profiles do not transfer |
| Code-object container | **N** | None: the examples link kernels directly into the host binary |

### 2.5 ROCm libraries and frameworks (L3)

| Library | M1 | Operator mapping (not implemented) |
|---|---|---|
| **hipBLASLt** | **N — not native** | `hipblasLtMatmul` → `m1::gemm_fp4` (`doc/OPERATORS.md` §2); tile heuristics are M1-specific |
| **rocBLAS** | **N — not native** | `rocblas_gemm_ex`/`gemv`/`dot` → the same FP4 GEMM/vector kernels; no per-handle streams |
| **MIOpen** | **N — not native** | Convolution lowers to GEMM; no solver DB, no fusion graph. Pooling/normalisation need more than the current SFU |
| rocFFT, rocSPARSE, rocPRIM, rocThrust, rocALUTION, RCCL, rocprofiler, RGP, rocm-smi | **N** | Not implemented; no counters or power/clock telemetry |
| PyTorch/ROCm, JAX/ROCm, ONNX Runtime ROCm EP, Triton, HIPIFY | **N/P** | Frameworks need the full stack; HIPIFY is source-level only and device code still hits the L0/L2 limits |

## 3. What "source/API-level HIP compatibility" means

This is what `rocm/examples/hip_gemm.cpp` does today, and it passes:

```cpp
#include <hip/hip_runtime.h>
__global__ void gemm_kernel(const float* A, const float* B, int32_t* C, int M, int N, int K) {
  auto r = m1::gemm_fp4(M, N, K, std::vector<float>(A, A+M*K), std::vector<float>(B, B+K*N));
  for (size_t i = 0; i < r.C.size(); ++i) C[i] = r.C[i];
}
// host: hipMalloc / hipMemcpy / hipLaunchKernelGGL(gemm_kernel, dim3(1), dim3(1), 0, 0, ...)
```

The kernel body is **ordinary host C++** that calls an M1 operator. It is not
compiled to device code, and the "launch" is a direct call. A kernel written for
real HIP hardware needs its inner loop replaced with `m1::` operator calls (or
an instruction-level port to the M1 ISA), and any use of shuffles, atomics,
textures, `double`, or large `__shared__` must be removed.

## 4. Shim design (as built)

### 4.1 Components

| Path | Contents |
|---|---|
| `rocm/include/hip/hip_runtime.h` | Host declarations, `hipError_t` values, `dim3`, `threadIdx/blockIdx` globals, `hipLaunchKernelGGL` macro |
| `rocm/include/hsa/hsa.h` | HSA types (`hsa_signal_t`, `hsa_queue_t`, `hsa_kernel_dispatch_packet_t`), the implemented function set |
| `rocm/src/hip_shim.cpp` | HIP runtime subset over plain host memory |
| `rocm/src/hsa_shim.cpp` | HSA subset, signals, `hsa_ext_submit` |
| `rocm/examples/*.cpp` | `hip_saxpy`, `hip_gemm`, `hip_softmax`, `hip_flash_attention`, `hsa_demo` |
| hipBLASLt/rocBLAS/MIOpen mapping layer | Not implemented; no directory exists yet |
| `sim/m1_sim.hpp/.cpp` | C++ functional/cycle model the operators execute on |

### 4.2 `hipMalloc` / `hipMemcpy` / `hipMemset`

* `hipMalloc` is `std::malloc`, `hipMemcpy` is `memcpy`, `hipMemset` is
  `memset`, and the `hipMemcpyKind` argument is ignored. "Device" and host
  memory are the **same** address space: no arena, no 32-bit offsets, no
  pinning, no migration, no copy engine.
* The C++ model has its own 4 MB word-addressed `m1::Device` memory; operators
  copy host vectors in and out internally, so a caller never sees an offset.
* 128 B is the RTL AXI4/TDM block size; it constrains nothing in this shim.

### 4.3 `hipLaunchKernelGGL` / launch semantics

```
hipLaunchKernelGGL(kernel, nBlocks, nThreads, shmem, stream, ...args)
  -> threadIdx = blockIdx = dim3(0); blockDim = dim3(nThreads); gridDim = dim3(nBlocks)
  -> kernel(args...)            // one host call; kernels loop over their workload
```

There is no queue, no packet, no doorbell, and no completion signal on this
path: the call returns after the body completes. A second "launch" simply runs
after the first (single-threaded), so there is no concurrency, no preemption,
and no need for `hipDeviceSynchronize` (which is a no-op).

### 4.4 HSA signals

* `hsa_signal_t` wraps a 64-bit counter in a host pool; create/destroy,
  `hsa_signal_store_screlease`, `hsa_signal_load_scacquire`, and
  `hsa_signal_wait_scacquire(signal, cond, value, timeout_ns, ...)` are
  implemented with the requested comparison and timeout.
* Signals are host counters, not device memory: they are safe because there is
  no concurrent device agent. No signal groups, no IPC, no cross-device use.

### 4.5 HSA queues and `hsa_ext_submit`

The queue is an opaque handle and `hsa_ext_submit` ignores it: there is **no
ring buffer, no read/write index, no doorbell, and no barrier packet**. The
packet is a project-specific struct — `header`, `setup`, `workgroup_size[3]`,
`grid_size[3]`, a `kernel` **function pointer**, a `kernarg` pointer and a
`completion_signal` — not the upstream 64-byte AQL packet. Submit calls
`kernel(kernarg)` synchronously and, if a completion signal is set, stores 1
into it. It does **not** validate dimensions, group/private segment sizes, or
packet type.

### 4.6 Kernel ABI

Kernels are C++ functions. There is no kernarg blob, no hidden arguments, no
`dispatch_ptr`, no SGPR seeding, and no entry-PC convention; arguments are
ordinary parameters, and an operator call takes pointers and sizes. The RTL's
launch state (`s0=wg_id`, `s1=arg_ptr`, `s2=lds_base=0`, `s3=wg_size`,
`s4=lane_base=0`, `PC=0`) exists only in the ISA and is not modelled by this
shim.

### 4.7 Memory model

* One address space, which is host memory; little-endian; **no MMU, no
  protection, no SVM, no unified memory, no coherence protocol**.
* **No atomics and no fences**: everything is host-sequential.
* Alias rules are software contracts: `A`, `B`, and `C` must not overlap for a
  GEMM (the model reads A/B and writes C through one LDS view).
* 4 B words at this layer; 128 B is the RTL block granularity, not a shim rule.

### 4.8 Dispatch and synchronisation

* One "kernel" at a time, on the calling thread; the host call is the barrier.
* `hipDeviceSynchronize`/`hipStreamSynchronize` return immediately;
  `hsa_signal_wait_scacquire` blocks on a host counter with a timeout.
* Errors surface as `hipError_t`/`hsa_status_t` return codes; there is no
  sticky device error register in this shim (`STATUS.ERROR` is RTL-only).

### 4.9 Error mapping

`hipErrorInvalidValue`/`HSA_STATUS_ERROR_INVALID_ARGUMENT` for bad sizes,
dimensions, or packet fields; `hipErrorOutOfMemory` when the arena is
exhausted; `hipErrorNotInitialized` before `hipInit`/`hsa_init`. No
`hipErrorLaunchFailure` path exists because nothing is launched asynchronously.

### 4.10 What the shim deliberately does not do

It does **not** decode or translate gfx1250 code, load ELF/HSACO/code objects,
drive AXI4/CSRs, model AQL ring indices or doorbells, or provide concurrency,
preemption, profiling, or telemetry. It is a source-compatibility layer for
bring-up code, not a ROCm implementation.

## 5. Claims we explicitly do not make

1. "CDNA5-M1 runs unmodified ROCm" — false: only the L0/L1 subsets exist.
2. "It runs gfx1250 binaries/HSACOs" — **false**: there is no loader.
3. "Libraries (hipBLASLt/rocBLAS/MIOpen) work unchanged" — false: no native
   library; only a planned operator mapping.
4. "Source compatible means recompile-only" — false: kernels are rewritten into
   C++/`m1::` calls; nothing is compiled to device code.
5. "Same performance as CDNA5" — false: model cycles at 100 MHz, one CU.
6. "HSA queue/doorbell semantics, SVM, IPC, or peer support" — false.

## 6. Porting checklist (HIP kernel → M1)

1. Make the body ordinary C++: replace the thread/block decomposition with a
   loop and call the matching `m1::` operator (`gemm_fp4`, `softmax_f16`,
   `flash_attention_f16`, …) inside the kernel.
2. Remove `__shfl_*`/`__ballot`, atomics, textures/surfaces, `double`, device
   `malloc`/`new`, and any reliance on traps.
3. Keep `blockDim.x ≤ 32` and `gridDim.x ≤ 8` if the same code will later run
   on the RTL; the shim does not enforce it.
4. Keep `__shared__` ≤ 4 KB total (model LDS = 1,024 words).
5. Pass matrices as pointers plus M/N/K; the model is row-major and word- or
   half-granular.
6. Expect model timings (`run_operators` prints cycles), not gfx1250 budgets.

## 7. Verification status

| Test | Result |
|---|---|
| `hip_saxpy` (plain HIP kernel, host backend) | PASS, 1,024 elements, 0 errors |
| `hip_gemm_m1` (hipMalloc/Memcpy + `m1::gemm_fp4`, 64x64x64) | PASS, `max_err = 0` (exact int32) |
| `hip_softmax_m1` (8x128 FP16) | PASS, row-sum error 4.5e-04 |
| `hip_flash_attention_m1` (seq=32, dim=16) | PASS, error 0.0 |
| `hsa_demo` (init, agent, queue, signal, submit) | PASS, 0 errors |

Not covered, and not claimed: RTL-backed dispatch (the shim talks to the C++
model, not to `rtl/`), gfx1250 rejection tests, libc-free freestanding builds,
multi-threaded hosts, and any ROCm library. Until those exist the honest
summary is: **source-level HIP/HSA compatibility is demonstrated on a host
model; binary compatibility with ROCm does not exist.**
