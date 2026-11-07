// Copyright (c) 2026 CDNA5-M1 project.
// SPDX-License-Identifier: MIT
//
// softmax_engine.v -- serialized row-wise Softmax over the LDS linear port.
//
// Input/output format: signed Q4.12 (input logits), unsigned Q0.12 (output
// probabilities; the row sums to 4096 = 1.0).  The engine reads the row from
// LDS, finds the max, computes exp2(x-max) with the SFU, sums, divides once,
// and writes the normalized row back.  It is a WGP-level AI block: it owns
// the LDS linear port while busy, like the WMMA and TDM engines.
//
// The block is deliberately serial (one 16-bit element per SFU command) so it
// stays small; a 32-element row costs roughly 32*5 cycles per pass.  It is the
// RTL softmax primitive used by the operator model; it is not yet wired to a
// scalar instruction in simd32/wgp (see spec/AI_SCOPE.md).
`timescale 1ns/1ps
`default_nettype none

module softmax_engine (
  input  wire        clk,
  input  wire        rst_n,

  input  wire        start,
  input  wire [9:0]  base_word,   // LDS word address of the row
  input  wire [6:0]  len,         // number of 16-bit elements, 2..64, even
  output reg         busy,
  output reg         done,

  // LDS linear port
  output reg         lds_req,
  output reg         lds_we,
  output reg  [9:0]  lds_addr,
  output reg  [31:0] lds_wdata,
  input  wire [31:0] lds_rdata,
  input  wire        lds_ready
);

  localparam [3:0] S_IDLE   = 4'd0;
  localparam [3:0] S_MAX_RD = 4'd1;
  localparam [3:0] S_MAX_WT = 4'd2;
  localparam [3:0] S_EXP_RD = 4'd3;
  localparam [3:0] S_EXP_WT = 4'd4;
  localparam [3:0] S_SFU_ST = 4'd5;
  localparam [3:0] S_SFU_WT = 4'd6;
  localparam [3:0] S_EXP_WR = 4'd7;
  localparam [3:0] S_NORM_RD = 4'd8;
  localparam [3:0] S_NORM_WT = 4'd9;
  localparam [3:0] S_NORM_WR = 4'd10;
  localparam [3:0] S_DONE    = 4'd11;
  localparam [3:0] S_DIV     = 4'd12;

  reg [3:0]  state;
  reg [6:0]  idx;
  reg [9:0]  base_r;
  reg [6:0]  len_r;
  reg [15:0] max_r;
  reg [31:0] rdata_r;
  reg [15:0] cur_r;
  reg [15:0] sfu_x;
  reg [19:0] sum_r;
  reg [31:0] inv_sum;
  reg [31:0] div_rem;
  reg [24:0] div_quot;
  reg [4:0]  div_bit;
  reg [15:0] exp_r;

  wire [15:0] cur = idx[0] ? rdata_r[31:16] : rdata_r[15:0];
  wire [15:0] cur_now = idx[0] ? lds_rdata[31:16] : lds_rdata[15:0];
  wire signed [16:0] diff = $signed({cur_now[15], cur_now}) -
                            $signed({max_r[15], max_r});
  wire [15:0] diff_clamped = (diff < -17'sd32768) ? 16'h8000 : diff[15:0];
  wire [31:0] w_keep = idx[0] ? {exp_r, rdata_r[15:0]} : {rdata_r[31:16], exp_r};

  // exp2 / reciprocal primitive (4-cycle latency, valid/ready).
  wire        sfu_start;
  wire [15:0] sfu_y;
  wire        sfu_busy, sfu_done;

  sfu u_sfu (
    .clk(clk), .rst_n(rst_n),
    .start(sfu_start), .op(2'd0), .x(sfu_x), .y(sfu_y),
    .busy(sfu_busy), .done(sfu_done)
  );

  assign sfu_start = (state == S_SFU_ST);

  // One restoring division per row: inv_sum = 2^24 / sum (25 cycles).  This
  // replaces the former combinational 32/20 divider, which made ABC run for
  // minutes on the WGP.
  wire [31:0] div_rem_shift = (div_rem << 1) | (div_bit == 5'd24 ? 32'd1 : 32'd0);
  wire [31:0] div_rem_next  = (div_rem_shift >= {12'd0, sum_r})
                              ? (div_rem_shift - {12'd0, sum_r}) : div_rem_shift;
  wire        div_sub       = (div_rem_shift >= {12'd0, sum_r});
  wire [24:0] div_quot_next = div_quot |
                              (div_sub ? (25'd1 << div_bit) : 25'd0);

  wire [47:0] norm_prod = {32'd0, cur} * {16'd0, inv_sum};
  wire [47:0] norm_shift = norm_prod >> 12;
  wire [15:0] norm_val = (norm_shift > 48'd4095) ? 16'd4095 : norm_shift[15:0];

  always @(posedge clk) begin
    if (!rst_n) begin
      state    <= S_IDLE;
      idx      <= 7'd0;
      base_r   <= 10'd0;
      len_r    <= 7'd0;
      max_r    <= 16'h8000;
      rdata_r  <= 16'd0;
      cur_r    <= 16'd0;
      sfu_x    <= 16'd0;
      sum_r    <= 20'd0;
      exp_r    <= 16'd0;
      inv_sum  <= 32'd0;
      div_rem  <= 32'd0;
      div_quot <= 25'd0;
      div_bit  <= 5'd24;
      busy     <= 1'b0;
      done     <= 1'b0;
      lds_req  <= 1'b0;
      lds_we   <= 1'b0;
      lds_addr <= 10'd0;
      lds_wdata<= 32'd0;
    end else begin
      done    <= 1'b0;
      lds_req <= 1'b0;
      lds_we  <= 1'b0;

      case (state)
        S_IDLE: begin
          if (start) begin
            base_r <= base_word;
            len_r  <= len;
            idx    <= 7'd0;
            max_r  <= 16'h8000;
            sum_r  <= 20'd0;
            busy   <= 1'b1;
            state  <= S_MAX_RD;
          end
        end

        S_MAX_RD: begin
          lds_req  <= 1'b1;
          lds_we   <= 1'b0;
          lds_addr <= base_r + {3'd0, idx[6:1]};
          state    <= S_MAX_WT;
        end

        S_MAX_WT: begin
          if (lds_ready) begin
            rdata_r <= lds_rdata;
            if ($signed({cur_now[15], cur_now}) >
                $signed({max_r[15], max_r})) max_r <= cur_now;
            if (idx + 7'd1 >= len_r) begin
              idx   <= 7'd0;
              state <= S_EXP_RD;
            end else begin
              idx   <= idx + 7'd1;
              state <= S_MAX_RD;
            end
          end
        end

        S_EXP_RD: begin
          lds_req  <= 1'b1;
          lds_we   <= 1'b0;
          lds_addr <= base_r + {3'd0, idx[6:1]};
          state    <= S_EXP_WT;
        end

        S_EXP_WT: begin
          // Capture the read word, then start the SFU with (x - max).
          if (lds_ready) begin
            rdata_r <= lds_rdata;
            sfu_x   <= diff_clamped;
            state   <= S_SFU_ST;
          end
        end

        S_SFU_ST: state <= S_SFU_WT;

        S_SFU_WT: begin
          if (sfu_done) begin
            exp_r <= sfu_y;
            state <= S_EXP_WR;
          end
        end

        S_EXP_WR: begin
          lds_req   <= 1'b1;
          lds_we    <= 1'b1;
          lds_addr  <= base_r + {3'd0, idx[6:1]};
          lds_wdata <= w_keep;
          sum_r     <= sum_r + {4'd0, sfu_y};
          if (idx + 7'd1 >= len_r) begin
            idx      <= 7'd0;
            div_rem  <= 32'd0;
            div_quot <= 25'd0;
            div_bit  <= 5'd24;
            state    <= S_DIV;
          end else begin
            idx   <= idx + 7'd1;
            state <= S_EXP_RD;
          end
        end

        S_DIV: begin
          if (sum_r == 20'd0) begin
            inv_sum <= 32'd0;
            state   <= S_NORM_RD;
          end else begin
            div_rem  <= div_rem_next;
            div_quot <= div_quot_next;
            if (div_bit == 5'd0) begin
              inv_sum <= {7'd0, div_quot_next};
              state   <= S_NORM_RD;
            end else begin
              div_bit <= div_bit - 5'd1;
            end
          end
        end

        S_NORM_RD: begin
          lds_req  <= 1'b1;
          lds_we   <= 1'b0;
          lds_addr <= base_r + {3'd0, idx[6:1]};
          state    <= S_NORM_WT;
        end

        S_NORM_WT: begin
          if (lds_ready) begin
            rdata_r <= lds_rdata;
            state   <= S_NORM_WR;
          end
        end

        S_NORM_WR: begin
          lds_req   <= 1'b1;
          lds_we    <= 1'b1;
          lds_addr  <= base_r + {3'd0, idx[6:1]};
          lds_wdata <= idx[0] ? {norm_val, rdata_r[15:0]}
                              : {rdata_r[31:16], norm_val};
          if (idx + 7'd1 >= len_r) begin
            state <= S_DONE;
          end else begin
            idx   <= idx + 7'd1;
            state <= S_NORM_RD;
          end
        end

        S_DONE: begin
          done  <= 1'b1;
          busy  <= 1'b0;
          state <= S_IDLE;
        end

        default: state <= S_IDLE;
      endcase
    end
  end

endmodule

`default_nettype wire
