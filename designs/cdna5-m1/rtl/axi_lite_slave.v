// Copyright (c) 2026 CDNA5-M1 project.
// SPDX-License-Identifier: MIT
//
// axi_lite_slave.v -- AXI4-Lite slave for the M1 host control interface.
// AW and W are captured independently and the CSR write fires once when both
// are present, which removes the same-cycle ready/write race that a
// single-cycle wready pulse creates for a polling host.

module axi_lite_slave (
  input  wire        clk,
  input  wire        rst_n,

  input  wire [31:0] s_axil_awaddr,
  input  wire        s_axil_awvalid,
  output reg         s_axil_awready,
  input  wire [31:0] s_axil_wdata,
  input  wire [3:0]  s_axil_wstrb,
  input  wire        s_axil_wvalid,
  output reg         s_axil_wready,
  output reg  [1:0]  s_axil_bresp,
  output reg         s_axil_bvalid,
  input  wire        s_axil_bready,
  input  wire [31:0] s_axil_araddr,
  input  wire        s_axil_arvalid,
  output reg         s_axil_arready,
  output reg  [31:0] s_axil_rdata,
  output reg  [1:0]  s_axil_rresp,
  output reg         s_axil_rvalid,
  input  wire        s_axil_rready,

  output reg         csr_wr,
  output reg  [7:0]  csr_waddr,
  output reg  [31:0] csr_wdata,
  output reg         csr_rd,
  output wire [7:0]  csr_raddr,
  input  wire [31:0] csr_rdata
);

  reg        aw_got, w_got;
  reg [31:0] awaddr_lat, wdata_lat;
  reg        rvalid_r;

  assign csr_raddr = s_axil_araddr[7:0];

  always @(posedge clk) begin
    if (!rst_n) begin
      s_axil_awready <= 1'b0;
      s_axil_wready  <= 1'b0;
      s_axil_bresp   <= 2'b00;
      s_axil_bvalid  <= 1'b0;
      s_axil_arready <= 1'b0;
      s_axil_rdata   <= 32'd0;
      s_axil_rresp   <= 2'b00;
      s_axil_rvalid  <= 1'b0;
      csr_wr         <= 1'b0;
      csr_waddr      <= 8'd0;
      csr_wdata      <= 32'd0;
      csr_rd         <= 1'b0;
      aw_got         <= 1'b0;
      w_got          <= 1'b0;
      awaddr_lat     <= 32'd0;
      wdata_lat      <= 32'd0;
      rvalid_r       <= 1'b0;
    end else begin
      csr_wr <= 1'b0;
      csr_rd <= 1'b0;

      // ---- AW
      s_axil_awready <= (!aw_got && !s_axil_bvalid);
      if (s_axil_awready && s_axil_awvalid) begin
        awaddr_lat <= s_axil_awaddr;
        aw_got     <= 1'b1;
      end

      // ---- W
      s_axil_wready <= (!w_got && !s_axil_bvalid);
      if (s_axil_wready && s_axil_wvalid) begin
        wdata_lat <= s_axil_wdata;
        w_got     <= 1'b1;
      end

      // ---- commit
      if (aw_got && w_got && !s_axil_bvalid) begin
        csr_wr        <= 1'b1;
        csr_waddr     <= awaddr_lat[7:0];
        csr_wdata     <= wdata_lat;
        s_axil_bvalid <= 1'b1;
        s_axil_bresp  <= 2'b00;
        aw_got        <= 1'b0;
        w_got         <= 1'b0;
      end

      if (s_axil_bvalid && s_axil_bready) s_axil_bvalid <= 1'b0;

      // ---- read
      s_axil_arready <= !s_axil_rvalid;
      if (s_axil_arready && s_axil_arvalid) begin
        s_axil_rdata  <= csr_rdata;
        s_axil_rresp  <= 2'b00;
        s_axil_rvalid <= 1'b1;
        csr_rd        <= 1'b1;
      end
      if (s_axil_rvalid && s_axil_rready) s_axil_rvalid <= 1'b0;
    end
  end

endmodule
