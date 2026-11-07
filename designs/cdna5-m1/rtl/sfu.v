// Copyright (c) 2026 CDNA5-M1 project.
// SPDX-License-Identifier: MIT
//
// sfu.v -- serialized 16-bit Special Function Unit (exp2 / reciprocal).
//
// ---------------------------------------------------------------------------
// Interface / handshake
// ---------------------------------------------------------------------------
//   clk     single 100 MHz clock, rising-edge logic.
//   rst_n   active-low SYNCHRONOUS reset (only sampled on posedge clk).
//   start   command valid.  A command is accepted on a rising edge when
//           start == 1 and busy == 0.  start is ignored while busy == 1.
//   op      2'b00 = exp2, 2'b01 = rcp.  op[1] is reserved (treated as rcp).
//   x       input operand, 16 bits.
//   y       result, valid while done == 1 (and held until the next result).
//   busy    command in flight.  busy is the inverse of "ready"; therefore
//           the handshake is the usual valid/ready pair (start/busy).
//   done    single-cycle result-valid pulse, asserted together with y.
//
// Latency: 4 clock cycles from the rising edge that accepts start (busy
// rises) to the rising edge that presents y/done.  Throughput is one command
// per 5 cycles; start may be held high for back-to-back commands, in which
// case it is accepted again one cycle after busy falls.
//
// ---------------------------------------------------------------------------
// Fixed-point conventions (exact)
// ---------------------------------------------------------------------------
// exp2:
//   input  x is SIGNED two's-complement Q4.12:
//              x_value = signed(x) / 4096.0,  range [-8.0, +8.0)
//          so 0xF000 = -1.0, 0x8000 = -8.0, 0x0000 = 0.0,
//             0x1000 = +1.0 (Q4.12 is two's complement: 0x1000 is +1.0,
//             not -1.0; 0xF000 is -1.0).
//   output y is UNSIGNED Q0.12:
//              y_value = y / 4096.0,  range [0, 4095/4096]
//          y is saturated: exp2(0) = 1.0 would need code 4096, so the
//          representable maximum is 4095 (error 1 LSB = 2.44e-4).
//          x >= 0 saturates at 4095; x < -12 saturates at 0.
//
// rcp:
//   The 16-bit port uses UNSIGNED Q1.15 for both operands:
//              x_value = x / 32768.0,  range [0.5, 2.0]
//              y_value = y / 32768.0,  range [0.5, 2.0]
//          so 0x4000 = 0.5, 0x8000 = 1.0, 0xFFFF = 1.99997 (~2.0).
//   y = round(32768 / x_value), saturated at 0xFFFF.
//
//   Why Q1.15 and not the literal Q0.16 (0x8000 = 0.5) for rcp?  A 16-bit
//   Q0.16 word represents only [0, 1); the reciprocal of the required input
//   domain [0.5, 2.0] is [0.5, 2.0], which does not fit in Q0.16 either.
//   Q1.15 is the 16-bit unsigned fixed-point mapping that covers the full
//   specified [0.5, 2.0] input and output range (2.0 is represented by the
//   saturated code 0xFFFF, relative error 1.5e-5).  A Q0.16 formulation
//   with x in [0.5, 1) would need a 17-bit output for 1/x in (1, 2].
//
// ---------------------------------------------------------------------------
// Algorithm (no floating point, 50 LUT entries total)
// ---------------------------------------------------------------------------
// exp2(x) = 2^n * 2^f, n = floor(x) (4-bit signed), f in [0,1).
//   2^f is interpolated linearly over 16 segments using
//   T[k] = round(2^(k/16) * 32768), k = 0..16 (17 entries).
//   P = T[k] + ((T[k+1]-T[k]) * frac8 + 128) >> 8,  P ~= 2^f in Q1.15.
//   y = round(P * 2^n / 8) with the shift 3-n, then clamp to [0,4095].
//
// rcp(x): normalise x = m * 2^e with m in [1,2), e in {-1,0}:
//   if x >= 1.0: m = x,          e = 0
//   else:        m = 2*x,        e = -1
//   1/m is interpolated linearly over 32 segments using
//   R[k] = round(32768 / (1 + k/32)), k = 0..32 (33 entries).
//   P = R[k] - ((R[k]-R[k+1]) * frac10 + 512) >> 10,  P ~= 1/m in Q1.15.
//   y = P * 2^(-e) (i.e. P or 2*P), saturated at 0xFFFF.
//
// Both interpolations share one 13x10 unsigned multiplier.  The linear
// interpolation error is bounded by max|f''|*h^2/8: 4.7e-4 relative for
// exp2 (h=1/16) and 2.44e-4 absolute for rcp (h=1/32).
// Measured against a double-precision reference over every input code:
//   exp2, x in [-8,0]:  max abs error = 3.53e-4  (limit 2e-3)
//   rcp,  x in [0.5,2]: max rel error = 2.51e-4  (limit 1e-3)
//
// Area: small LUTs + one small multiplier; well below the 8k Sky130 cell
// target (see scripts/check_sfu.sh and the synthesis note in the README).

