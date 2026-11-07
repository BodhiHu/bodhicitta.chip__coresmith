// Copyright (c) 2026 CDNA5-M1 project.
// SPDX-License-Identifier: MIT
//
// axi_master.v -- AXI4 master for the M1 chip.  Converts the internal
// 128-byte block interface (32 x 32-bit words) into 8-beat INCR bursts of
// 128-bit data.  One outstanding transaction; the M1 memory system is a
// bring-up single-channel controller.

`include "cdna5_m1_defs.vh"

module axi_master (
  input  wire         clk,
  input  wire         rst_n,

  // internal block interface
  input  wire         req,
  input  wire         we,
  input  wire [31:0]  addr,
  input  wire [1023:0] wdata,
  output reg  [1023:0] rdata,
  output reg          ready,

  // AXI4 master
  output reg  [31:0]  m_axi_awaddr,
  output reg  [7:0]   m_axi_awlen,
  output reg  [2:0]   m_axi_awsize,
  output reg  [1:0]   m_axi_awburst,
  output reg          m_axi_awvalid,
  input  wire         m_axi_awready,
  output wire [127:0] m_axi_wdata,
  output wire [15:0]  m_axi_wstrb,
  output wire         m_axi_wlast,
  output reg          m_axi_wvalid,
  input  wire         m_axi_wready,
  input  wire [1:0]   m_axi_bresp,
  input  wire         m_axi_bvalid,
  output reg          m_axi_bready,
  output reg  [31:0]  m_axi_araddr,
  output reg  [7:0]   m_axi_arlen,
  output reg  [2:0]   m_axi_arsize,
  output reg  [1:0]   m_axi_arburst,
  output reg          m_axi_arvalid,
  input  wire         m_axi_arready,
  input  wire [127:0] m_axi_rdata,
  input  wire [1:0]   m_axi_rresp,
  input  wire         m_axi_rlast,
  input  wire         m_axi_rvalid,
  output reg          m_axi_rready
);

  localparam S_IDLE = 3'd0;
  localparam S_AR   = 3'd1;
  localparam S_R    = 3'd2;
  localparam S_AW   = 3'd3;
  localparam S_W    = 3'd4;
  localparam S_B    = 3'd5;

  reg [2:0]  state;
  reg [31:0] cur_addr;
  reg [1023:0] wbuf;
  reg [3:0]  beat;
  reg [127:0] rbuf [0:7];

  assign m_axi_wdata = wbuf[beat*128 +: 128];
  assign m_axi_wstrb = 16'hffff;
  assign m_axi_wlast = (beat == 4'd7);

  always @(posedge clk) begin
    if (!rst_n) begin
      state <= S_IDLE;
      ready <= 1'b0;
      rdata <= 1024'd0;
      cur_addr <= 32'd0;
      wbuf <= 1024'd0;
      beat <= 4'd0;
      m_axi_awaddr <= 32'd0;
      m_axi_awlen <= 8'd7;
      m_axi_awsize <= 3'd4;
      m_axi_awburst <= 2'b01;
      m_axi_awvalid <= 1'b0;
      m_axi_wvalid <= 1'b0;
      m_axi_bready <= 1'b0;
      m_axi_araddr <= 32'd0;
      m_axi_arlen <= 8'd7;
      m_axi_arsize <= 3'd4;
      m_axi_arburst <= 2'b01;
      m_axi_arvalid <= 1'b0;
      m_axi_rready <= 1'b0;
    end else begin
      ready <= 1'b0;

      case (state)
        S_IDLE: begin
          m_axi_awvalid <= 1'b0;
          m_axi_wvalid  <= 1'b0;
          m_axi_bready  <= 1'b0;
          m_axi_arvalid <= 1'b0;
          m_axi_rready  <= 1'b0;
          if (req) begin
            cur_addr <= addr;
            beat     <= 4'd0;
            if (we) begin
              wbuf          <= wdata;
              m_axi_awaddr  <= addr;
              m_axi_awlen   <= 8'd7;
              m_axi_awsize  <= 3'd4;
              m_axi_awburst <= 2'b01;
              m_axi_awvalid <= 1'b1;
              state         <= S_AW;
            end else begin
              m_axi_araddr  <= addr;
              m_axi_arlen   <= 8'd7;
              m_axi_arsize  <= 3'd4;
              m_axi_arburst <= 2'b01;
              m_axi_arvalid <= 1'b1;
              state         <= S_AR;
            end
          end
        end

        S_AR: begin
          if (m_axi_arready) begin
            m_axi_arvalid <= 1'b0;
            m_axi_rready  <= 1'b1;
            beat          <= 4'd0;
            state         <= S_R;
          end
        end

        S_R: begin
          if (m_axi_rvalid) begin
            rbuf[beat[2:0]] <= m_axi_rdata;
            if (m_axi_rlast) begin
              m_axi_rready <= 1'b0;
              rdata <= {m_axi_rdata, rbuf[6], rbuf[5], rbuf[4], rbuf[3],
                        rbuf[2], rbuf[1], rbuf[0]};
              ready <= 1'b1;
              state <= S_IDLE;
            end else begin
              beat <= beat + 4'd1;
            end
          end
        end

        S_AW: begin
          if (m_axi_awready) begin
            m_axi_awvalid <= 1'b0;
            m_axi_wvalid  <= 1'b1;
            beat          <= 4'd0;
            state         <= S_W;
          end
        end

        S_W: begin
          if (m_axi_wready) begin
            if (beat == 4'd7) begin
              m_axi_wvalid <= 1'b0;
              m_axi_bready <= 1'b1;
              state        <= S_B;
            end else begin
              beat <= beat + 4'd1;
            end
          end
        end

        S_B: begin
          if (m_axi_bvalid) begin
            m_axi_bready <= 1'b0;
            ready <= 1'b1;
            state <= S_IDLE;
          end
        end

        default: state <= S_IDLE;
      endcase
    end
  end

endmodule
