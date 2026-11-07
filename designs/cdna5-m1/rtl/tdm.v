// Copyright (c) 2026 CDNA5-M1 project.
// SPDX-License-Identifier: MIT
//
// tdm.v -- Tensor Data Mover, bring-up 1-D contiguous subset of the CDNA5
// TDM.  Copies `len` 32-bit words (multiple of 32, <= 256) from a 128-byte
// aligned global address to an LDS word address.  A production TDM takes a
// 5-D descriptor from SGPRs, bounds-checks it, and supports multicast; the
// address generation and LDS/DRAM path here are the same.

`include "cdna5_m1_defs.vh"

module tdm (
  input  wire         clk,
  input  wire         rst_n,

  input  wire         start,
  input  wire [31:0]  src,
  input  wire [9:0]   dst,
  input  wire [8:0]   len,       // words
  output reg          busy,
  output reg          done,

  // global memory block port
  output reg          gmem_req,
  output wire [31:0]  gmem_addr,
  input  wire [1023:0] gmem_rdata,
  input  wire         gmem_ready,

  // LDS linear port
  output reg          lds_req,
  output reg          lds_we,
  output reg  [9:0]   lds_addr,
  output reg  [1023:0] lds_wdata,
  input  wire         lds_ready
);

  localparam S_IDLE = 3'd0;
  localparam S_GRD  = 3'd1;
  localparam S_LWR  = 3'd2;
  localparam S_DONE = 3'd3;

  reg [2:0]  state;
  reg [31:0] cur_src;
  reg [9:0]  cur_dst;
  reg [8:0]  remain;   // words remaining
  reg [1023:0] blk_buf;

  assign gmem_addr = cur_src;

  always @(posedge clk) begin
    if (!rst_n) begin
      state    <= S_IDLE;
      busy     <= 1'b0;
      done     <= 1'b0;
      gmem_req <= 1'b0;
      lds_req  <= 1'b0;
      lds_we   <= 1'b0;
      lds_addr <= 10'd0;
      lds_wdata<= 1024'd0;
      cur_src  <= 32'd0;
      cur_dst  <= 10'd0;
      remain   <= 9'd0;
      blk_buf      <= 1024'd0;
    end else begin
      done <= 1'b0;

      case (state)
        S_IDLE: begin
          busy <= 1'b0;
          lds_req  <= 1'b0;
          lds_we   <= 1'b0;
          gmem_req <= 1'b0;
          if (start) begin
            cur_src  <= src;
            cur_dst  <= dst;
            remain   <= len;
            busy     <= 1'b1;
            gmem_req <= 1'b1;
            state    <= S_GRD;
          end
        end

        S_GRD: begin
          if (gmem_ready) begin
            blk_buf      <= gmem_rdata;
            gmem_req <= 1'b0;
            lds_req  <= 1'b1;
            lds_we   <= 1'b1;
            lds_addr <= cur_dst;
            lds_wdata<= gmem_rdata;
            state    <= S_LWR;
          end
        end

        S_LWR: begin
          if (lds_ready) begin
            lds_req <= 1'b0;
            lds_we  <= 1'b0;
            if (remain <= 9'd32) begin
              busy  <= 1'b0;
              done  <= 1'b1;
              state <= S_DONE;
            end else begin
              remain  <= remain - 9'd32;
              cur_src <= cur_src + 32'd128;
              cur_dst <= cur_dst + 10'd32;
              gmem_req<= 1'b1;
              state   <= S_GRD;
            end
          end
        end

        S_DONE: state <= S_IDLE;

        default: state <= S_IDLE;
      endcase
    end
  end

endmodule
