// Copyright (c) 2026 CDNA5-M1 project.
// SPDX-License-Identifier: MIT
//
// HSA runtime API shim demo: agent discovery, signal, queue, memory, and one
// dispatch packet.  Source/API-level compatibility, not ROCr ABI.
#include <hsa/hsa.h>

#include <cstdio>
#include <cstring>

struct SaxpyArgs {
  float* y;
  const float* x;
  float a;
  int n;
};

static void saxpy_kernel(void* raw) {
  auto* p = static_cast<SaxpyArgs*>(raw);
  for (int i = 0; i < p->n; ++i) p->y[i] = p->a * p->x[i] + p->y[i];
}

static hsa_status_t on_agent(hsa_agent_t agent, void* data) {
  char name[64] = {0};
  hsa_agent_get_info(agent, HSA_AGENT_INFO_NAME, name);
  std::printf("  agent: %s\n", name);
  *static_cast<hsa_agent_t*>(data) = agent;
  return HSA_STATUS_SUCCESS;
}

int main() {
  hsa_init();
  hsa_agent_t agent{};
  hsa_iterate_agents(on_agent, &agent);
  hsa_signal_t signal{};
  hsa_signal_t sig0{}; hsa_signal_create(sig0, 0, nullptr, &signal);
  hsa_queue_t* queue = nullptr;
  hsa_queue_create(agent, 64, HSA_QUEUE_TYPE_SINGLE, nullptr, nullptr, 0, 0, &queue);
  void* dx = nullptr;
  void* dy = nullptr;
  hsa_memory_allocate(agent, 1024 * sizeof(float), &dx);
  hsa_memory_allocate(agent, 1024 * sizeof(float), &dy);
  float hx[1024], hy[1024];
  for (int i = 0; i < 1024; ++i) { hx[i] = 2.0f; hy[i] = 1.0f; }
  hsa_memory_copy(dx, hx, sizeof(hx));
  hsa_memory_copy(dy, hy, sizeof(hy));
  SaxpyArgs args{static_cast<float*>(dy), static_cast<const float*>(dx), 3.0f, 1024};
  hsa_kernel_dispatch_packet_t pkt{};
  pkt.kernel = saxpy_kernel;
  pkt.kernarg = &args;
  pkt.completion_signal = signal;
  hsa_ext_submit(queue, &pkt);
  hsa_signal_wait_scacquire(signal, HSA_SIGNAL_CONDITION_EQ, 1, 0, HSA_WAIT_STATE_BLOCKED);
  hsa_memory_copy(hy, dy, sizeof(hy));
  int errs = 0;
  for (int i = 0; i < 1024; ++i) if (hy[i] != 7.0f) ++errs;
  hsa_memory_free(dx); hsa_memory_free(dy);
  hsa_queue_destroy(queue);
  hsa_signal_destroy(signal);
  hsa_shut_down();
  std::printf("%s hsa_demo (agent/queue/signal/dispatch, %d errors)\n",
              errs ? "FAIL" : "PASS", errs);
  return errs ? 1 : 0;
}
