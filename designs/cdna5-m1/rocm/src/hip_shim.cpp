// Copyright (c) 2026 CDNA5-M1 project.
// SPDX-License-Identifier: MIT
#include <hip/hip_runtime.h>

#include <chrono>
#include <cstdio>
#include <new>

dim3 threadIdx(0), blockIdx(0), blockDim(1), gridDim(1);

namespace {
struct Event {
  std::chrono::steady_clock::time_point t;
};
bool g_inited = false;
int g_device = 0;
}  // namespace

hipError_t hipInit(unsigned) {
  g_inited = true;
  return hipSuccess;
}
hipError_t hipGetDevice(int* device) {
  if (!device) return hipErrorInvalidValue;
  *device = g_device;
  return hipSuccess;
}
hipError_t hipSetDevice(int device) {
  g_device = device;
  return hipSuccess;
}
hipError_t hipGetDeviceCount(int* count) {
  if (!count) return hipErrorInvalidValue;
  *count = 1;
  return hipSuccess;
}
hipError_t hipGetDeviceProperties(hipDeviceProp_t* prop, int) {
  if (!prop) return hipErrorInvalidValue;
  std::snprintf(prop->name, sizeof(prop->name), "CDNA5-M1 (functional simulator)");
  prop->totalGlobalMem = 4ull * 1024 * 1024;
  prop->multiProcessorCount = 1;
  prop->warpSize = 32;
  prop->clockRate = 100000;  // kHz
  return hipSuccess;
}
hipError_t hipMalloc(void** ptr, size_t bytes) {
  if (!ptr) return hipErrorInvalidValue;
  *ptr = std::malloc(bytes ? bytes : 1);
  return *ptr ? hipSuccess : hipErrorOutOfMemory;
}
hipError_t hipFree(void* ptr) {
  std::free(ptr);
  return hipSuccess;
}
hipError_t hipMemcpy(void* dst, const void* src, size_t bytes, hipMemcpyKind) {
  if (bytes) std::memcpy(dst, src, bytes);
  return hipSuccess;
}
hipError_t hipMemset(void* ptr, int value, size_t bytes) {
  std::memset(ptr, value, bytes);
  return hipSuccess;
}
hipError_t hipDeviceSynchronize(void) { return hipSuccess; }
hipError_t hipStreamCreate(hipStream_t* stream) {
  if (!stream) return hipErrorInvalidValue;
  *stream = reinterpret_cast<hipStream_t>(1);
  return hipSuccess;
}
hipError_t hipStreamDestroy(hipStream_t) { return hipSuccess; }
hipError_t hipEventCreate(hipEvent_t* event) {
  if (!event) return hipErrorInvalidValue;
  *event = new (std::nothrow) Event();
  return *event ? hipSuccess : hipErrorOutOfMemory;
}
hipError_t hipEventDestroy(hipEvent_t event) {
  delete reinterpret_cast<Event*>(event);
  return hipSuccess;
}
hipError_t hipEventRecord(hipEvent_t event, hipStream_t) {
  auto* e = reinterpret_cast<Event*>(event);
  if (!e) return hipErrorInvalidValue;
  e->t = std::chrono::steady_clock::now();
  return hipSuccess;
}
hipError_t hipEventSynchronize(hipEvent_t) { return hipSuccess; }
hipError_t hipEventElapsedTime(float* ms, hipEvent_t start, hipEvent_t stop) {
  if (!ms) return hipErrorInvalidValue;
  auto* a = reinterpret_cast<Event*>(start);
  auto* b = reinterpret_cast<Event*>(stop);
  if (!a || !b) return hipErrorInvalidValue;
  *ms = std::chrono::duration<float, std::milli>(b->t - a->t).count();
  return hipSuccess;
}
const char* hipGetErrorString(hipError_t err) {
  switch (err) {
    case hipSuccess: return "hipSuccess";
    case hipErrorInvalidValue: return "hipErrorInvalidValue";
    case hipErrorOutOfMemory: return "hipErrorOutOfMemory";
    case hipErrorNotInitialized: return "hipErrorNotInitialized";
    case hipErrorInvalidDevice: return "hipErrorInvalidDevice";
    default: return "hipErrorUnknown";
  }
}
