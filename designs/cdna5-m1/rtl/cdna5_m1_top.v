// Copyright (c) 2026 CDNA5-M1 project.
// SPDX-License-Identifier: MIT
//
// cdna5_m1_top.v -- CDNA5-M1 0.1 TFLOP/s MXFP4 accelerator (Sky130 bring-up).
//
// 1 WGP / 1 CU / 2 SIMD32, 4 KB LDS, 16x16x32 MXFP4 matrix core, 1 KB I$,
// 1-D TDM, AXI4-Lite host control and AXI4 global-memory master.

`include "cdna5_m1_defs.vh"

module cdna5_m1_top (
  input  wire        clk,
  input  wire        rst_n,

  // AXI4-Lite host control
  input  wire [31:0] s_axil_awaddr,
  input  wire        s_axil_awvalid,
  output wire        s_axil_awready,
  input  wire [31:0] s_axil_wdata,
  input  wire [3:0]  s_axil_wstrb,
  input  wire        s_axil_wvalid,
  output wire        s_axil_wready,
  output wire [1:0]  s_axil_bresp,
  output wire        s_axil_bvalid,
  input  wire        s_axil_bready,
  input  wire [31:0] s_axil_araddr,
  input  wire        s_axil_arvalid,
  output wire        s_axil_arready,
  output wire [31:0] s_axil_rdata,
  output wire [1:0]  s_axil_rresp,
  output wire        s_axil_rvalid,
  input  wire        s_axil_rready,

  // AXI4 global memory master
  output wire [31:0] m_axi_awaddr,
  output wire [7:0]  m_axi_awlen,
  output wire [2:0]  m_axi_awsize,
  output wire [1:0]  m_axi_awburst,
  output wire        m_axi_awvalid,
  input  wire        m_axi_awready,
  output wire [127:0] m_axi_wdata,
  output wire [15:0] m_axi_wstrb,
  output wire        m_axi_wlast,
  output wire        m_axi_wvalid,
  input  wire        m_axi_wready,
  input  wire [1:0]  m_axi_bresp,
  input  wire        m_axi_bvalid,
  output wire        m_axi_bready,
  output wire [31:0] m_axi_araddr,
  output wire [7:0]  m_axi_arlen,
  output wire [2:0]  m_axi_arsize,
  output wire [1:0]  m_axi_arburst,
  output wire        m_axi_arvalid,
  input  wire        m_axi_arready,
  input  wire [127:0] m_axi_rdata,
  input  wire [1:0]  m_axi_rresp,
  input  wire        m_axi_rlast,
  input  wire        m_axi_rvalid,
  output wire        m_axi_rready,

  output wire        irq
);

  // ---------------------------------------------------------------- AXI-Lite
  wire        csr_wr, csr_rd;
  wire [7:0]  csr_waddr, csr_raddr;
  wire [31:0] csr_wdata, csr_rdata;

  axi_lite_slave u_axil (
    .clk(clk), .rst_n(rst_n),
    .s_axil_awaddr(s_axil_awaddr), .s_axil_awvalid(s_axil_awvalid),
    .s_axil_awready(s_axil_awready),
    .s_axil_wdata(s_axil_wdata), .s_axil_wstrb(s_axil_wstrb),
    .s_axil_wvalid(s_axil_wvalid), .s_axil_wready(s_axil_wready),
    .s_axil_bresp(s_axil_bresp), .s_axil_bvalid(s_axil_bvalid),
    .s_axil_bready(s_axil_bready),
    .s_axil_araddr(s_axil_araddr), .s_axil_arvalid(s_axil_arvalid),
    .s_axil_arready(s_axil_arready),
    .s_axil_rdata(s_axil_rdata), .s_axil_rresp(s_axil_rresp),
    .s_axil_rvalid(s_axil_rvalid), .s_axil_rready(s_axil_rready),
    .csr_wr(csr_wr), .csr_waddr(csr_waddr), .csr_wdata(csr_wdata),
    .csr_rd(csr_rd), .csr_raddr(csr_raddr), .csr_rdata(csr_rdata)
  );

  // ---------------------------------------------------------------- CP
  wire         cp_mem_req;
  wire         cp_mem_we;
  wire [31:0]  cp_mem_addr;
  wire [1023:0] cp_mem_wdata;
  reg  [1023:0] cp_mem_rdata;
  reg          cp_mem_ready;

  wire         ic_we;
  wire [7:0]   ic_addr;
  wire [31:0]  ic_wdata;

  wire         wgp_start;
  wire [7:0]   grid_x;
  wire [15:0]  wg_size;
  wire [31:0]  arg_ptr;
  wire         wgp_busy, wgp_done, wgp_error;
  wire [7:0]   waves_done;
  wire [63:0]  cycle;

  command_processor u_cp (
    .clk(clk), .rst_n(rst_n),
    .csr_wr(csr_wr), .csr_waddr(csr_waddr), .csr_wdata(csr_wdata),
    .csr_rd(csr_rd), .csr_raddr(csr_raddr), .csr_rdata(csr_rdata),
    .mem_req(cp_mem_req), .mem_we(cp_mem_we), .mem_addr(cp_mem_addr),
    .mem_wdata(cp_mem_wdata), .mem_rdata(cp_mem_rdata), .mem_ready(cp_mem_ready),
    .ic_we(ic_we), .ic_addr(ic_addr), .ic_wdata(ic_wdata),
    .wgp_start(wgp_start), .grid_x(grid_x), .wg_size(wg_size), .arg_ptr(arg_ptr),
    .wgp_busy(wgp_busy), .wgp_done(wgp_done), .wgp_error(wgp_error),
    .irq(irq), .cycle_out(cycle)
  );

  // ---------------------------------------------------------------- WGP
  wire         wgp_mem_req;
  wire         wgp_mem_we;
  wire [31:0]  wgp_mem_addr;
  wire [1023:0] wgp_mem_wdata;
  reg  [1023:0] wgp_mem_rdata;
  reg          wgp_mem_ready;

  wgp u_wgp (
    .clk(clk), .rst_n(rst_n),
    .start(wgp_start), .grid_x(grid_x), .wg_size(wg_size), .arg_ptr(arg_ptr),
    .busy(wgp_busy), .done(wgp_done), .error(wgp_error), .waves_done(waves_done),
    .ic_we(ic_we), .ic_addr(ic_addr), .ic_wdata(ic_wdata),
    .mem_req(wgp_mem_req), .mem_we(wgp_mem_we), .mem_addr(wgp_mem_addr),
    .mem_wdata(wgp_mem_wdata), .mem_rdata(wgp_mem_rdata), .mem_ready(wgp_mem_ready),
    .cycle(cycle)
  );

  // ---------------------------------------------------------------- memory arbiter
  reg        arb_busy;
  reg        arb_owner; // 0 = CP, 1 = WGP
  reg [31:0] arb_addr;
  reg        arb_we;
  reg [1023:0] arb_wdata;
  reg [1:0]  arb_cool;

  wire       axi_req;
  wire       axi_we;
  wire [31:0] axi_addr;
  wire [1023:0] axi_wdata;
  wire [1023:0] axi_rdata;
  wire       axi_ready;

  assign axi_req   = arb_busy & ~axi_ready;
  assign axi_we    = arb_we;
  assign axi_addr  = arb_addr;
  assign axi_wdata = arb_wdata;

  always @(posedge clk) begin
    if (!rst_n) begin
      arb_busy  <= 1'b0;
      arb_cool  <= 2'd0;
      arb_owner <= 1'b0;
      arb_addr  <= 32'd0;
      arb_we    <= 1'b0;
      arb_wdata <= 1024'd0;
      cp_mem_ready <= 1'b0;
      wgp_mem_ready<= 1'b0;
      cp_mem_rdata <= 1024'd0;
      wgp_mem_rdata<= 1024'd0;
    end else begin
      cp_mem_ready  <= 1'b0;
      wgp_mem_ready <= 1'b0;

      if (arb_cool != 2'd0) begin
        arb_cool <= arb_cool - 2'd1;
      end else if (!arb_busy) begin
        if (cp_mem_req) begin
          arb_owner <= 1'b0;
          arb_addr  <= cp_mem_addr;
          arb_we    <= cp_mem_we;
          arb_wdata <= cp_mem_wdata;
          arb_busy  <= 1'b1;
        end else if (wgp_mem_req) begin
          arb_owner <= 1'b1;
          arb_addr  <= wgp_mem_addr;
          arb_we    <= wgp_mem_we;
          arb_wdata <= wgp_mem_wdata;
          arb_busy  <= 1'b1;
        end
      end else if (axi_ready) begin
        arb_busy <= 1'b0;
        arb_cool <= 2'd2;
        if (arb_owner == 1'b0) begin
          cp_mem_ready  <= 1'b1;
          cp_mem_rdata  <= axi_rdata;
        end else begin
          wgp_mem_ready <= 1'b1;
          wgp_mem_rdata <= axi_rdata;
        end
      end
    end
  end

  // ---------------------------------------------------------------- AXI4 master
  axi_master u_axi (
    .clk(clk), .rst_n(rst_n),
    .req(axi_req), .we(axi_we), .addr(axi_addr), .wdata(axi_wdata),
    .rdata(axi_rdata), .ready(axi_ready),
    .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen),
    .m_axi_awsize(m_axi_awsize), .m_axi_awburst(m_axi_awburst),
    .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
    .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb),
    .m_axi_wlast(m_axi_wlast), .m_axi_wvalid(m_axi_wvalid),
    .m_axi_wready(m_axi_wready),
    .m_axi_bresp(m_axi_bresp), .m_axi_bvalid(m_axi_bvalid),
    .m_axi_bready(m_axi_bready),
    .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen),
    .m_axi_arsize(m_axi_arsize), .m_axi_arburst(m_axi_arburst),
    .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
    .m_axi_rdata(m_axi_rdata), .m_axi_rresp(m_axi_rresp),
    .m_axi_rlast(m_axi_rlast), .m_axi_rvalid(m_axi_rvalid),
    .m_axi_rready(m_axi_rready)
  );

endmodule
