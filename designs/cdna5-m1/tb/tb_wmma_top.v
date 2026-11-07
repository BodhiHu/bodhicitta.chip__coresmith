// Copyright (c) 2026 CDNA5-M1 project.
// SPDX-License-Identifier: MIT
//
// tb_wmma_top.v -- full-chip test: TDM -> LDS -> WMMA (16x16x32 MXFP4)
// -> V_LDS_LD/V_MEM_ST.  Uses the same behavioural AXI4 slave as tb_top.

`timescale 1ns/1ps

module tb_wmma_top;
  reg clk = 1'b0;
  reg rst_n = 1'b0;
  always #5 clk = ~clk;

  reg  [31:0] s_awaddr; reg s_awvalid; wire s_awready;
  reg  [31:0] s_wdata;  reg [3:0] s_wstrb; reg s_wvalid; wire s_wready;
  wire [1:0]  s_bresp; wire s_bvalid; reg s_bready;
  reg  [31:0] s_araddr; reg s_arvalid; wire s_arready;
  wire [31:0] s_rdata; wire [1:0] s_rresp; wire s_rvalid; reg s_rready;

  wire [31:0] m_awaddr; wire [7:0] m_awlen; wire [2:0] m_awsize;
  wire [1:0] m_awburst; wire m_awvalid; wire m_awready;
  wire [127:0] m_wdata; wire [15:0] m_wstrb; wire m_wlast; wire m_wvalid;
  wire m_wready;
  wire [1:0] m_bresp; wire m_bvalid; wire m_bready;
  wire [31:0] m_araddr; wire [7:0] m_arlen; wire [2:0] m_arsize;
  wire [1:0] m_arburst; wire m_arvalid; wire m_arready;
  wire [127:0] m_rdata; wire [1:0] m_rresp; wire m_rlast; wire m_rvalid;
  wire m_rready;
  wire irq;

  cdna5_m1_top dut (
    .clk(clk), .rst_n(rst_n),
    .s_axil_awaddr(s_awaddr), .s_axil_awvalid(s_awvalid), .s_axil_awready(s_awready),
    .s_axil_wdata(s_wdata), .s_axil_wstrb(s_wstrb), .s_axil_wvalid(s_wvalid),
    .s_axil_wready(s_wready),
    .s_axil_bresp(s_bresp), .s_axil_bvalid(s_bvalid), .s_axil_bready(s_bready),
    .s_axil_araddr(s_araddr), .s_axil_arvalid(s_arvalid), .s_axil_arready(s_arready),
    .s_axil_rdata(s_rdata), .s_axil_rresp(s_rresp), .s_axil_rvalid(s_rvalid),
    .s_axil_rready(s_rready),
    .m_axi_awaddr(m_awaddr), .m_axi_awlen(m_awlen), .m_axi_awsize(m_awsize),
    .m_axi_awburst(m_awburst), .m_axi_awvalid(m_awvalid), .m_axi_awready(m_awready),
    .m_axi_wdata(m_wdata), .m_axi_wstrb(m_wstrb), .m_axi_wlast(m_wlast),
    .m_axi_wvalid(m_wvalid), .m_axi_wready(m_wready),
    .m_axi_bresp(m_bresp), .m_axi_bvalid(m_bvalid), .m_axi_bready(m_bready),
    .m_axi_araddr(m_araddr), .m_axi_arlen(m_arlen), .m_axi_arsize(m_arsize),
    .m_axi_arburst(m_arburst), .m_axi_arvalid(m_arvalid), .m_axi_arready(m_arready),
    .m_axi_rdata(m_rdata), .m_axi_rresp(m_rresp), .m_axi_rlast(m_rlast),
    .m_axi_rvalid(m_rvalid), .m_axi_rready(m_rready),
    .irq(irq)
  );

  reg [31:0] mem [0:262143];
  reg [31:0] pmem [0:255];
  reg [31:0] araddr_lat;
  reg [3:0]  rcnt;
  reg        rvalid_r;
  wire [31:0] ridx = (araddr_lat >> 2) + rcnt * 4;

  assign m_arready = ~rvalid_r;
  assign m_rvalid  = rvalid_r;
  assign m_rlast   = (rcnt == 4'd7);
  assign m_rdata   = {mem[ridx+3], mem[ridx+2], mem[ridx+1], mem[ridx]};
  assign m_rresp   = 2'b00;

  reg [31:0] awaddr_lat;
  reg        wbusy;
  reg        bvalid_r;
  reg [3:0]  wcnt;
  assign m_awready = ~wbusy & ~bvalid_r;
  assign m_wready  = wbusy;
  assign m_bvalid  = bvalid_r;
  assign m_bresp   = 2'b00;
  integer wk;

  always @(posedge clk) begin
    if (!rst_n) begin
      araddr_lat <= 0; rcnt <= 0; rvalid_r <= 0;
      awaddr_lat <= 0; wbusy <= 0; bvalid_r <= 0; wcnt <= 0;
    end else begin
      if (m_arready && m_arvalid) begin
        araddr_lat <= m_araddr;
        rcnt <= 0;
        rvalid_r <= 1;
      end else if (rvalid_r && m_rready) begin
        if (rcnt == 4'd7) rvalid_r <= 0;
        else rcnt <= rcnt + 4'd1;
      end

      if (m_awready && m_awvalid) begin
        awaddr_lat <= m_awaddr;
        wbusy <= 1;
        wcnt <= 0;
      end else if (wbusy && m_wready && m_wvalid) begin
        for (wk = 0; wk < 4; wk = wk + 1)
          mem[(awaddr_lat >> 2) + wcnt * 4 + wk] <= m_wdata[wk*32 +: 32];
        if (m_wlast) begin
          wbusy <= 0;
          bvalid_r <= 1;
        end else begin
          wcnt <= wcnt + 4'd1;
        end
      end
      if (bvalid_r && m_bready) bvalid_r <= 0;
    end
  end

  task axil_write;
    input [31:0] addr;
    input [31:0] data;
    begin
      while (s_bvalid) @(posedge clk);
      @(negedge clk);
      s_awaddr = addr; s_awvalid = 1; s_wdata = data; s_wstrb = 4'hf; s_wvalid = 1;
      while (!s_bvalid) @(posedge clk);
      @(negedge clk);
      s_bready = 1; s_awvalid = 0; s_wvalid = 0;
      @(posedge clk); #1;
      @(negedge clk); s_bready = 0;
    end
  endtask

  task axil_read;
    input  [31:0] addr;
    output [31:0] data;
    begin
      while (s_rvalid) @(posedge clk);
      @(negedge clk);
      s_araddr = addr; s_arvalid = 1;
      while (!s_rvalid) @(posedge clk);
      #1; data = s_rdata;
      @(negedge clk); s_rready = 1; s_arvalid = 0;
      @(posedge clk); #1;
      @(negedge clk); s_rready = 0;
    end
  endtask

  integer i, errs;
  reg [31:0] rd;
  initial begin
    s_awaddr = 0; s_awvalid = 0; s_wdata = 0; s_wstrb = 0; s_wvalid = 0;
    s_bready = 0; s_araddr = 0; s_arvalid = 0; s_rready = 0;
    errs = 0;

    $readmemh("sw/wmma_test.hex", pmem);
    for (i = 0; i < 256; i = i + 1) mem[i] = pmem[i];

    for (i = 0; i < 64; i = i + 1) begin
      mem[32'h4000/4 + i] = 32'h22222222; // A = 1.0 (E2M1 0010)
      mem[32'h4100/4 + i] = 32'h44444444; // B = 2.0 (E2M1 0100)
    end

    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    repeat (3) @(posedge clk);

    axil_write(32'h00000008, 32'h00000000);
    axil_write(32'h0000000C, 32'h00000000);
    axil_write(32'h00000010, 32'd1);
    axil_write(32'h0000001C, 32'd32);
    axil_write(32'h00000020, 32'd1);
    axil_write(32'h00000000, 32'd1);

    i = 0;
    while (!irq && i < 400000) begin
      @(posedge clk);
      i = i + 1;
    end
    if (!irq) begin
      $display("FAIL: timeout waiting for irq");
      axil_read(32'h00000004, rd);
      $display("  status=%h", rd);
      $finish;
    end

    for (i = 0; i < 256; i = i + 1) begin
      if (mem[32'h5000/4 + i] !== 32'd256) begin
        if (errs < 4) $display("FAIL C[%0d]=%h expected 256", i, mem[32'h5000/4 + i]);
        errs = errs + 1;
      end
    end

    if (errs == 0) $display("PASS tb_wmma_top (16x16x32 MXFP4, %0d cycles)", i);
    else $display("FAIL tb_wmma_top (%0d errors)", errs);
    $finish;
  end

  initial begin
    #8000000;
    $display("TIMEOUT tb_wmma_top");
    $finish;
  end

endmodule
