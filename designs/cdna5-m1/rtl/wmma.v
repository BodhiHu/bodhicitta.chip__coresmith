// Copyright (c) 2026 CDNA5-M1 project.
// SPDX-License-Identifier: MIT
//
// wmma.v -- M1 matrix core: C[16][16] (int32) = A[16][32] x B[32][16],
// A and B are MXFP4 (E2M1) nibbles packed two per byte.  Peaks at
// 512 FP4 MACs/cycle (2 K-slices x 256 outputs), i.e. 102.4 GFLOP/s at
// 100 MHz -- the 0.1 TFLOP/s headline of the CDNA5-M1.
//
// Operands are LDS-resident (a CDNA5 WMMA takes VGPR operands; the M1
// bring-up stages them through the TDM/LDS path, which is the same data
// movement, just earlier in the pipeline).
//
// LDS layout (32-bit word addresses):
//   A: 64 words, row-major nibbles, 16 rows x 16 bytes  (32 nibbles/row)
//   B: 64 words, row-major nibbles, 32 rows x  8 bytes  (16 nibbles/row)
//   C: 256 words, row-major int32, 16 rows x 16 words
// A/B/C bases must be 32-word aligned.

`include "cdna5_m1_defs.vh"


  function automatic signed [4:0] w_fp4_to_i5;
    input [3:0] v;
    reg [2:0] mag;
    reg signed [4:0] out;
    begin
      mag = v[2:0];
      case (mag)
        3'd0: out = 5'sd0;  3'd1: out = 5'sd1;  3'd2: out = 5'sd2;
        3'd3: out = 5'sd3;  3'd4: out = 5'sd4;  3'd5: out = 5'sd6;
        3'd6: out = 5'sd8;  3'd7: out = 5'sd12;
      endcase
      w_fp4_to_i5 = v[3] ? -out : out;
    end
  endfunction

  function automatic signed [9:0] w_fp4_mul;
    input [3:0] a;
    input [3:0] b;
    reg signed [4:0] av, bv;
    begin
      av = w_fp4_to_i5(a);
      bv = w_fp4_to_i5(b);
      w_fp4_mul = av * bv;
    end
  endfunction

  function automatic signed [31:0] w_fp4_mul32;
    input [3:0] a;
    input [3:0] b;
    reg signed [9:0] p;
    begin
      p = w_fp4_mul(a, b);
      w_fp4_mul32 = {{22{p[9]}}, p};
    end
  endfunction

module wmma (
  input  wire         clk,
  input  wire         rst_n,

  input  wire         start,
  input  wire [9:0]   a_base,
  input  wire [9:0]   b_base,
  input  wire [9:0]   c_base,
  output reg          busy,
  output reg          done,

  // LDS linear port
  output reg          lds_req,
  output reg          lds_we,
  output reg  [9:0]   lds_addr,
  output reg  [1023:0] lds_wdata,
  input  wire [1023:0] lds_rdata,
  input  wire         lds_ready
);

  localparam S_IDLE = 3'd0;
  localparam S_LA   = 3'd1;
  localparam S_COMP = 3'd2;
  localparam S_ST   = 3'd3;
  localparam S_DONE = 3'd4;
  localparam S_LW   = 3'd5;

  reg [2:0]  state;
  reg [9:0]  base_a, base_b, base_c;
  reg [1:0]  ld_blk;     // 0..3: A0, A1, B0, B1
  reg [4:0]  kstep;
  reg [3:0]  st_cnt;

  reg [3:0]  a_mat [0:511]; // a_mat[i*32 + k]
  reg [3:0]  b_mat [0:511]; // b_mat[k*16 + j]
  reg signed [31:0] acc [0:255]; // acc[i*16 + j]

  integer i, j, n, w, t, idx;
  reg signed [10:0] psum;

  wire [4:0] k0 = {kstep[3:0], 1'b0};
  wire [4:0] k1 = k0 + 5'd1;

  reg signed [4:0] av0 [0:15];
  reg signed [4:0] av1 [0:15];
  reg signed [4:0] bv0 [0:31];
  reg signed [4:0] bv1 [0:31];
  integer ai, bj;

  always @* begin
    for (ai = 0; ai < 16; ai = ai + 1) begin
      av0[ai] = w_fp4_to_i5(a_mat[ai*32 + k0]);
      av1[ai] = w_fp4_to_i5(a_mat[ai*32 + k1]);
    end
    for (bj = 0; bj < 32; bj = bj + 1) begin
      bv0[bj] = w_fp4_to_i5(b_mat[k0*16 + bj]);
      bv1[bj] = w_fp4_to_i5(b_mat[k1*16 + bj]);
    end
  end

  // C words for the current 32-word store beat
  // Store beat: C words st_cnt*32 .. st_cnt*32+31 are a contiguous slice of
  // acc[0..255].  Indexing with st_cnt[2:0] keeps this an 8:1 mux per word
  // instead of a 256:1 mux (which is what a synthesizer builds if it cannot
  // prove the range).
  reg [31:0] c_word [0:31];
  integer ci;
  always @* begin
    for (ci = 0; ci < 32; ci = ci + 1)
      c_word[ci] = acc[{1'b0, st_cnt[2:0]} * 32 + ci];
  end

  // Combinational linear-port driver
  always @* begin
    lds_req  = 1'b0;
    lds_we   = 1'b0;
    lds_addr = 10'd0;
    lds_wdata= 1024'd0;

    case (state)
      S_LA: begin
        lds_req = 1'b1;
        lds_we  = 1'b0;
        case (ld_blk)
          2'd0: lds_addr = base_a;
          2'd1: lds_addr = base_a + 10'd32;
          2'd2: lds_addr = base_b;
          default: lds_addr = base_b + 10'd32;
        endcase
      end
      S_ST: begin
        lds_req = 1'b1;
        lds_we  = 1'b1;
        lds_addr = base_c + {st_cnt, 5'b0};
        lds_wdata = {c_word[31], c_word[30], c_word[29], c_word[28],
                     c_word[27], c_word[26], c_word[25], c_word[24],
                     c_word[23], c_word[22], c_word[21], c_word[20],
                     c_word[19], c_word[18], c_word[17], c_word[16],
                     c_word[15], c_word[14], c_word[13], c_word[12],
                     c_word[11], c_word[10], c_word[9],  c_word[8],
                     c_word[7],  c_word[6],  c_word[5],  c_word[4],
                     c_word[3],  c_word[2],  c_word[1],  c_word[0]};
      end
      default: begin end
    endcase
  end

  // ---------------------------------------------------------------- FSM
  always @(posedge clk) begin
    if (!rst_n) begin
      state  <= S_IDLE;
      busy   <= 1'b0;
      done   <= 1'b0;
      base_a <= 10'd0;
      base_b <= 10'd0;
      base_c <= 10'd0;
      ld_blk <= 2'd0;
      kstep  <= 5'd0;
      st_cnt <= 4'd0;
    end else begin
      done <= 1'b0;

      case (state)
        S_IDLE: begin
          busy <= 1'b0;
          if (start) begin
            base_a <= a_base;
            base_b <= b_base;
            base_c <= c_base;
            ld_blk <= 2'd0;
            kstep  <= 5'd0;
            st_cnt <= 4'd0;
            busy   <= 1'b1;
            state  <= S_LA;
          end
        end

        S_LA: begin
          if (lds_ready) begin
            case (ld_blk)
              2'd0: begin
                for (t = 0; t < 32; t = t + 1)
                  for (idx = 0; idx < 8; idx = idx + 1)
                    a_mat[t*8 + idx] <= lds_rdata[t*32 + idx*4 +: 4];
                ld_blk <= 2'd1;
                state  <= S_LW;
              end
              2'd1: begin
                for (t = 0; t < 32; t = t + 1)
                  for (idx = 0; idx < 8; idx = idx + 1)
                    a_mat[256 + t*8 + idx] <= lds_rdata[t*32 + idx*4 +: 4];
                ld_blk <= 2'd2;
                state  <= S_LW;
              end
              2'd2: begin
                for (t = 0; t < 32; t = t + 1)
                  for (idx = 0; idx < 8; idx = idx + 1)
                    b_mat[t*8 + idx] <= lds_rdata[t*32 + idx*4 +: 4];
                ld_blk <= 2'd3;
                state  <= S_LW;
              end
              default: begin
                for (t = 0; t < 32; t = t + 1)
                  for (idx = 0; idx < 8; idx = idx + 1)
                    b_mat[256 + t*8 + idx] <= lds_rdata[t*32 + idx*4 +: 4];
                state <= S_COMP;
              end
            endcase
          end
        end

        S_LW: begin
          state <= S_LA;
        end

        S_COMP: begin
          for (i = 0; i < 16; i = i + 1) begin
            for (j = 0; j < 16; j = j + 1) begin
              // One 11-bit sum of the two K-slice products, then one 32-bit
              // accumulate.  Sharing the add tree here keeps the synthesized
              // area linear in MACs instead of duplicating a 32-bit adder per
              // product.
              psum = w_fp4_mul(a_mat[i*32 + k0], b_mat[k0*16 + j])
                   + w_fp4_mul(a_mat[i*32 + k1], b_mat[k1*16 + j]);
              if (kstep == 5'd0) acc[i*16+j] <= psum;
              else               acc[i*16+j] <= acc[i*16+j] + psum;
            end
          end
          if (kstep == 5'd15) begin
            st_cnt <= 4'd0;
            state  <= S_ST;
          end else begin
            kstep <= kstep + 5'd1;
          end
        end

        S_ST: begin
          if (lds_ready) begin
            if (st_cnt == 4'd7) begin
              state <= S_DONE;
            end else begin
              st_cnt <= st_cnt + 4'd1;
            end
          end
        end

        S_DONE: begin
          busy  <= 1'b0;
          done  <= 1'b1;
          state <= S_IDLE;
        end

        default: state <= S_IDLE;
      endcase
    end
  end

endmodule
