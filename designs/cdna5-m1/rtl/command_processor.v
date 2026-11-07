// Copyright (c) 2026 CDNA5-M1 project.
// SPDX-License-Identifier: MIT
//
// command_processor.v -- host command processor for the M1 chip.
//
// Bring-up design: the host programs the CSR block, then writes CONTROL.START.
// The CP copies the 1 KB kernel image from KERNEL_PC into the WGP I$ through
// the memory block port, launches the grid, and raises the completion
// interrupt.
//
// This is the CDNA5 command-processor role (fetch commands from a ring,
// dispatch work, signal completion) with a CSR rather than a ring-buffer
// front end; the preload path stands in for the I$ miss path.

`include "cdna5_m1_defs.vh"

module command_processor (
  input  wire        clk,
  input  wire        rst_n,

  // CSR port
  input  wire        csr_wr,
  input  wire [7:0]  csr_waddr,
  input  wire [31:0] csr_wdata,
  input  wire        csr_rd,
  input  wire [7:0]  csr_raddr,
  output reg  [31:0] csr_rdata,

  // memory block port
  output reg         mem_req,
  output wire        mem_we,
  output wire [31:0] mem_addr,
  output wire [1023:0] mem_wdata,
  input  wire [1023:0] mem_rdata,
  input  wire        mem_ready,

  // I$ fill port
  output reg         ic_we,
  output reg  [7:0]  ic_addr,
  output reg  [31:0] ic_wdata,

  // WGP launch
  output reg         wgp_start,
  output wire [7:0]  grid_x,
  output wire [15:0] wg_size,
  output wire [31:0] arg_ptr,
  input  wire        wgp_busy,
  input  wire        wgp_done,
  input  wire        wgp_error,

  output reg         irq,
  output wire [63:0] cycle_out
);

  reg [31:0] ctrl;
  reg [31:0] status;
  reg [31:0] kernel_pc;
  reg [31:0] arg_ptr_r;
  reg [7:0]  grid_x_r;
  reg [31:0] grid_y, grid_z;
  reg [15:0] wg_size_r;
  reg [31:0] irq_en;
  reg [31:0] wave_done;
  reg [63:0] cycle;

  assign cycle_out = cycle;
  assign grid_x    = grid_x_r;
  assign wg_size   = wg_size_r;
  assign arg_ptr   = arg_ptr_r;

  // ------------------------------------------------------------------ FSM
  localparam C_IDLE = 2'd0;
  localparam C_PRE  = 2'd1;
  localparam C_FILL = 2'd2;
  localparam C_RUN  = 2'd3;

  reg [1:0]  cstate;
  reg [31:0] preload_addr;
  reg [31:0] preload_base;
  reg [1023:0] blk_data;
  reg [3:0]  blk;
  reg [5:0]  wr_idx;
  reg        start_pending;

  always @(posedge clk) begin
    if (!rst_n) begin
      ctrl <= 32'd0;
      status <= 32'd0;
      kernel_pc <= 32'd0;
      arg_ptr_r <= 32'd0;
      grid_x_r <= 8'd1;
      grid_y <= 32'd1;
      grid_z <= 32'd1;
      wg_size_r <= 16'd32;
      irq_en <= 32'd0;
      wave_done <= 32'd0;
      cycle <= 64'd0;
      irq <= 1'b0;
      cstate <= C_IDLE;
      mem_req <= 1'b0;
      preload_addr <= 32'd0;
      preload_base <= 32'd0;
      blk_data <= 1024'd0;
      blk <= 4'd0;
      wr_idx <= 6'd0;
      ic_we <= 1'b0;
      ic_addr <= 8'd0;
      ic_wdata <= 32'd0;
      wgp_start <= 1'b0;
      start_pending <= 1'b0;
    end else begin
      cycle <= cycle + 64'd1;
      ic_we <= 1'b0;
      wgp_start <= 1'b0;

      // ---------------------------------------------------------- CSR writes
      if (csr_wr) begin
        case (csr_waddr)
          8'h00: begin
            ctrl <= csr_wdata;
            if (csr_wdata[0]) start_pending <= 1'b1;
          end
          8'h08: kernel_pc  <= csr_wdata;
          8'h0C: arg_ptr_r  <= csr_wdata;
          8'h10: grid_x_r   <= csr_wdata[7:0];
          8'h14: grid_y     <= csr_wdata;
          8'h18: grid_z     <= csr_wdata;
          8'h1C: wg_size_r  <= csr_wdata[15:0];
          8'h20: irq_en     <= csr_wdata;
          default: ;
        endcase
      end

      // ---------------------------------------------------------- FSM
      case (cstate)
        C_IDLE: begin
          if (wgp_done) begin
            status[1] <= 1'b1;
            status[0] <= 1'b0;
            wave_done <= wave_done + 32'd1;
          end
          if (wgp_error) status[2] <= 1'b1;

          if (start_pending && !status[0]) begin
            start_pending <= 1'b0;
            status <= 32'b001;      // busy
            irq    <= 1'b0;
            blk    <= 4'd0;
            wr_idx <= 6'd0;
            preload_base <= kernel_pc;
            preload_addr <= kernel_pc;
            mem_req <= 1'b1;
            cstate  <= C_PRE;
          end
        end

        C_PRE: begin
          if (mem_ready) begin
            blk_data <= mem_rdata;
            mem_req  <= 1'b0;
            wr_idx   <= 6'd0;
            cstate   <= C_FILL;
          end
        end

        C_FILL: begin
          ic_we    <= 1'b1;
          ic_addr  <= blk * 8'd32 + {2'b0, wr_idx};
          ic_wdata <= blk_data[wr_idx*32 +: 32];
          wr_idx   <= wr_idx + 6'd1;
          if (wr_idx == 6'd31) begin
            if (blk == 4'd7) begin
              wgp_start <= 1'b1;
              status[1] <= 1'b0;
              cstate    <= C_RUN;
            end else begin
              blk <= blk + 4'd1;
              preload_addr <= preload_base + ((blk + 4'd1) * 32'd128);
              mem_req <= 1'b1;
              cstate  <= C_PRE;
            end
          end
        end

        C_RUN: begin
          if (wgp_done) begin
            status[1] <= 1'b1;
            status[0] <= 1'b0;
            wave_done <= wave_done + 32'd1;
            irq <= (irq_en[0]) ? 1'b1 : 1'b0;
            cstate <= C_IDLE;
          end
          if (wgp_error) begin
            status[2] <= 1'b1;
            status[0] <= 1'b0;
            cstate <= C_IDLE;
          end
        end

        default: cstate <= C_IDLE;
      endcase
    end
  end

  // ---------------------------------------------------------------- CSR read
  always @* begin
    case (csr_raddr)
      8'h00: csr_rdata = ctrl;
      8'h04: csr_rdata = status;
      8'h08: csr_rdata = kernel_pc;
      8'h0C: csr_rdata = arg_ptr_r;
      8'h10: csr_rdata = {24'd0, grid_x_r};
      8'h14: csr_rdata = grid_y;
      8'h18: csr_rdata = grid_z;
      8'h1C: csr_rdata = {16'd0, wg_size_r};
      8'h20: csr_rdata = irq_en;
      8'h24: csr_rdata = cycle[31:0];
      8'h28: csr_rdata = cycle[63:32];
      8'h2C: csr_rdata = wave_done;
      8'h30: csr_rdata = 32'h43444e35; // "CDN5"
      default: csr_rdata = 32'd0;
    endcase
  end

  assign mem_we    = 1'b0;
  assign mem_addr  = preload_addr;
  assign mem_wdata = 1024'd0;

endmodule
