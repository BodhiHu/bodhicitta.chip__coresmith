// Copyright (c) 2026 CDNA5-M1 project.
// SPDX-License-Identifier: MIT
//
// cdna5_m1_defs.vh -- opcodes and shared parameters for the CDNA5-M1 core.
// Frozen encoding: see spec/ISA.md.

`ifndef CDNA5_M1_DEFS_VH
`define CDNA5_M1_DEFS_VH

// ---------------------------------------------------------------- scalar ops
`define S_NOP            6'h00
`define S_MOV_B32        6'h01
`define S_ADD_U32        6'h02
`define S_SUB_U32        6'h03
`define S_AND_B32        6'h04
`define S_OR_B32         6'h05
`define S_XOR_B32        6'h06
`define S_SHL_B32        6'h07
`define S_SHR_B32        6'h08
`define S_CMP_LT_U32     6'h09
`define S_CBRANCH_SCC    6'h0A
`define S_BRANCH         6'h0B
`define S_ENDPGM         6'h0C
`define S_BARRIER        6'h0D
`define S_WAITCNT        6'h0E
`define S_GET_WG_ID      6'h0F
`define S_GET_WG_SIZE    6'h10
`define S_MOV_B64        6'h11
`define S_LDS_ADDR       6'h12
`define S_CSR_READ       6'h13
`define S_TDM_COPY       6'h14
`define S_WMMA           6'h15
`define S_GET_LANE_BASE  6'h16
`define S_SET_EXEC       6'h17
`define S_SOFTMAX        6'h18

// ---------------------------------------------------------------- vector ops
`define V_NOP               6'h20
`define V_MOV_B32           6'h21
`define V_ADD_I32           6'h22
`define V_SUB_I32           6'h23
`define V_AND_B32           6'h24
`define V_OR_B32            6'h25
`define V_XOR_B32           6'h26
`define V_SHL_B32           6'h27
`define V_SHR_B32           6'h28
`define V_MUL_I32           6'h29
`define V_CMP_LT_I32        6'h2A
`define V_CNDMASK           6'h2B
`define V_MBCNT_LO_U32      6'h2C
`define V_DOT4_I32_IU8      6'h2D
`define V_DOT8_I32_IU4      6'h2E
`define V_CVT_F32_I32       6'h2F
`define V_LDS_LD            6'h30
`define V_LDS_ST            6'h31
`define V_MEM_LD            6'h32
`define V_MEM_ST            6'h33
`define V_ADD_F16           6'h34
`define V_MUL_F16           6'h35
`define V_FMA_F16           6'h36
`define V_CVT_F16_F32       6'h37
`define V_LDS_LD_IDX        6'h38
`define V_LDS_ST_IDX        6'h39
`define V_READFIRSTLANE_B32 6'h3A

// ---------------------------------------------------------------- parameters
`define WAVE_SIZE 32
`define VGPR_NUM  16
`define SGPR_NUM  32
`define LDS_BANKS 32
`define LDS_ROWS  32
`define IMEM_WORDS 256

`endif // CDNA5_M1_DEFS_VH
