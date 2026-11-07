// Copyright (c) 2026 CDNA5-M1 project.
// SPDX-License-Identifier: MIT
//
// hip_runtime.h -- source/API-level HIP compatibility header for the M1
// ROCm bring-up.  It is NOT a ROCm binary runtime and does not implement a
// GPU driver: kernels are compiled as ordinary C++ and executed serially by
// the host shim.  Applications written against the HIP runtime API compile
// unchanged; device operators that need the M1 model call m1:: explicitly.
#ifndef M1_HIP_RUNTIME_H
#define M1_HIP_RUNTIME_H

#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>

#define __global__
#define __device__
#define __host__
#define __shared__ static
#define __forceinline__ inline

typedef int hipError_t;
enum {
  hipSuccess = 0,
  hipErrorInvalidValue = 1,
  hipErrorOutOfMemory = 2,
  hipErrorNotInitialized = 3,
  hipErrorInvalidDevice = 4,
  hipErrorUnknown = 999
};

enum hipMemcpyKind {
  hipMemcpyHostToHost = 0,
  hipMemcpyHostToDevice = 1,
  hipMemcpyDeviceToHost = 2,
  hipMemcpyDeviceToDevice = 3,
  hipMemcpyDefault = 4
};

struct dim3 {
  unsigned x, y, z;
  dim3(unsigned x_ = 1, unsigned y_ = 1, unsigned z_ = 1) : x(x_), y(y_), z(z_) {}
};

extern dim3 threadIdx;
extern dim3 blockIdx;
extern dim3 blockDim;
extern dim3 gridDim;

struct hipDeviceProp_t {
  char name[256];
  size_t totalGlobalMem;
  int multiProcessorCount;
  int warpSize;
  int clockRate;
};

typedef void* hipStream_t;
typedef void* hipEvent_t;

hipError_t hipInit(unsigned flags);
hipError_t hipGetDevice(int* device);
hipError_t hipSetDevice(int device);
hipError_t hipGetDeviceCount(int* count);
hipError_t hipGetDeviceProperties(hipDeviceProp_t* prop, int device);
hipError_t hipMalloc(void** ptr, size_t bytes);
hipError_t hipFree(void* ptr);
hipError_t hipMemcpy(void* dst, const void* src, size_t bytes, hipMemcpyKind kind);
hipError_t hipMemset(void* ptr, int value, size_t bytes);
hipError_t hipDeviceSynchronize(void);
hipError_t hipStreamCreate(hipStream_t* stream);
hipError_t hipStreamDestroy(hipStream_t stream);
hipError_t hipEventCreate(hipEvent_t* event);
hipError_t hipEventDestroy(hipEvent_t event);
hipError_t hipEventRecord(hipEvent_t event, hipStream_t stream);
hipError_t hipEventSynchronize(hipEvent_t event);
hipError_t hipEventElapsedTime(float* ms, hipEvent_t start, hipEvent_t stop);
const char* hipGetErrorString(hipError_t err);

// The M1 shim executes the kernel body once on the host.  Grid/block loops are
// a no-op; kernels used in this bring-up loop internally over their workload.
#define hipLaunchKernelGGL(kernel, nBlocks, nThreads, shmem, stream, ...) \
  do {                                                                     \
    threadIdx = dim3(0); blockIdx = dim3(0);                               \
    blockDim = dim3(nThreads); gridDim = dim3(nBlocks);                    \
    kernel(__VA_ARGS__);                                                   \
  } while (0)

#endif  // M1_HIP_RUNTIME_H
