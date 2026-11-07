// Copyright (c) 2026 CDNA5-M1 project.
// SPDX-License-Identifier: MIT
//
// tb_sfu.v -- self-checking testbench for rtl/sfu.v.
//
// Checks, for every input code:
//   exp2: x signed Q4.12 in [-8.0, 0.0], y unsigned Q0.12,
//         |y/4096 - 2^x| <= 2e-3.
//   rcp : x unsigned Q1.15 in [0.5, 2.0], y unsigned Q1.15,
//         |y/32768 - 1/x| / (1/x) <= 1e-3.
// Also checks the valid/ready handshake (start/busy), the one-cycle done
// pulse, 4..8 cycle latency, ignore-start-while-busy, synchronous reset,
// and holding start high across a completion (back-to-back acceptance).
//
// Run: /opt/eda/oss-cad-suite/bin/iverilog -g2005 -Irtl -o tb_sfu.vvp \
//          rtl/sfu.v tb/tb_sfu.v && vvp tb_sfu.vvp
// The final line is exactly "PASS" on success (scripts/check_sfu.sh greps it).

`timescale 1ns/1ps

module tb_sfu;

  reg         clk;
  reg         rst_n;
  reg         start;
  reg  [1:0]  op;
  reg  [15:0] x;
  wire [15:0] y;
  wire        busy;
  wire        done;

  integer errors;
  integer exp_checks;
  integer rcp_checks;
  integer exp_fails;
  integer rcp_fails;
  integer min_lat;
  integer max_lat;
  real    max_exp_err;
  real    max_rcp_err;
  integer worst_exp_code;
  integer worst_rcp_code;

  // ------------------------------------------------------------------
  // DUT
  // ------------------------------------------------------------------
  sfu dut (
    .clk   (clk),
    .rst_n (rst_n),
    .start (start),
    .op    (op),
    .x     (x),
    .y     (y),
    .busy  (busy),
    .done  (done)
  );

  always #5 clk = ~clk;   // 100 MHz

  // ------------------------------------------------------------------
  // One command: drive start for one cycle, wait for done, return y and
  // the accept->done latency in clock cycles.
  // ------------------------------------------------------------------
  task automatic run_op (
    input  [1:0]  op_i,
    input  [15:0] x_i,
    output [15:0] y_o,
    output integer lat
  );
    integer c;
    begin
      @(negedge clk);
      if (busy !== 1'b0) begin
        errors = errors + 1;
        if (errors < 16)
          $display("FAIL: busy asserted in idle (t=%0t)", $time);
      end
      start = 1'b1;
      op    = op_i;
      x     = x_i;

      @(posedge clk);
      #1;
      if (busy !== 1'b1) begin
        errors = errors + 1;
        if (errors < 16)
          $display("FAIL: busy did not assert after start (t=%0t)", $time);
      end

      @(negedge clk);
      start = 1'b0;

      c = 0;
      while ((done !== 1'b1) && (c < 20)) begin
        @(posedge clk);
        #1;
        c = c + 1;
      end

      if (done !== 1'b1) begin
        errors = errors + 1;
        if (errors < 16)
          $display("FAIL: done timeout op=%0d x=0x%04h (t=%0t)",
                   op_i, x_i, $time);
      end

      y_o = y;
      lat = c;

      if ((^y_o) === 1'bx) begin
        errors = errors + 1;
        if (errors < 16)
          $display("FAIL: X on y op=%0d x=0x%04h (t=%0t)",
                   op_i, x_i, $time);
      end

      @(posedge clk);
      #1;
      if (done !== 1'b0) begin
        errors = errors + 1;
        if (errors < 16)
          $display("FAIL: done is not a one-cycle pulse (t=%0t)", $time);
      end

      if ((lat < 4) || (lat > 8)) begin
        errors = errors + 1;
        if (errors < 16)
          $display("FAIL: latency %0d outside 4..8 op=%0d x=0x%04h",
                   lat, op_i, x_i);
      end
      if (lat < min_lat) min_lat = lat;
      if (lat > max_lat) max_lat = lat;
    end
  endtask

  // ------------------------------------------------------------------
  // Stimulus
  // ------------------------------------------------------------------
  integer code;
  integer i;
  integer lat;
  integer c;
  reg [15:0] xin;
  reg [15:0] yout;
  real xv;
  real ref;
  real got;
  real err;

  initial begin
    clk   = 1'b0;
    rst_n = 1'b0;
    start = 1'b0;
    op    = 2'd0;
    x     = 16'd0;

    errors        = 0;
    exp_checks    = 0;
    rcp_checks    = 0;
    exp_fails     = 0;
    rcp_fails     = 0;
    min_lat       = 999;
    max_lat       = 0;
    max_exp_err   = 0.0;
    max_rcp_err   = 0.0;
    worst_exp_code = 0;
    worst_rcp_code = 0;

    // ---------------- reset (active-low synchronous) ----------------
    repeat (3) @(negedge clk);
    if ((busy !== 1'b0) || (done !== 1'b0) || (y !== 16'd0)) begin
      errors = errors + 1;
      $display("FAIL: outputs not cleared by synchronous reset");
    end
    rst_n = 1'b1;
    @(negedge clk);
    if ((busy !== 1'b0) || (done !== 1'b0)) begin
      errors = errors + 1;
      $display("FAIL: busy/done not idle after reset release");
    end

    // ---------------- exp2 exhaustive sweep: x in [-8, 0] ----------------
    for (code = -32768; code <= 0; code = code + 1) begin
      xin = code;                       // 16-bit two's complement
      run_op(2'd0, xin, yout, lat);
      xv  = code / 4096.0;
      ref = 2.0 ** xv;
      got = yout / 4096.0;
      err = (got > ref) ? (got - ref) : (ref - got);
      exp_checks = exp_checks + 1;
      if (yout > 16'd4095) begin
        exp_fails = exp_fails + 1;
        if (exp_fails <= 8)
          $display("FAIL: exp2 output out of range x=0x%04h y=%0d", xin, yout);
      end
      if (err > max_exp_err) begin
        max_exp_err    = err;
        worst_exp_code = code;
      end
      if (err > 0.002) begin
        exp_fails = exp_fails + 1;
        if (exp_fails <= 8)
          $display("FAIL: exp2 x=0x%04h (%.6f) ref=%.8f got=%.8f err=%.8f",
                   xin, xv, ref, got, err);
      end
    end

    // ---------------- rcp exhaustive sweep: x in [0.5, 2.0] ----------------
    // Q1.15: 0x4000 = 0.5, 0x8000 = 1.0, 0xFFFF = 1.99997.
    for (code = 16'h4000; code <= 16'hFFFF; code = code + 1) begin
      xin = code;
      run_op(2'd1, xin, yout, lat);
      xv  = code / 32768.0;
      ref = 1.0 / xv;
      got = yout / 32768.0;
      err = ((got > ref) ? (got - ref) : (ref - got)) / ref;
      rcp_checks = rcp_checks + 1;
      if (err > max_rcp_err) begin
        max_rcp_err    = err;
        worst_rcp_code = code;
      end
      if (err > 0.001) begin
        rcp_fails = rcp_fails + 1;
        if (rcp_fails <= 8)
          $display("FAIL: rcp x=0x%04h (%.8f) ref=%.8f got=%.8f rel=%.8f",
                   xin, xv, ref, got, err);
      end
    end

    // ---------------- directed: ignore start while busy ----------------
    // First command exp2(-1.0) -> y = 2048.  A second start is pulsed while
    // busy and must not be accepted; the first result must survive.
    @(negedge clk);
    start = 1'b1;
    op    = 2'd0;
    x     = 16'hF000;                    // -1.0
    @(posedge clk);
    #1;
    @(negedge clk);
    start = 1'b0;

    @(negedge clk);
    start = 1'b1;
    op    = 2'd1;
    x     = 16'h4000;                    // rcp(0.5)
    @(posedge clk);
    #1;
    if (busy !== 1'b1) begin
      errors = errors + 1;
      $display("FAIL: busy dropped while a command was in flight");
    end
    @(negedge clk);
    start = 1'b0;

    c = 0;
    while ((done !== 1'b1) && (c < 12)) begin
      @(posedge clk);
      #1;
      c = c + 1;
    end
    if (done !== 1'b1) begin
      errors = errors + 1;
      $display("FAIL: no done after ignore-while-busy test");
    end
    if (y !== 16'd2048) begin
      errors = errors + 1;
      $display("FAIL: start while busy was accepted (y=%0d, expected 2048)",
               y);
    end
    @(posedge clk);
    #1;
    if (done !== 1'b0) begin
      errors = errors + 1;
      $display("FAIL: spuriously re-asserted done after ignored start");
    end
    repeat (3) begin
      @(posedge clk);
      #1;
      if (done !== 1'b0) begin
        errors = errors + 1;
        $display("FAIL: unexpected second completion after ignored start");
      end
    end

    // ---------------- directed: synchronous reset mid-operation ----------
    @(negedge clk);
    start = 1'b1;
    op    = 2'd1;
    x     = 16'h6000;                    // rcp(0.75)
    @(posedge clk);
    #1;
    @(negedge clk);
    start = 1'b0;
    @(negedge clk);
    rst_n = 1'b0;
    @(posedge clk);
    #1;
    if ((busy !== 1'b0) || (done !== 1'b0) || (y !== 16'd0)) begin
      errors = errors + 1;
      $display("FAIL: synchronous reset did not clear busy/done/y");
    end
    @(negedge clk);
    rst_n = 1'b1;
    @(negedge clk);
    if ((busy !== 1'b0) || (done !== 1'b0)) begin
      errors = errors + 1;
      $display("FAIL: block not idle after reset release");
    end

    // ---------------- directed: start held high across completion ---------
    // start stays high; after the first done the block is ready again, so
    // the next rising edge must accept a second command.
    @(negedge clk);
    start = 1'b1;
    op    = 2'd0;
    x     = 16'hE000;                    // exp2(-2.0) = 0.25 -> 1024
    c = 0;
    while ((done !== 1'b1) && (c < 12)) begin
      @(posedge clk);
      #1;
      c = c + 1;
    end
    if (done !== 1'b1) begin
      errors = errors + 1;
      $display("FAIL: no done in held-start back-to-back test");
    end
    if (y !== 16'd1024) begin
      errors = errors + 1;
      $display("FAIL: held-start first result y=%0d expected 1024", y);
    end
    @(posedge clk);
    #1;
    if (busy !== 1'b1) begin
      errors = errors + 1;
      $display("FAIL: held-high start was not accepted when ready");
    end
    @(negedge clk);
    start = 1'b0;
    c = 0;
    while ((done !== 1'b1) && (c < 12)) begin
      @(posedge clk);
      #1;
      c = c + 1;
    end
    if ((done !== 1'b1) || (y !== 16'd1024)) begin
      errors = errors + 1;
      $display("FAIL: held-start second command result wrong (y=%0d)", y);
    end
    @(posedge clk);
    #1;

    // ---------------- summary -------------------------------------------
    errors = errors + exp_fails + rcp_fails;

    $display("");
    $display("sfu self-check: exp2 %0d vectors, rcp %0d vectors",
             exp_checks, rcp_checks);
    $display("  exp2 max abs error : %.6f (limit 0.002000), worst code 0x%04h",
             max_exp_err, worst_exp_code[15:0]);
    $display("  rcp  max rel error : %.6f (limit 0.001000), worst code 0x%04h",
             max_rcp_err, worst_rcp_code[15:0]);
    $display("  latency            : min %0d, max %0d cycles (limit 4..8)",
             min_lat, max_lat);
    $display("  handshake          : start/busy valid-ready, one-cycle done");

    if (errors == 0) begin
      $display("");
      $display("PASS");
    end else begin
      $display("");
      $display("FAIL: %0d check(s) failed", errors);
    end
    $display("");
    $finish;
  end

  // Safety timeout: the exhaustive sweep is ~0.5 M cycles (5 ms).
  initial begin
    #20000000;                           // 20 ms
    $display("FAIL: global timeout");
    $finish;
  end

endmodule
