// Copyright (c) 2026 CDNA5-M1 project.
// SPDX-License-Identifier: MIT
//
// tb_wmma.v -- self-checking unit test for the M1 matrix core against a real
// LDS instance.  A = 1.0 (E2M1 0010), B = 2.0 (0100), K = 32:
//   C[i][j] = 32 * (2*4) = 256 in the integer pipeline.
// Runs on iverilog; part of the bring-up regression.

`timescale 1ns/1ps

module tb_wmma;
  reg clk = 1'b0;
  reg rst_n = 1'b0;
  always #5 clk = ~clk;

  reg         tb_req, tb_we;
  reg  [9:0]  tb_addr;
  reg  [1023:0] tb_wdata;
  reg         tb_drive;

  wire        l_req, l_we;
  wire [9:0]  l_addr;
  wire [1023:0] l_wdata, l_rdata;
  wire        l_ready;
  wire [1023:0] rdata0, rdata1;
  wire        ready0, ready1, cfl0, cfl1;

  lds u_lds (
    .clk(clk), .rst_n(rst_n),
    .req0(1'b0), .we0(1'b0), .addr0(1024'd0), .wdata0(1024'd0),
    .rdata0(rdata0), .ready0(ready0), .conflict0(cfl0),
    .req1(1'b0), .we1(1'b0), .addr1(1024'd0), .wdata1(1024'd0),
    .rdata1(rdata1), .ready1(ready1), .conflict1(cfl1),
    .reql(l_req), .wel(l_we), .addrl(l_addr), .wdatal(l_wdata),
    .rdatal(l_rdata), .readyl(l_ready)
  );

  reg         start;
  reg  [9:0]  a_base, b_base, c_base;
  wire        busy, done;
  wire        w_req, w_we, w_ready;
  wire [9:0]  w_addr;
  wire [1023:0] w_wdata;

  wmma u_wmma (
    .clk(clk), .rst_n(rst_n),
    .start(start), .a_base(a_base), .b_base(b_base), .c_base(c_base),
    .busy(busy), .done(done),
    .lds_req(w_req), .lds_we(w_we), .lds_addr(w_addr),
    .lds_wdata(w_wdata), .lds_rdata(l_rdata), .lds_ready(w_ready)
  );

  assign l_req   = tb_drive ? tb_req  : w_req;
  assign l_we    = tb_drive ? tb_we   : w_we;
  assign l_addr  = tb_drive ? tb_addr : w_addr;
  assign l_wdata = tb_drive ? tb_wdata: w_wdata;
  assign w_ready = l_ready & ~tb_drive;

  integer i, errs;
  reg [1023:0] cap;

  task lds_write32;
    input [9:0] waddr;
    input [31:0] val;
    integer k;
    begin
      @(negedge clk);
      tb_drive = 1'b1; tb_req = 1'b1; tb_we = 1'b1; tb_addr = waddr;
      for (k = 0; k < 32; k = k + 1) tb_wdata[k*32 +: 32] = val;
      @(posedge clk); #1;
      while (!l_ready) begin @(posedge clk); #1; end
      @(negedge clk);
      tb_req = 1'b0; tb_we = 1'b0; tb_drive = 1'b0;
    end
  endtask

  task lds_read32;
    input [9:0] waddr;
    begin
      @(negedge clk);
      tb_drive = 1'b1; tb_req = 1'b1; tb_we = 1'b0; tb_addr = waddr;
      @(posedge clk); #1;
      while (!l_ready) begin @(posedge clk); #1; end
      cap = l_rdata;
      @(negedge clk);
      tb_req = 1'b0; tb_drive = 1'b0;
    end
  endtask

  initial begin
    tb_req = 0; tb_we = 0; tb_addr = 0; tb_wdata = 0; tb_drive = 0;
    start = 0; a_base = 0; b_base = 64; c_base = 128;
    errs = 0;
    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    for (i = 0; i < 64; i = i + 1) lds_write32(i, 32'h22222222);
    for (i = 0; i < 64; i = i + 1) lds_write32(64 + i, 32'h44444444);

    @(negedge clk);
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;

    while (!done) @(posedge clk);
    #1;

    for (i = 0; i < 256; i = i + 1) begin
      if ((i % 32) == 0) lds_read32(128 + (i / 32) * 32);
      if (cap[(i % 32)*32 +: 32] !== 32'd256) begin
        $display("FAIL C[%0d] = %0d expected 256", i, cap[(i % 32)*32 +: 32]);
        errs = errs + 1;
      end
    end

    if (errs == 0) $display("PASS tb_wmma");
    else $display("FAIL tb_wmma (%0d errors)", errs);
    $finish;
  end

  initial begin
    #400000;
    $display("TIMEOUT tb_wmma");
    $finish;
  end

endmodule
