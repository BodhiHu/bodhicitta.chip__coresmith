// Copyright (c) 2026 CDNA5-M1 project.
// SPDX-License-Identifier: MIT
#include <hsa/hsa.h>

#include <cstdlib>
#include <cstring>
#include <map>

namespace {
std::map<uint64_t, int64_t> g_signals;
uint64_t g_next = 1;
bool g_inited = false;
}  // namespace

hsa_status_t hsa_init(void) {
  g_inited = true;
  return HSA_STATUS_SUCCESS;
}
hsa_status_t hsa_shut_down(void) {
  g_inited = false;
  return HSA_STATUS_SUCCESS;
}
hsa_status_t hsa_system_get_info(hsa_system_info_t attr, void* value) {
  if (!value) return HSA_STATUS_ERROR_INVALID_ARGUMENT;
  if (attr == HSA_SYSTEM_INFO_VERSION_MAJOR) *static_cast<uint32_t*>(value) = 1;
  else *static_cast<uint32_t*>(value) = 0;
  return HSA_STATUS_SUCCESS;
}
hsa_status_t hsa_iterate_agents(hsa_status_t (*cb)(hsa_agent_t, void*), void* data) {
  if (!cb) return HSA_STATUS_ERROR_INVALID_ARGUMENT;
  hsa_agent_t a;
  a.handle = 1;
  return cb(a, data);
}
hsa_status_t hsa_agent_get_info(hsa_agent_t, hsa_agent_info_t attr, void* value) {
  if (!value) return HSA_STATUS_ERROR_INVALID_ARGUMENT;
  switch (attr) {
    case HSA_AGENT_INFO_NAME:
      std::strncpy(static_cast<char*>(value), "CDNA5-M1", 64);
      break;
    case HSA_AGENT_INFO_DEVICE:
      *static_cast<uint32_t*>(value) = HSA_DEVICE_TYPE_GPU;
      break;
    case HSA_AGENT_INFO_QUEUE_MAX_SIZE:
      *static_cast<uint32_t*>(value) = 64;
      break;
  }
  return HSA_STATUS_SUCCESS;
}
hsa_status_t hsa_queue_create(hsa_agent_t, uint32_t, hsa_queue_type_t,
                              void (*)(hsa_status_t, hsa_queue_t*, void*), void*,
                              uint32_t, uint32_t, hsa_queue_t** queue) {
  if (!queue) return HSA_STATUS_ERROR_INVALID_ARGUMENT;
  auto* q = new (std::nothrow) hsa_queue_t();
  if (!q) return HSA_STATUS_ERROR_OUT_OF_RESOURCES;
  q->handle = g_next++;
  *queue = q;
  return HSA_STATUS_SUCCESS;
}
hsa_status_t hsa_queue_destroy(hsa_queue_t* queue) {
  delete queue;
  return HSA_STATUS_SUCCESS;
}
hsa_status_t hsa_signal_create(hsa_signal_t, uint32_t, const hsa_agent_t*, hsa_signal_t* signal) {
  if (!signal) return HSA_STATUS_ERROR_INVALID_ARGUMENT;
  signal->handle = g_next++;
  g_signals[signal->handle] = 0;
  return HSA_STATUS_SUCCESS;
}
hsa_status_t hsa_signal_destroy(hsa_signal_t signal) {
  g_signals.erase(signal.handle);
  return HSA_STATUS_SUCCESS;
}
void hsa_signal_store_screlease(hsa_signal_t signal, int64_t value) {
  g_signals[signal.handle] = value;
}
int64_t hsa_signal_load_scacquire(hsa_signal_t signal) {
  auto it = g_signals.find(signal.handle);
  return it == g_signals.end() ? 0 : it->second;
}
hsa_status_t hsa_signal_wait_scacquire(hsa_signal_t signal, hsa_signal_condition_t cond,
                                       int64_t compare, uint64_t, hsa_wait_state_t) {
  const int64_t v = hsa_signal_load_scacquire(signal);
  const bool ok = (cond == HSA_SIGNAL_CONDITION_EQ) ? (v == compare) : (v != compare);
  return ok ? HSA_STATUS_SUCCESS : HSA_STATUS_ERROR;
}
hsa_status_t hsa_memory_allocate(hsa_agent_t, size_t size, void** ptr) {
  if (!ptr) return HSA_STATUS_ERROR_INVALID_ARGUMENT;
  *ptr = std::malloc(size ? size : 1);
  return *ptr ? HSA_STATUS_SUCCESS : HSA_STATUS_ERROR_OUT_OF_RESOURCES;
}
hsa_status_t hsa_memory_free(void* ptr) {
  std::free(ptr);
  return HSA_STATUS_SUCCESS;
}
hsa_status_t hsa_memory_copy(void* dst, const void* src, size_t size) {
  std::memcpy(dst, src, size);
  return HSA_STATUS_SUCCESS;
}
hsa_status_t hsa_ext_submit(hsa_queue_t*, const hsa_kernel_dispatch_packet_t* packet) {
  if (!packet || !packet->kernel) return HSA_STATUS_ERROR_INVALID_ARGUMENT;
  packet->kernel(packet->kernarg);
  if (packet->completion_signal.handle) hsa_signal_store_screlease(packet->completion_signal, 1);
  return HSA_STATUS_SUCCESS;
}
