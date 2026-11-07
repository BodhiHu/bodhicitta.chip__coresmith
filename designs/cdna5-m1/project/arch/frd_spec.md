<!-- rendered from project.sqlite by coresmith state write; edit with coresmith frd add/edit -->

# Functional Requirements Document

## Performance Requirements

1. **ID**: PERF-001
   - **Requirement**: Matrix core sustains 102.4 GFLOP/s MXFP4 (512 MAC/cycle at 100 MHz) [HARD, KPI-001]
   - **Acceptance criteria**: measured WMMA throughput
   - **Priority**: must_have
   - **Metric**: flops; min 102400000000; max -; unit flop/s

2. **ID**: PERF-002
   - **Requirement**: Matrix core sustained throughput >=92.16 GFLOP/s (>=90% of the 102.4 GFLOP/s peak) with A/B operands fed from LDS [HARD, KPI-001, KPI-PERF-001]
   - **Acceptance criteria**: measured sustained WMMA throughput over back-to-back 16x16x32 MXFP4 MFMA operations with A/B resident in LDS (KPI-PERF-001)
   - **Priority**: must_have
   - **Metric**: flops; min 92160000000; max -; unit flop/s
