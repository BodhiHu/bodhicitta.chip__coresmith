<!-- rendered from project.sqlite by coresmith state write; edit with coresmith frd add/edit -->

# Functional Requirements Document

## Performance Requirements

1. **ID**: PERF-001
   - **Requirement**: Matrix core sustains 102.4 GFLOP/s MXFP4 (512 MAC/cycle at 100 MHz) [HARD, KPI-001]
   - **Acceptance criteria**: measured WMMA throughput
   - **Priority**: must_have
   - **Metric**: flops; min 102400000000; max -; unit flop/s
