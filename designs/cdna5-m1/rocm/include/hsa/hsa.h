// Copyright (c) 2026 CDNA5-M1 project.
// SPDX-License-Identifier: MIT
//
// hsa.h -- HSA runtime API subset for the M1 bring-up.  This is a source/API
// shim, not the ROCm HSA runtime: it models agents, signals, queues and
// memory, and dispatches a registered kernel function on the host.  It is
// enough to compile and run the M1 HSA examples; it is not ABI-compatible
// with ROCr.
#ifndef M1_HSA_H
#define M1_HSA_H

#include <cstddef>
#include <cstdint>

typedef int hsa_status_t;
enum {
  HSA_STATUS_SUCCESS = 0,
  HSA_STATUS_ERROR = 1,
  HSA_STATUS_ERROR_INVALID_ARGUMENT = 2,
  HSA_STATUS_ERROR_OUT_OF_RESOURCES = 3
};

typedef struct hsa_agent_s { uint64_t handle; } hsa_agent_t;
typedef struct hsa_signal_s { uint64_t handle; } hsa_signal_t;
typedef struct hsa_queue_s { uint64_t handle; } hsa_queue_t;

typedef enum {
  HSA_AGENT_INFO_NAME = 0,
  HSA_AGENT_INFO_DEVICE = 1,
  HSA_AGENT_INFO_QUEUE_MAX_SIZE = 2
} hsa_agent_info_t;

typedef enum {
  HSA_SYSTEM_INFO_VERSION_MAJOR = 0,
  HSA_SYSTEM_INFO_VERSION_MINOR = 1
} hsa_system_info_t;

typedef enum {
  HSA_DEVICE_TYPE_CPU = 0,
  HSA_DEVICE_TYPE_GPU = 1
} hsa_device_type_t;

typedef enum {
  HSA_SIGNAL_CONDITION_EQ = 0,
  HSA_SIGNAL_CONDITION_NE = 1
} hsa_signal_condition_t;

typedef enum {
  HSA_WAIT_STATE_BLOCKED = 0,
  HSA_WAIT_STATE_ACTIVE = 1
} hsa_wait_state_t;

typedef enum {
  HSA_QUEUE_TYPE_SINGLE = 0,
  HSA_QUEUE_TYPE_MULTI = 1
} hsa_queue_type_t;

typedef void (*hsa_kernel_t)(void* arg);

typedef struct {
  uint16_t header;
  uint16_t setup;
  uint16_t workgroup_size[3];
  uint16_t grid_size[3];
  hsa_kernel_t kernel;
  void* kernarg;
  hsa_signal_t completion_signal;
} hsa_kernel_dispatch_packet_t;

hsa_status_t hsa_init(void);
hsa_status_t hsa_shut_down(void);
hsa_status_t hsa_system_get_info(hsa_system_info_t attr, void* value);
hsa_status_t hsa_iterate_agents(hsa_status_t (*cb)(hsa_agent_t, void*), void* data);
hsa_status_t hsa_agent_get_info(hsa_agent_t agent, hsa_agent_info_t attr, void* value);
hsa_status_t hsa_queue_create(hsa_agent_t agent, uint32_t size, hsa_queue_type_t type,
                              void (*callback)(hsa_status_t, hsa_queue_t*, void*),
                              void* data, uint32_t private_segment_size,
                              uint32_t group_segment_size, hsa_queue_t** queue);
hsa_status_t hsa_queue_destroy(hsa_queue_t* queue);
hsa_status_t hsa_signal_create(hsa_signal_t initial, uint32_t num_consumers,
                               const hsa_agent_t* consumers, hsa_signal_t* signal);
hsa_status_t hsa_signal_destroy(hsa_signal_t signal);
void hsa_signal_store_screlease(hsa_signal_t signal, int64_t value);
int64_t hsa_signal_load_scacquire(hsa_signal_t signal);
hsa_status_t hsa_signal_wait_scacquire(hsa_signal_t signal, hsa_signal_condition_t cond,
                                       int64_t compare, uint64_t timeout_hint,
                                       hsa_wait_state_t wait_state);
hsa_status_t hsa_memory_allocate(hsa_agent_t agent, size_t size, void** ptr);
hsa_status_t hsa_memory_free(void* ptr);
hsa_status_t hsa_memory_copy(void* dst, const void* src, size_t size);

// M1 extension: submit one dispatch packet and wait for completion.  This
// replaces the ROCr AQL doorbell path in the bring-up.
hsa_status_t hsa_ext_submit(hsa_queue_t* queue, const hsa_kernel_dispatch_packet_t* packet);

#endif  // M1_HSA_H
