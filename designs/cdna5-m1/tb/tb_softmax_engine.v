// Copyright (c) 2026 CDNA5-M1 project.
// SPDX-License-Identifier: MIT
//
// tb_softmax_engine.v -- self-checking test for the serialized LDS softmax.
`timescale 1ns/1ps
`default_nettype none

module tb_softmax_engine;
  reg clk = 0;
  reg rst_n = 0;
  reg start = 0;
  reg [9:0] base_word = 0;
  reg [6:0] len = 0;
  wire busy, done;
  wire lds_req, lds_we;
  wire [9:0] lds_addr;
  wire [31:0] lds_wdata;
  wire [31:0] lds_rdata;
  wire lds_ready = 1'b1;

  reg [31:0] mem [0:1023];
  integer errors = 0;
  integer i;
  integer sum;
  integer first, other;

  always #5 clk = ~clk;

  always @(posedge clk) begin
    if (lds_req && lds_we && lds_ready) mem[lds_addr] <= lds_wdata;
  end
  assign lds_rdata = mem[lds_addr];

  softmax_engine dut (
    .clk(clk), .rst_n(rst_n),
    .start(start), .base_word(base_word), .len(len),
    .busy(busy), .done(done),
    .lds_req(lds_req), .lds_we(lds_we), .lds_addr(lds_addr),
    .lds_wdata(lds_wdata), .lds_rdata(lds_rdata), .lds_ready(lds_ready)
  );

  task automatic set_elem(input integer word, input integer idx, input [15:0] v);
    reg [31:0] w;
    begin
      w = mem[word];
      if (idx[0]) w[31:16] = v;
      else        w[15:0]  = v;
      mem[word] = w;
    end
  endtask

  function automatic [15:0] get_elem(input integer word, input integer idx);
    get_elem = idx[0] ? mem[word][31:16] : mem[word][15:0];
  endfunction

  task automatic run_row(input integer base, input integer n);
    begin
      base_word = base[9:0];
      len = n[6:0];
      @(posedge clk); start = 1;
      @(posedge clk); start = 0;
      while (!done) @(posedge clk);
      @(posedge clk);
    end
  endtask

  task automatic check_sum(input integer base, input integer n, input integer lo,
                            input integer hi);
    begin
      sum = 0;
      for (i = 0; i < n; i = i + 1) sum = sum + get_elem(base + i / 2, i);
      if (sum < lo || sum > hi) begin
        $display("FAIL: row sum %0d outside [%0d,%0d]", sum, lo, hi);
        errors = errors + 1;
      end else begin
        $display("  row sum %0d in [%0d,%0d]  OK", sum, lo, hi);
      end
    end
  endtask

  initial begin
    for (i = 0; i < 1024; i = i + 1) mem[i] = 32'd0;
    repeat (3) @(posedge clk);
    rst_n = 1;
    repeat (2) @(posedge clk);

    // Equal logits (all 0): softmax = 1/32 each => Q0.12 ~ 128, sum ~4096.
    for (i = 0; i < 32; i = i + 1) set_elem(100, i, 16'h0000);
    run_row(100, 32);
    check_sum(100, 32, 4000, 4200);
    for (i = 0; i < 32; i = i + 1) begin
      if (get_elem(100 + i / 2, i) < 120 || get_elem(100 + i / 2, i) > 136) begin
        $display("FAIL: equal-logit element %0d = %0d", i, get_elem(100 + i / 2, i));
        errors = errors + 1;
      end
    end

    // One-hot logits: max 4.0 (0x4000), others 0.  First element must dominate.
    for (i = 0; i < 32; i = i + 1) set_elem(200, i, 16'h0000);
    set_elem(200, 0, 16'h4000);
    run_row(200, 32);
    check_sum(200, 32, 4000, 4200);
    first = get_elem(200, 0);
    other = get_elem(200 + 1 / 2, 1);
    if (first <= other || first < 1000 || other > 200) begin
      $display("FAIL: one-hot first=%0d other=%0d", first, other);
      errors = errors + 1;
    end else begin
      $display("  one-hot first=%0d other=%0d  OK", first, other);
    end

    // Equal negative logits (all -4.0): same as the all-zero case.
    for (i = 0; i < 32; i = i + 1) set_elem(300, i, 16'hC000);
    run_row(300, 32);
    check_sum(300, 32, 4000, 4200);

    if (errors == 0) begin
      $display("PASS: softmax_engine");
      $finish;
    end else begin
      $display("FAIL: softmax_engine (%0d errors)", errors);
      $finish;
    end
  end

  initial begin
    #200000;
    $display("FAIL: timeout");
    $finish;
  end
endmodule

`default_nettype wire
