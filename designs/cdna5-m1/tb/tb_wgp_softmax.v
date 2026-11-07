// Copyright (c) 2026 CDNA5-M1 project.
// SPDX-License-Identifier: MIT
//
// tb_wgp_softmax.v -- full WGP path: preloaded I$, S_SOFTMAX scalar command,
// LDS softmax engine, wave completion.  The LDS is preloaded directly because
// the bring-up TDM path is tested separately.
`timescale 1ns/1ps
`default_nettype none

module tb_wgp_softmax;
  reg clk = 0;
  reg rst_n = 0;
  reg start = 0;
  reg [7:0] grid_x = 1;
  reg [15:0] wg_size = 32;
  reg [31:0] arg_ptr = 0;
  wire busy, done, error;
  wire [7:0] waves_done;
  reg ic_we = 0;
  reg [7:0] ic_addr = 0;
  reg [31:0] ic_wdata = 0;
  wire mem_req, mem_we;
  wire [31:0] mem_addr;
  wire [1023:0] mem_wdata;
  reg [1023:0] mem_rdata = 0;
  reg mem_ready = 0;
  reg [63:0] cycle = 0;

  integer errors = 0;
  integer i, sum, first, other;

  always #5 clk = ~clk;
  always @(posedge clk) cycle <= cycle + 1;

  wgp dut (
    .clk(clk), .rst_n(rst_n), .start(start), .grid_x(grid_x),
    .wg_size(wg_size), .arg_ptr(arg_ptr), .busy(busy), .done(done),
    .error(error), .waves_done(waves_done),
    .ic_we(ic_we), .ic_addr(ic_addr), .ic_wdata(ic_wdata),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr),
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ready(mem_ready),
    .cycle(cycle)
  );

  task automatic wr_instr(input integer a, input [31:0] w);
    begin
      ic_we = 1; ic_addr = a[7:0]; ic_wdata = w;
      @(posedge clk);
    end
  endtask

  task automatic load_program;
    begin
      // s5 = 0 (base word), s6 = 32 (elements)
      wr_instr(0, (32'h01 << 26) | (1 << 25) | (5 << 20)); // MOV s5, lit
      wr_instr(1, 32'd0);
      wr_instr(2, (32'h01 << 26) | (1 << 25) | (6 << 20)); // MOV s6, lit
      wr_instr(3, 32'd32);
      wr_instr(4, (32'h18 << 26) | (5 << 20));             // S_SOFTMAX s5
      wr_instr(5, (32'h0C << 26));                          // ENDPGM
      ic_we = 0;
      @(posedge clk);
    end
  endtask

  task automatic set_word(input integer w, input [31:0] v);
    begin
      dut.u_lds.mem[w[4:0]][w[9:5]] = v;
    end
  endtask

  function automatic [31:0] get_word(input integer w);
    get_word = dut.u_lds.mem[w[4:0]][w[9:5]];
  endfunction

  function automatic [15:0] get_elem(input integer w, input integer idx);
    get_elem = idx[0] ? (get_word(w) >> 16) : (get_word(w) & 32'h0000ffff);
  endfunction

  task automatic run;
    begin
      @(posedge clk); start = 1;
      @(posedge clk); start = 0;
      while (!done) @(posedge clk);
      @(posedge clk);
    end
  endtask

  task automatic check_equal;
    begin
      for (i = 0; i < 16; i = i + 1) set_word(i, 32'd0);
      run();
      sum = 0;
      for (i = 0; i < 32; i = i + 1) sum = sum + get_elem(i / 2, i);
      if (sum < 4000 || sum > 4200) begin
        $display("FAIL: equal row sum %0d", sum); errors = errors + 1;
      end
      for (i = 0; i < 32; i = i + 1)
        if (get_elem(i / 2, i) < 120 || get_elem(i / 2, i) > 136) begin
          $display("FAIL: equal element %0d = %0d", i, get_elem(i / 2, i));
          errors = errors + 1;
        end
      $display("  equal: sum=%0d  OK", sum);
    end
  endtask

  task automatic check_onehot;
    begin
      for (i = 0; i < 16; i = i + 1) set_word(i, 32'd0);
      set_word(0, 32'h0000_4000);
      run();
      first = get_elem(0, 0);
      other = get_elem(0, 1);
      sum = 0;
      for (i = 0; i < 32; i = i + 1) sum = sum + get_elem(i / 2, i);
      if (first < 1000 || other > 200 || sum < 4000 || sum > 4200) begin
        $display("FAIL: one-hot first=%0d other=%0d sum=%0d", first, other, sum);
        errors = errors + 1;
      end else begin
        $display("  one-hot: first=%0d other=%0d sum=%0d  OK", first, other, sum);
      end
    end
  endtask

  initial begin
    repeat (3) @(posedge clk);
    rst_n = 1;
    repeat (2) @(posedge clk);
    load_program();
    check_equal();
    rst_n = 0; repeat (2) @(posedge clk); rst_n = 1;
    check_onehot();
    if (errors == 0) $display("PASS: wgp softmax path");
    else             $display("FAIL: wgp softmax path (%0d errors)", errors);
    $finish;
  end

  initial begin
    #500000;
    $display("FAIL: timeout");
    $finish;
  end
endmodule

`default_nettype wire
