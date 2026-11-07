// Copyright (c) 2026 CDNA5-M1 project.
// SPDX-License-Identifier: MIT
//
// wgp.v -- one CDNA5-M1 Work-Group Processor: 1 CU (2 x SIMD32), 1 KB
// instruction RAM with two read ports, 4 KB LDS, one matrix core and one TDM.
//
// The M1 WGP is a scaled CDNA5 WGP: the real part has 2 CUs (4 SIMD32), 320 KB
// LDS, 64 KB I$, 16 KB K$ and 2 matrix cores.  The M1 ships one CU to land
// exactly on 0.1 TFLOP/s MXFP4 at 100 MHz.

`include "cdna5_m1_defs.vh"

module wgp (
  input  wire         clk,
  input  wire         rst_n,

  // launch from the command processor
  input  wire         start,
  input  wire [7:0]   grid_x,
  input  wire [15:0]  wg_size,
  input  wire [31:0]  arg_ptr,
  output reg          busy,
  output reg          done,
  output reg          error,
  output reg  [7:0]   waves_done,

  // instruction-RAM fill port (from CP)
  input  wire         ic_we,
  input  wire [7:0]   ic_addr,
  input  wire [31:0]  ic_wdata,

  // global memory block port
  output wire         mem_req,
  output wire         mem_we,
  output wire [31:0]  mem_addr,
  output wire [1023:0] mem_wdata,
  input  wire [1023:0] mem_rdata,
  input  wire         mem_ready,

  input  wire [63:0]  cycle
);

  // ---------------------------------------------------------------- I$
  reg [31:0] icmem [0:255];
  wire [7:0] imem_addr0, imem_addr1;
  wire [31:0] imem_data0 = icmem[imem_addr0];
  wire [31:0] imem_data1 = icmem[imem_addr1];

  always @(posedge clk) begin
    if (ic_we) icmem[ic_addr] <= ic_wdata;
  end

  // ---------------------------------------------------------------- SIMDs
  reg         launch0, launch1;
  reg  [15:0] wg_id0, wg_id1;
  wire        busy0, busy1, done0, done1, err0, err1;

  wire        lds_req0, lds_we0, lds_rdy0, lds_cfl0;
  wire [1023:0] lds_addr0, lds_wdata0, lds_rdata0;
  wire        lds_req1, lds_we1, lds_rdy1, lds_cfl1;
  wire [1023:0] lds_addr1, lds_wdata1, lds_rdata1;

  wire        gm_req0, gm_we0;
  wire [31:0] gm_addr0;
  wire [1023:0] gm_wdata0;
  reg  [1023:0] gm_rdata0;
  reg         gm_rdy0;

  wire        gm_req1, gm_we1;
  wire [31:0] gm_addr1;
  wire [1023:0] gm_wdata1;
  reg  [1023:0] gm_rdata1;
  reg         gm_rdy1;

  wire        wreq0, wreq1;
  wire [31:0] wa0, wb0, wc0, wa1, wb1, wc1;
  reg         wdone0, wdone1;
  wire        wack0, wack1;

  wire        treq0, treq1;
  wire [31:0] ts0, td0, tl0, ts1, td1, tl1;
  reg         tdone0, tdone1;
  wire        tack0, tack1;

  wire        sfre0, sfre1;
  wire [31:0] sfa0, sfa1, sfl0, sfl1;
  reg         sfdone0, sfdone1;

  simd32 u_simd0 (
    .clk(clk), .rst_n(rst_n),
    .launch(launch0), .kernel_pc(8'd0), .wg_id(wg_id0), .wg_size(wg_size),
    .arg_ptr(arg_ptr), .lds_base(32'd0),
    .busy(busy0), .done(done0), .error(err0),
    .imem_addr(imem_addr0), .imem_data(imem_data0),
    .lds_req(lds_req0), .lds_we(lds_we0), .lds_addr(lds_addr0),
    .lds_wdata(lds_wdata0), .lds_rdata(lds_rdata0),
    .lds_ready(lds_rdy0), .lds_conflict(lds_cfl0),
    .gmem_req(gm_req0), .gmem_we(gm_we0), .gmem_addr(gm_addr0),
    .gmem_wdata(gm_wdata0), .gmem_rdata(gm_rdata0), .gmem_ready(gm_rdy0),
    .wmma_req(wreq0), .wmma_a(wa0), .wmma_b(wb0), .wmma_c(wc0),
    .wmma_ack(wack0), .wmma_done(wdone0),
    .tdm_req(treq0), .tdm_src(ts0), .tdm_dst(td0), .tdm_len(tl0),
    .tdm_ack(tack0), .tdm_done(tdone0),
    .softmax_req(sfre0), .softmax_base(sfa0), .softmax_len(sfl0),
    .softmax_done(sfdone0),
    .cycle(cycle)
  );

  simd32 u_simd1 (
    .clk(clk), .rst_n(rst_n),
    .launch(launch1), .kernel_pc(8'd0), .wg_id(wg_id1), .wg_size(wg_size),
    .arg_ptr(arg_ptr), .lds_base(32'd0),
    .busy(busy1), .done(done1), .error(err1),
    .imem_addr(imem_addr1), .imem_data(imem_data1),
    .lds_req(lds_req1), .lds_we(lds_we1), .lds_addr(lds_addr1),
    .lds_wdata(lds_wdata1), .lds_rdata(lds_rdata1),
    .lds_ready(lds_rdy1), .lds_conflict(lds_cfl1),
    .gmem_req(gm_req1), .gmem_we(gm_we1), .gmem_addr(gm_addr1),
    .gmem_wdata(gm_wdata1), .gmem_rdata(gm_rdata1), .gmem_ready(gm_rdy1),
    .wmma_req(wreq1), .wmma_a(wa1), .wmma_b(wb1), .wmma_c(wc1),
    .wmma_ack(wack1), .wmma_done(wdone1),
    .tdm_req(treq1), .tdm_src(ts1), .tdm_dst(td1), .tdm_len(tl1),
    .tdm_ack(tack1), .tdm_done(tdone1),
    .softmax_req(sfre1), .softmax_base(sfa1), .softmax_len(sfl1),
    .softmax_done(sfdone1),
    .cycle(cycle)
  );

  // ---------------------------------------------------------------- LDS
  wire [9:0]  lin_addr;
  wire [1023:0] lin_wdata, lin_rdata;
  wire        lin_req, lin_we, lin_ready;

  wire        w_lds_req, w_lds_we, w_lds_ready;
  wire [9:0]  w_lds_addr;
  wire [1023:0] w_lds_wdata;
  wire        t_lds_req, t_lds_we, t_lds_ready;
  wire [9:0]  t_lds_addr;
  wire [1023:0] t_lds_wdata;

  assign lin_req    = w_lds_req | t_lds_req;
  assign lin_we     = w_lds_req ? w_lds_we : t_lds_we;
  assign lin_addr   = w_lds_req ? w_lds_addr : t_lds_addr;
  assign lin_wdata  = w_lds_req ? w_lds_wdata : t_lds_wdata;
  assign w_lds_ready = w_lds_req & lin_ready;
  assign t_lds_ready = t_lds_req & ~w_lds_req & lin_ready;

  // Softmax engine signals (declared before the LDS scalar port).
  wire        sf_busy, sf_done;
  reg         sf_start;
  reg  [9:0]  sf_base;
  reg  [6:0]  sf_len;
  reg         sf_owner;
  reg  [1:0]  sf_cool;
  wire        sf_lds_req, sf_lds_we;
  wire [9:0]  sf_lds_addr;
  wire [31:0] sf_lds_wdata, sf_lds_rdata;
  wire        sf_lds_ready;

  lds u_lds (
    .clk(clk), .rst_n(rst_n),
    .req0(lds_req0), .we0(lds_we0), .addr0(lds_addr0), .wdata0(lds_wdata0),
    .rdata0(lds_rdata0), .ready0(lds_rdy0), .conflict0(lds_cfl0),
    .req1(lds_req1), .we1(lds_we1), .addr1(lds_addr1), .wdata1(lds_wdata1),
    .rdata1(lds_rdata1), .ready1(lds_rdy1), .conflict1(lds_cfl1),
    .reql(lin_req), .wel(lin_we), .addrl(lin_addr), .wdatal(lin_wdata),
    .rdatal(lin_rdata), .readyl(lin_ready),
    .reqs(sf_lds_req), .wes(sf_lds_we), .addrs(sf_lds_addr),
    .wdatas(sf_lds_wdata), .rdatas(sf_lds_rdata), .readys(sf_lds_ready)
  );

  // ---------------------------------------------------------------- WMMA
  wire        wmm_busy, wmm_done;
  reg         wmm_start;
  reg  [31:0] wmm_a, wmm_b, wmm_c;
  reg         wmm_owner;
  reg  [1:0]  wmm_cool;
  reg  [1:0]  wmm_kick;

  wmma u_wmma (
    .clk(clk), .rst_n(rst_n),
    .start(wmm_start), .a_base(wmm_a[9:0]), .b_base(wmm_b[9:0]), .c_base(wmm_c[9:0]),
    .busy(wmm_busy), .done(wmm_done),
    .lds_req(w_lds_req), .lds_we(w_lds_we), .lds_addr(w_lds_addr),
    .lds_wdata(w_lds_wdata), .lds_rdata(lin_rdata), .lds_ready(w_lds_ready)
  );

  // ---------------------------------------------------------------- TDM
  wire        tdm_busy, tdm_done;
  reg         tdm_start;
  reg  [31:0] tdm_src_r, tdm_len_r;
  reg  [9:0]  tdm_dst_r;
  reg         tdm_owner;
  reg  [1:0]  tdm_cool;
  reg  [1:0]  tdm_kick;

  wire        t_req;
  wire [31:0] t_addr;
  reg         t_ready;

  tdm u_tdm (
    .clk(clk), .rst_n(rst_n),
    .start(tdm_start), .src(tdm_src_r), .dst(tdm_dst_r), .len(tdm_len_r[8:0]),
    .busy(tdm_busy), .done(tdm_done),
    .gmem_req(t_req), .gmem_addr(t_addr), .gmem_rdata(mem_rdata),
    .gmem_ready(t_ready),
    .lds_req(t_lds_req), .lds_we(t_lds_we), .lds_addr(t_lds_addr),
    .lds_wdata(t_lds_wdata), .lds_ready(t_lds_ready)
  );

  softmax_engine u_softmax (
    .clk(clk), .rst_n(rst_n),
    .start(sf_start), .base_word(sf_base), .len(sf_len),
    .busy(sf_busy), .done(sf_done),
    .lds_req(sf_lds_req), .lds_we(sf_lds_we), .lds_addr(sf_lds_addr),
    .lds_wdata(sf_lds_wdata), .lds_rdata(sf_lds_rdata),
    .lds_ready(sf_lds_ready)
  );

  // ---------------------------------------------------------------- dispatch
  reg [7:0]  pending;
  reg [15:0] next_wg;
  integer k;

  always @(posedge clk) begin
    if (!rst_n) begin
      busy      <= 1'b0;
      done      <= 1'b0;
      error     <= 1'b0;
      waves_done<= 8'd0;
      pending   <= 8'd0;
      next_wg   <= 16'd0;
      launch0   <= 1'b0;
      launch1   <= 1'b0;
      wg_id0    <= 16'd0;
      wg_id1    <= 16'd0;
      wmm_start <= 1'b0;
      wmm_a     <= 32'd0;
      wmm_b     <= 32'd0;
      wmm_c     <= 32'd0;
      wmm_owner <= 1'b0;
      wmm_cool  <= 2'd0;
      wmm_kick  <= 2'd0;
      wdone0    <= 1'b0;
      wdone1    <= 1'b0;
      tdm_start <= 1'b0;
      tdm_src_r <= 32'd0;
      tdm_dst_r <= 10'd0;
      tdm_len_r <= 32'd0;
      tdm_owner <= 1'b0;
      tdm_cool  <= 2'd0;
      tdm_kick  <= 2'd0;
      tdone0    <= 1'b0;
      tdone1    <= 1'b0;
      sf_start  <= 1'b0;
      sf_base   <= 10'd0;
      sf_len    <= 7'd0;
      sf_owner  <= 1'b0;
      sf_cool   <= 2'd0;
      sfdone0   <= 1'b0;
      sfdone1   <= 1'b0;
    end else begin
      launch0   <= 1'b0;
      launch1   <= 1'b0;
      wmm_start <= 1'b0;
      tdm_start <= 1'b0;
      sf_start  <= 1'b0;
      done      <= 1'b0;

      if (start) begin
        busy       <= 1'b1;
        done       <= 1'b0;
        error      <= 1'b0;
        waves_done <= 8'd0;
        pending    <= grid_x;
        next_wg    <= 16'd0;
      end

      if (busy && pending != 8'd0) begin
        if (!busy0 && !launch0 && !launch1) begin
          launch0 <= 1'b1;
          wg_id0  <= next_wg;
          next_wg <= next_wg + 16'd1;
          pending <= pending - 8'd1;
        end else if (!busy1 && !launch0 && !launch1) begin
          launch1 <= 1'b1;
          wg_id1  <= next_wg;
          next_wg <= next_wg + 16'd1;
          pending <= pending - 8'd1;
        end
      end

      if (done0) waves_done <= waves_done + 8'd1;
      if (done1) waves_done <= waves_done + 8'd1;
      if (err0 || err1) error <= 1'b1;

      if (busy && pending == 8'd0 && !busy0 && !busy1 && !launch0 && !launch1) begin
        busy <= 1'b0;
        done <= 1'b1;
      end

      // WMMA arbitration (one outstanding, SIMD0 priority)
      if (wmm_cool != 2'd0) wmm_cool <= wmm_cool - 2'd1;
      if (wmm_kick != 2'd0) wmm_kick <= wmm_kick - 2'd1;
      if (!wmm_busy && !wmm_start && !wmm_done && wmm_cool == 2'd0 && wmm_kick == 2'd0 && (wreq0 || wreq1)) begin
        if (wreq0) begin
          wmm_a <= wa0; wmm_b <= wb0; wmm_c <= wc0; wmm_owner <= 1'b0;
        end else begin
          wmm_a <= wa1; wmm_b <= wb1; wmm_c <= wc1; wmm_owner <= 1'b1;
        end
        wmm_start <= 1'b1;
        wmm_kick  <= 2'd2;
      end
      if (wmm_done) begin
        wmm_cool <= 2'd2;
        if (wmm_owner) wdone1 <= 1'b1;
        else           wdone0 <= 1'b1;
      end else begin
        wdone0 <= 1'b0;
        wdone1 <= 1'b0;
      end

      // TDM arbitration (serialised with WMMA)
      if (tdm_cool != 2'd0) tdm_cool <= tdm_cool - 2'd1;
      if (tdm_kick != 2'd0) tdm_kick <= tdm_kick - 2'd1;
      if (!tdm_busy && !tdm_start && !tdm_done && !wmm_busy && !wmm_start && tdm_cool == 2'd0 && tdm_kick == 2'd0 && (treq0 || treq1)) begin
        if (treq0) begin
          tdm_src_r <= ts0; tdm_dst_r <= td0[9:0]; tdm_len_r <= tl0; tdm_owner <= 1'b0;
        end else begin
          tdm_src_r <= ts1; tdm_dst_r <= td1[9:0]; tdm_len_r <= tl1; tdm_owner <= 1'b1;
        end
        tdm_start <= 1'b1;
        tdm_kick  <= 2'd2;
      end
      if (tdm_done) begin
        tdm_cool <= 2'd2;
        if (tdm_owner) tdone1 <= 1'b1;
        else           tdone0 <= 1'b1;
      end else begin
        tdone0 <= 1'b0;
        tdone1 <= 1'b0;
      end

      // Softmax arbitration: one row engine, only when WMMA/TDM are idle.
      if (sf_cool != 2'd0) sf_cool <= sf_cool - 2'd1;
      if (!sf_busy && !sf_start && !sf_done && sf_cool == 2'd0 &&
          !wmm_busy && !wmm_start && !tdm_busy && !tdm_start &&
          (sfre0 || sfre1)) begin
        if (sfre0) begin
          sf_base <= sfa0[9:0]; sf_len <= sfl0[6:0]; sf_owner <= 1'b0;
        end else begin
          sf_base <= sfa1[9:0]; sf_len <= sfl1[6:0]; sf_owner <= 1'b1;
        end
        sf_start <= 1'b1;
        sf_cool  <= 2'd2;
      end
      if (sf_done) begin
        sf_cool <= 2'd2;
        if (sf_owner) sfdone1 <= 1'b1;
        else          sfdone0 <= 1'b1;
      end else begin
        sfdone0 <= 1'b0;
        sfdone1 <= 1'b0;
      end
    end
  end

  // ---------------------------------------------------------------- memory arbiter
  localparam M_IDLE = 2'd0;
  localparam M_BUSY = 2'd1;
  localparam M_COOL = 2'd2;
  localparam M_COOL2= 2'd3;

  reg [1:0]  mstate;
  reg [1:0]  mowner;
  reg [31:0] maddr;
  reg        mwe;
  reg [1023:0] mwdata;

  assign mem_req  = (mstate == M_BUSY);
  assign mem_we   = mwe;
  assign mem_addr = maddr;
  assign mem_wdata= mwdata;

  always @(posedge clk) begin
    if (!rst_n) begin
      mstate  <= M_IDLE;
      mowner  <= 2'd0;
      maddr   <= 32'd0;
      mwe     <= 1'b0;
      mwdata  <= 1024'd0;
      gm_rdy0 <= 1'b0;
      gm_rdy1 <= 1'b0;
      t_ready <= 1'b0;
      gm_rdata0 <= 1024'd0;
      gm_rdata1 <= 1024'd0;
    end else begin
      gm_rdy0 <= 1'b0;
      gm_rdy1 <= 1'b0;
      t_ready <= 1'b0;

      case (mstate)
        M_IDLE: begin
          if (gm_req0 || gm_req1 || t_req)
          if (gm_req0) begin
            mowner <= 2'd0; maddr <= gm_addr0; mwe <= gm_we0; mwdata <= gm_wdata0;
            mstate <= M_BUSY;
          end else if (gm_req1) begin
            mowner <= 2'd1; maddr <= gm_addr1; mwe <= gm_we1; mwdata <= gm_wdata1;
            mstate <= M_BUSY;
          end else if (t_req) begin
            mowner <= 2'd2; maddr <= t_addr; mwe <= 1'b0; mwdata <= 1024'd0;
            mstate <= M_BUSY;
          end
        end
        M_BUSY: begin
          if (mem_ready) begin
            case (mowner)
              2'd0: begin
                gm_rdy0 <= 1'b1; gm_rdata0 <= mem_rdata;
              end
              2'd1: begin gm_rdy1 <= 1'b1; gm_rdata1 <= mem_rdata; end
              default: t_ready <= 1'b1;
            endcase
            mstate <= M_COOL;
          end
        end
        M_COOL:  mstate <= M_COOL2;
        M_COOL2: mstate <= M_IDLE;
        default: mstate <= M_IDLE;
      endcase
    end
  end

  assign wack0 = 1'b0;
  assign wack1 = 1'b0;
  assign tack0 = 1'b0;
  assign tack1 = 1'b0;

endmodule
