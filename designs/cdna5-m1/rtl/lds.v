// Copyright (c) 2026 CDNA5-M1 project.
// SPDX-License-Identifier: MIT
//
// lds.v -- Local Data Share / WGP-cache scratchpad, 4 KB, 32 banks x 32 rows.
//
//   word index w = byte_addr[11:2]
//   bank = w[4:0] (byte_addr[6:2]), row = w[9:5] (byte_addr[11:7])
//
// Two 32-lane ports (one per SIMD) plus one 32-word linear port used by WMMA
// and TDM.  A lane port is conflict-free only when its 32 lane addresses map
// to 32 distinct banks (the contiguous V_LDS_* forms guarantee this).  On a
// bank conflict the port is not served and `conflictN` is asserted; the SIMD
// raises a wave error rather than silently returning wrong data.  A production
// CDNA5 LDS would serialise conflicting lanes; the M1 software model is
// conflict-free by construction.

`include "cdna5_m1_defs.vh"

module lds (
  input  wire         clk,
  input  wire         rst_n,

  // lane port 0
  input  wire         req0,
  input  wire         we0,
  input  wire [1023:0] addr0,
  input  wire [1023:0] wdata0,
  output reg  [1023:0] rdata0,
  output reg          ready0,
  output wire         conflict0,

  // lane port 1
  input  wire         req1,
  input  wire         we1,
  input  wire [1023:0] addr1,
  input  wire [1023:0] wdata1,
  output reg  [1023:0] rdata1,
  output reg          ready1,
  output wire         conflict1,

  // linear 32-word port (WMMA / TDM)
  input  wire         reql,
  input  wire         wel,
  input  wire [9:0]   addrl,
  input  wire [1023:0] wdatal,
  output reg  [1023:0] rdatal,
  output reg          readyl,

  // scalar word port (softmax engine / SFU)
  input  wire         reqs,
  input  wire         wes,
  input  wire [9:0]   addrs,
  input  wire [31:0]  wdatas,
  output wire [31:0]  rdatas,
  output wire         readys
);

  reg [31:0] mem [0:31][0:31]; // [bank][row]

  assign rdatas = mem[addrs[4:0]][addrs[9:5]];
  assign readys = reqs;

  always @(posedge clk) begin
    if (reqs && wes) mem[addrs[4:0]][addrs[9:5]] <= wdatas;
  end
  reg [31:0] a0 [0:31];
  reg [31:0] a1 [0:31];

  integer i, j;

  always @* begin
    for (i = 0; i < 32; i = i + 1) begin
      a0[i] = addr0[i*32 +: 32];
      a1[i] = addr1[i*32 +: 32];
    end
  end

  // ---------------------------------------------------- conflict detection
  reg conflict0_r, conflict1_r;
  always @* begin
    conflict0_r = 1'b0;
    conflict1_r = 1'b0;
    for (i = 0; i < 32; i = i + 1) begin
      for (j = i + 1; j < 32; j = j + 1) begin
        if ((a0[i][6:2] == a0[j][6:2]) && (a0[i][11:7] != a0[j][11:7]))
          conflict0_r = 1'b1;
        if ((a1[i][6:2] == a1[j][6:2]) && (a1[i][11:7] != a1[j][11:7]))
          conflict1_r = 1'b1;
      end
    end
  end

  assign conflict0 = conflict0_r;
  assign conflict1 = conflict1_r;

  wire grant0 = req0 & ~conflict0_r;
  wire grant1 = req1 & ~conflict1_r & ~grant0;
  wire grantl = reql & ~grant0 & ~grant1;

  // ---------------------------------------------------- read data
  reg [31:0] r0 [0:31];
  reg [31:0] r1 [0:31];
  reg [31:0] rl [0:31];
  always @* begin
    for (i = 0; i < 32; i = i + 1) begin
      r0[i] = mem[a0[i][6:2]][a0[i][11:7]];
      r1[i] = mem[a1[i][6:2]][a1[i][11:7]];
      rl[i] = mem[i[4:0]][addrl[9:5]];
    end
  end

  // ---------------------------------------------------- access
  always @(posedge clk) begin
    if (!rst_n) begin
      ready0 <= 1'b0;
      ready1 <= 1'b0;
      readyl <= 1'b0;
      rdata0 <= 1024'd0;
      rdata1 <= 1024'd0;
      rdatal <= 1024'd0;
    end else begin
      ready0 <= 1'b0;
      ready1 <= 1'b0;
      readyl <= 1'b0;

      if (grant0) begin
        ready0 <= 1'b1;
        if (we0) begin
          for (i = 0; i < 32; i = i + 1)
            mem[a0[i][6:2]][a0[i][11:7]] <= wdata0[i*32 +: 32];
        end else begin
          for (i = 0; i < 32; i = i + 1)
            rdata0[i*32 +: 32] <= r0[i];
        end
      end

      if (grant1) begin
        ready1 <= 1'b1;
        if (we1) begin
          for (i = 0; i < 32; i = i + 1)
            mem[a1[i][6:2]][a1[i][11:7]] <= wdata1[i*32 +: 32];
        end else begin
          for (i = 0; i < 32; i = i + 1)
            rdata1[i*32 +: 32] <= r1[i];
        end
      end

      if (grantl) begin
        readyl <= 1'b1;
        if (wel) begin
          for (i = 0; i < 32; i = i + 1)
            mem[i[4:0]][addrl[9:5]] <= wdatal[i*32 +: 32];
        end else begin
          for (i = 0; i < 32; i = i + 1)
            rdatal[i*32 +: 32] <= rl[i];
        end
      end
    end
  end

endmodule
