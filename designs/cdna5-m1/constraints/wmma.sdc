# Copyright (c) 2026 CDNA5-M1 project.
# SPDX-License-Identifier: MIT
# 100 MHz bring-up constraint for CDNA5-M1 blocks.
create_clock -name clk -period 10.0 [get_ports clk]
set_clock_uncertainty -setup 0.50 [get_clocks clk]
set_clock_uncertainty -hold  0.15 [get_clocks clk]
set_max_fanout 16 [current_design]
set_max_transition 1.5 [current_design]