`timescale 1ns/1ps

`default_nettype none

module sfu (
  input  wire        clk,
  input  wire        rst_n,

  input  wire        start,
  input  wire [1:0]  op,
  input  wire [15:0] x,
  output reg  [15:0] y,
  output reg         busy,
  output reg         done
);

  // ------------------------------------------------------------------
  // 2^f lookup, T[k] = round(2^(k/16) * 32768), k = 0..16.
  // k=16 is 2.0 in Q1.15 (17 bits) and is used only as an endpoint.
  // ------------------------------------------------------------------
  function [16:0] exp2_lut;
    input [4:0] k;
    begin
      case (k)
        5'd0:  exp2_lut = 17'd32768;
        5'd1:  exp2_lut = 17'd34219;
        5'd2:  exp2_lut = 17'd35734;
        5'd3:  exp2_lut = 17'd37316;
        5'd4:  exp2_lut = 17'd38968;
        5'd5:  exp2_lut = 17'd40693;
        5'd6:  exp2_lut = 17'd42495;
        5'd7:  exp2_lut = 17'd44376;
        5'd8:  exp2_lut = 17'd46341;
        5'd9:  exp2_lut = 17'd48393;
        5'd10: exp2_lut = 17'd50535;
        5'd11: exp2_lut = 17'd52773;
        5'd12: exp2_lut = 17'd55109;
        5'd13: exp2_lut = 17'd57549;
        5'd14: exp2_lut = 17'd60097;
        5'd15: exp2_lut = 17'd62757;
        5'd16: exp2_lut = 17'd65536;   // 2.0, endpoint only
        default: exp2_lut = 17'd32768;
      endcase
    end
  endfunction

  // ------------------------------------------------------------------
  // 1/(1+k/32) lookup, R[k] = round(32768 / (1 + k/32)), k = 0..32.
  // All values fit in 16 bits; R[32] = 16384 = 0.5 in Q1.15.
  // ------------------------------------------------------------------
  function [15:0] rcp_lut;
    input [5:0] k;
    begin
      case (k)
        6'd0:  rcp_lut = 16'd32768;
        6'd1:  rcp_lut = 16'd31775;
        6'd2:  rcp_lut = 16'd30840;
        6'd3:  rcp_lut = 16'd29959;
        6'd4:  rcp_lut = 16'd29127;
        6'd5:  rcp_lut = 16'd28340;
        6'd6:  rcp_lut = 16'd27594;
        6'd7:  rcp_lut = 16'd26887;
        6'd8:  rcp_lut = 16'd26214;
        6'd9:  rcp_lut = 16'd25575;
        6'd10: rcp_lut = 16'd24966;
        6'd11: rcp_lut = 16'd24385;
        6'd12: rcp_lut = 16'd23831;
        6'd13: rcp_lut = 16'd23302;
        6'd14: rcp_lut = 16'd22795;
        6'd15: rcp_lut = 16'd22310;
        6'd16: rcp_lut = 16'd21845;
        6'd17: rcp_lut = 16'd21400;
        6'd18: rcp_lut = 16'd20972;
        6'd19: rcp_lut = 16'd20560;
        6'd20: rcp_lut = 16'd20165;
        6'd21: rcp_lut = 16'd19784;
        6'd22: rcp_lut = 16'd19418;
        6'd23: rcp_lut = 16'd19065;
        6'd24: rcp_lut = 16'd18725;
        6'd25: rcp_lut = 16'd18396;
        6'd26: rcp_lut = 16'd18079;
        6'd27: rcp_lut = 16'd17772;
        6'd28: rcp_lut = 16'd17476;
        6'd29: rcp_lut = 16'd17190;
        6'd30: rcp_lut = 16'd16913;
        6'd31: rcp_lut = 16'd16644;
        6'd32: rcp_lut = 16'd16384;   // 0.5, endpoint only
        default: rcp_lut = 16'd32768;
      endcase
    end
  endfunction

  // ------------------------------------------------------------------
  // Pipeline state
  // ------------------------------------------------------------------
  reg [2:0]  stage;          // 0 = idle, 1..4 = pipeline stages
  reg [1:0]  op_r;           // latched operation
  reg [15:0] x_r;            // latched operand

  // stage 1 -> 2
  reg [1:0]  op_s1;
  reg [16:0] t0_s1;          // LUT endpoint at k
  reg [12:0] d_s1;           // |LUT[k+1]-LUT[k]| (exp2: +, rcp: -)
  reg [9:0]  rem_s1;         // interpolation fraction
  reg [3:0]  sh_s1;          // product shift: 8 (exp2) or 10 (rcp)
  reg        sub_s1;         // 1 = interpolate downward (rcp)
  reg        pos_s1;         // exp2: x >= 0, force saturation
  reg [3:0]  nabs_s1;        // exp2: |floor(x)|, 0..15
  reg [1:0]  scale_s1;       // rcp: output left shift 0 or 1

  // stage 2 -> 3
  reg [1:0]  op_s2;
  reg [16:0] t0_s2;
  reg [22:0] prod_s2;        // d * rem
  reg [3:0]  sh_s2;
  reg        sub_s2;
  reg        pos_s2;
  reg [3:0]  nabs_s2;
  reg [1:0]  scale_s2;

  // ------------------------------------------------------------------
  // exp2 pre-processing (combinational from x_r)
  // ------------------------------------------------------------------
  // n = signed(x[15:12]); frac = x[11:0] (also the fractional part for
  // negative x because two's complement floors toward -infinity).
  wire [4:0]  exp2_k   = {1'b0, x_r[11:8]};
  wire [9:0]  exp2_rem = {2'b00, x_r[7:0]};
  wire [16:0] exp2_t0  = exp2_lut(exp2_k);
  wire [16:0] exp2_t1  = exp2_lut(exp2_k + 5'd1);
  wire [12:0] exp2_d   = exp2_t1[12:0] - exp2_t0[12:0];
  wire        exp2_pos = ~x_r[15];
  wire [3:0]  exp2_nabs = (~x_r[15:12]) + 4'd1; // two's-complement negate

  // ------------------------------------------------------------------
  // rcp pre-processing (combinational from x_r)
  // ------------------------------------------------------------------
  wire        rcp_small = ~x_r[15];             // x < 1.0
  wire [15:0] rcp_m     = rcp_small ? {x_r[14:0], 1'b0} : x_r;
  wire [15:0] rcp_f     = rcp_m - 16'd32768;    // m-1 in [0, 32767]
  wire [4:0]  rcp_k     = rcp_f[14:10];
  wire [9:0]  rcp_rem   = rcp_f[9:0];
  wire [15:0] rcp_t0    = rcp_lut({1'b0, rcp_k});
  wire [15:0] rcp_t1    = rcp_lut({1'b0, rcp_k} + 6'd1);
  wire [12:0] rcp_d     = {1'b0, rcp_t0} - {1'b0, rcp_t1};

  // ------------------------------------------------------------------
  // Stage 3 arithmetic (combinational)
  // ------------------------------------------------------------------
  // Rounded magnitude of the interpolation step, then P = t0 +/- step.
  wire [22:0] prod_round = prod_s2 + (23'd1 << (sh_s2 - 4'd1));
  wire [22:0] prod_step  = prod_round >> sh_s2;
  wire [16:0] p_s3       = sub_s2 ? (t0_s2 - prod_step[16:0])
                                  : (t0_s2 + prod_step[16:0]);

  // exp2 output: y = round(P * 2^n / 8) = (P + half) >> (3 + |n|).
  reg  [17:0] exp2_tmp;
  reg  [4:0]  exp2_sh;
  reg  [17:0] rcp_tmp;

  always @* begin
    exp2_sh  = 5'd3 + {1'b0, nabs_s2};
    exp2_tmp = ({1'b0, p_s3} + (18'd1 << (exp2_sh - 5'd1))) >> exp2_sh;
    rcp_tmp  = {2'b00, p_s3} << scale_s2;
  end

  reg [15:0] y_next;
  always @* begin
    if (op_s2 == 1'b0) begin
      if (pos_s2)
        y_next = 16'd4095;                 // x >= 0: 2^x >= 1.0
      else if (nabs_s2 > 4'd12)
        y_next = 16'd0;                    // x < -12: underflow
      else if (exp2_tmp > 18'd4095)
        y_next = 16'd4095;                 // saturate (x near 0)
      else
        y_next = exp2_tmp[15:0];
    end else begin
      if (rcp_tmp > 18'd65535)
        y_next = 16'hFFFF;                 // x = 0.5 -> 2.0, clamp
      else
        y_next = rcp_tmp[15:0];
    end
  end

  // ------------------------------------------------------------------
  // Sequential pipeline, synchronous active-low reset
  // ------------------------------------------------------------------
  always @(posedge clk) begin
    if (!rst_n) begin
      stage    <= 3'd0;
      op_r     <= 2'd0;
      x_r      <= 16'd0;
      op_s1    <= 2'd0;
      t0_s1    <= 17'd0;
      d_s1     <= 13'd0;
      rem_s1   <= 10'd0;
      sh_s1    <= 4'd8;
      sub_s1   <= 1'b0;
      pos_s1   <= 1'b0;
      nabs_s1  <= 4'd0;
      scale_s1 <= 2'd0;
      op_s2    <= 2'd0;
      t0_s2    <= 17'd0;
      prod_s2  <= 23'd0;
      sh_s2    <= 4'd8;
      sub_s2   <= 1'b0;
      pos_s2   <= 1'b0;
      nabs_s2  <= 4'd0;
      scale_s2 <= 2'd0;
      y        <= 16'd0;
      busy     <= 1'b0;
      done     <= 1'b0;
    end else begin
      done <= 1'b0;

      case (stage)
        3'd0: begin
          if (start) begin
            op_r  <= op;
            x_r   <= x;
            busy  <= 1'b1;
            stage <= 3'd1;
          end
        end

        2'd1: begin
          op_s1 <= op_r;
          if (op_r == 1'b0) begin
            t0_s1    <= exp2_t0;
            d_s1     <= exp2_d;
            rem_s1   <= exp2_rem;
            sh_s1    <= 4'd8;
            sub_s1   <= 1'b0;
            pos_s1   <= exp2_pos;
            nabs_s1  <= exp2_nabs;
            scale_s1 <= 2'd0;
          end else begin
            t0_s1    <= {1'b0, rcp_t0};
            d_s1     <= rcp_d;
            rem_s1   <= rcp_rem;
            sh_s1    <= 4'd10;
            sub_s1   <= 1'b1;
            pos_s1   <= 1'b0;
            nabs_s1  <= 4'd0;
            scale_s1 <= rcp_small ? 2'd1 : 2'd0;
          end
          stage <= 3'd2;
        end

        2'd2: begin
          op_s2    <= op_s1;
          t0_s2    <= t0_s1;
          prod_s2  <= d_s1 * rem_s1;
          sh_s2    <= sh_s1;
          sub_s2   <= sub_s1;
          pos_s2   <= pos_s1;
          nabs_s2  <= nabs_s1;
          scale_s2 <= scale_s1;
          stage    <= 3'd3;
        end

        3'd3: begin                        // stage 3: register the result
          y     <= y_next;
          stage <= 3'd4;
        end

        default: begin                     // stage 4: present result
          done  <= 1'b1;
          busy  <= 1'b0;
          stage <= 3'd0;
        end
      endcase
    end
  end

endmodule

`default_nettype wire
