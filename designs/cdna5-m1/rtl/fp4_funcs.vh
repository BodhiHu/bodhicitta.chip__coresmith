// Copyright (c) 2026 CDNA5-M1 project.
// SPDX-License-Identifier: MIT
//
// fp4_funcs.vh -- MXFP4 (E2M1) decode and dot-product functions.
// Include this file *inside* a module (Verilog-2005 functions are module
// scoped). The M1 decodes E2M1 to the exact integer sequence
// {0,1,2,3,4,6,8,12} (2x scale); products are therefore 4x the real product
// and the consumer removes that scale.

// E2M1 -> signed 5-bit integer, scaled by 2.
function automatic signed [4:0] fp4_to_i5;
  input [3:0] v;
  reg [2:0] mag;
  reg signed [4:0] out;
  begin
    mag = v[2:0];
    case (mag)
      3'd0: out = 5'sd0;
      3'd1: out = 5'sd1;   // 0.5
      3'd2: out = 5'sd2;   // 1.0
      3'd3: out = 5'sd3;   // 1.5
      3'd4: out = 5'sd4;   // 2.0
      3'd5: out = 5'sd6;   // 3.0
      3'd6: out = 5'sd8;   // 4.0
      3'd7: out = 5'sd12;  // 6.0
    endcase
    fp4_to_i5 = v[3] ? -out : out;
  end
endfunction

// 8-way FP4 dot product: sum of 8 signed products (low nibble first).
function automatic signed [31:0] dot8_fp4;
  input [31:0] a;
  input [31:0] b;
  integer k;
  reg signed [4:0] av, bv;
  reg signed [9:0] prod;
  reg signed [31:0] acc;
  begin
    acc = 32'sd0;
    for (k = 0; k < 8; k = k + 1) begin
      av = fp4_to_i5(a[k*4 +: 4]);
      bv = fp4_to_i5(b[k*4 +: 4]);
      prod = av * bv;
      acc = acc + {{22{prod[9]}}, prod};
    end
    dot8_fp4 = acc;
  end
endfunction

// 4-way signed int8 dot product.
function automatic signed [31:0] dot4_i8;
  input [31:0] a;
  input [31:0] b;
  integer k;
  reg signed [7:0] av, bv;
  reg signed [15:0] p8;
  reg signed [31:0] acc;
  begin
    acc = 32'sd0;
    for (k = 0; k < 4; k = k + 1) begin
      av = a[k*8 +: 8];
      bv = b[k*8 +: 8];
      p8 = av * bv;
      acc = acc + {{16{p8[15]}}, p8};
    end
    dot4_i8 = acc;
  end
endfunction

// Signed 4x4 MXFP4 product (decoded E2M1, 2x scale each) -> 10-bit.
function automatic signed [9:0] fp4_mul;
  input [3:0] a;
  input [3:0] b;
  reg signed [4:0] av, bv;
  begin
    av = fp4_to_i5(a);
    bv = fp4_to_i5(b);
    fp4_mul = av * bv; // 10-bit context widens the 5x5 product
  end
endfunction

function automatic signed [31:0] fp4_mul32;
  input [3:0] a;
  input [3:0] b;
  reg signed [9:0] p;
  begin
    p = fp4_mul(a, b);
    fp4_mul32 = {{22{p[9]}}, p};
  end
endfunction
