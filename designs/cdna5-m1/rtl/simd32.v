// Copyright (c) 2026 CDNA5-M1 project.
// SPDX-License-Identifier: MIT
//
// simd32.v -- one CDNA5-style SIMD32: per-wave SALU/SGPR, 32-lane VALU/VGPR,
// instruction sequencer, LDS lane port and global-memory block port.
//
// The M1 executes one wave per SIMD at a time. Every instruction is fetched
// from the preloaded 1 KB I$, decoded, then executed. Vector ALU write-back
// needs no bypass network: fetch (1 cyc) + fetch_wait (1) + decode (1) means a
// dependent instruction never reaches EXEC before the previous write-back.
//
// Memory forms are block forms: V_LDS_* moves 32 consecutive words (lane i
// word i), V_MEM_* moves one 128-byte global block.  This is the bring-up
// subset of the CDNA5 per-lane VMEM path.

`include "cdna5_m1_defs.vh"


  // ---------------------------------------------------- MXFP4 / INT8 helpers
  function automatic signed [4:0] v_fp4_to_i5;
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
      v_fp4_to_i5 = v[3] ? -out : out;
    end
  endfunction

  function automatic signed [31:0] v_dot8_fp4;
    input [31:0] a;
    input [31:0] b;
    integer k;
    reg signed [4:0] av, bv;
    reg signed [9:0] prod;
    reg signed [31:0] acc;
    begin
      acc = 32'sd0;
      for (k = 0; k < 8; k = k + 1) begin
        av = v_fp4_to_i5(a[k*4 +: 4]);
        bv = v_fp4_to_i5(b[k*4 +: 4]);
        prod = av * bv;
        acc = acc + {{22{prod[9]}}, prod};
      end
      v_dot8_fp4 = acc;
    end
  endfunction

  function automatic signed [31:0] v_dot4_i8;
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
      v_dot4_i8 = acc;
    end
  endfunction

module simd32 (
  input  wire         clk,
  input  wire         rst_n,

  // wave launch / status
  input  wire         launch,
  input  wire [7:0]   kernel_pc,
  input  wire [15:0]  wg_id,
  input  wire [15:0]  wg_size,
  input  wire [31:0]  arg_ptr,
  input  wire [31:0]  lds_base,
  output reg          busy,
  output reg          done,
  output reg          error,

  // instruction port
  output wire [7:0]   imem_addr,
  input  wire [31:0]  imem_data,

  // LDS lane port (32 x 32-bit byte addresses / write data)
  output reg          lds_req,
  output reg          lds_we,
  output wire [1023:0] lds_addr,
  output wire [1023:0] lds_wdata,
  input  wire [1023:0] lds_rdata,
  input  wire         lds_ready,
  input  wire         lds_conflict,

  // global memory block port (128 B)
  output reg          gmem_req,
  output reg          gmem_we,
  output wire [31:0]  gmem_addr,
  output wire [1023:0] gmem_wdata,
  input  wire [1023:0] gmem_rdata,
  input  wire         gmem_ready,

  // matrix core / TDM hand-off
  output reg          wmma_req,
  output wire [31:0]  wmma_a,
  output wire [31:0]  wmma_b,
  output wire [31:0]  wmma_c,
  input  wire         wmma_ack,
  input  wire         wmma_done,
  output reg          tdm_req,
  output wire [31:0]  tdm_src,
  output wire [31:0]  tdm_dst,
  output wire [31:0]  tdm_len,
  input  wire         tdm_ack,
  input  wire         tdm_done,

  input  wire [63:0]  cycle
);

  // ------------------------------------------------------------------ state
  localparam S_IDLE      = 4'd0;
  localparam S_FETCH     = 4'd1;
  localparam S_FETCH_W   = 4'd2;
  localparam S_LIT_FETCH = 4'd3;
  localparam S_LIT_W     = 4'd4;
  localparam S_DEC       = 4'd5;
  localparam S_EXEC      = 4'd6;
  localparam S_LDS_W     = 4'd7;
  localparam S_GMEM_W    = 4'd8;
  localparam S_WMMA_W    = 4'd9;
  localparam S_TDM_W     = 4'd10;

  reg [3:0]  state;
  reg [7:0]  pc;
  reg [7:0]  pc_next;
  reg [31:0] exec_mask;
  reg [31:0] vcc;
  reg        scc;
  reg [31:0] sgpr [0:`SGPR_NUM-1];
  reg [31:0] vgpr [0:`VGPR_NUM-1][0:`WAVE_SIZE-1];

  reg [31:0] instr;
  reg [31:0] literal;
  reg        gwait, lwait;

  // decoded fields (latched in DEC)
  reg [5:0]  d_op;
  reg        d_imm;
  reg [4:0]  d_dst;
  reg [4:0]  d_s0;
  reg [4:0]  d_s1;
  reg [4:0]  d_s2;
  reg [15:0] d_imm16;
  reg signed [10:0] d_off11;

  // ------------------------------------------------------------------ decode
  wire [5:0]  dec_op   = instr[31:26];
  wire        dec_imm  = instr[25];
  wire [4:0]  dec_dst  = instr[24:20];
  wire [4:0]  dec_s0   = instr[19:15];
  wire [4:0]  dec_s1   = instr[14:10];
  wire [4:0]  dec_s2   = instr[9:5];
  wire [15:0] dec_i16  = instr[15:0];
  wire signed [10:0] dec_off = instr[10:0];
  wire [31:0] dec_a    = sgpr[dec_s0];
  wire [31:0] dec_b    = dec_imm ? literal : sgpr[dec_s1];
  wire        is_scalar = ~dec_op[5];

  // scalar ALU (combinational; operands are stable through DEC..EXEC)
  reg [31:0] salu_r;
  reg        salu_scc;
  always @* begin
    salu_r   = 32'd0;
    salu_scc = scc;
    case (dec_op)
      `S_MOV_B32:    salu_r = dec_b;
      `S_ADD_U32:    salu_r = dec_a + dec_b;
      `S_SUB_U32:    salu_r = dec_a - dec_b;
      `S_AND_B32:    salu_r = dec_a & dec_b;
      `S_OR_B32:     salu_r = dec_a | dec_b;
      `S_XOR_B32:    salu_r = dec_a ^ dec_b;
      `S_SHL_B32:    salu_r = dec_a << dec_b[4:0];
      `S_SHR_B32:    salu_r = dec_a >> dec_b[4:0];
      `S_CMP_LT_U32: salu_scc = (dec_a < dec_b);
      `S_GET_WG_ID:  salu_r = {16'd0, wg_id};
      `S_GET_WG_SIZE:salu_r = {16'd0, wg_size};
      `S_GET_LANE_BASE: salu_r = 32'd0;
      `S_LDS_ADDR:   salu_r = lds_base + (dec_a << 2);
      `S_CSR_READ:   salu_r = dec_i16[0] ? cycle[63:32] : cycle[31:0];
      default:       salu_r = 32'd0;
    endcase
  end

  // per-lane result
  wire [31:0] lane_a [0:`WAVE_SIZE-1];
  wire [31:0] lane_b [0:`WAVE_SIZE-1];
  wire [31:0] lane_c [0:`WAVE_SIZE-1];
  wire [31:0] lane_r [0:`WAVE_SIZE-1];

  genvar gi;
  generate
    for (gi = 0; gi < `WAVE_SIZE; gi = gi + 1) begin : LANES
      assign lane_a[gi] = vgpr[d_s0[3:0]][gi];
      assign lane_b[gi] = d_imm ? literal : vgpr[d_s1[3:0]][gi];
      assign lane_c[gi] = vgpr[d_s2[3:0]][gi];
    end
  endgenerate

  reg [31:0] lane_r_r [0:`WAVE_SIZE-1];
  integer li;
  always @* begin
    for (li = 0; li < `WAVE_SIZE; li = li + 1) begin
      lane_r_r[li] = 32'd0;
      case (d_op)
        `V_MOV_B32:          lane_r_r[li] = lane_b[li];
        `V_ADD_I32:          lane_r_r[li] = lane_a[li] + lane_b[li];
        `V_SUB_I32:          lane_r_r[li] = lane_a[li] - lane_b[li];
        `V_AND_B32:          lane_r_r[li] = lane_a[li] & lane_b[li];
        `V_OR_B32:           lane_r_r[li] = lane_a[li] | lane_b[li];
        `V_XOR_B32:          lane_r_r[li] = lane_a[li] ^ lane_b[li];
        `V_SHL_B32:          lane_r_r[li] = lane_a[li] << lane_b[li][4:0];
        `V_SHR_B32:          lane_r_r[li] = lane_a[li] >> lane_b[li][4:0];
        `V_MUL_I32:          lane_r_r[li] = $signed(lane_a[li]) * $signed(lane_b[li]);
        `V_CMP_LT_I32:       lane_r_r[li] = ($signed(lane_a[li]) < $signed(lane_b[li])) ? 32'd1 : 32'd0;
        `V_CNDMASK:          lane_r_r[li] = (lane_c[li] != 32'd0) ? lane_b[li] : lane_a[li];
        `V_MBCNT_LO_U32:     lane_r_r[li] = li[31:0];
        `V_DOT4_I32_IU8:     lane_r_r[li] = vgpr[d_dst[3:0]][li] + v_dot4_i8(lane_a[li], lane_b[li]);
        `V_DOT8_I32_IU4:     lane_r_r[li] = vgpr[d_dst[3:0]][li] + v_dot8_fp4(lane_a[li], lane_b[li]);
        `V_READFIRSTLANE_B32: lane_r_r[li] = vgpr[d_s0[3:0]][0];
        default:             lane_r_r[li] = 32'd0;
      endcase
    end
  end

  genvar gr;
  generate
    for (gr = 0; gr < `WAVE_SIZE; gr = gr + 1)
      assign lane_r[gr] = lane_r_r[gr];
  endgenerate

  // --------------------------------------------------------- bus drivers
  genvar ga;
  generate
    for (ga = 0; ga < `WAVE_SIZE; ga = ga + 1) begin : ADDR
      wire [31:0] lds_word = (d_op == `V_LDS_LD_IDX) ? vgpr[d_s0[3:0]][ga]
                                                     : sgpr[d_s0] + (ga * 4);
      assign lds_addr[ga*32 +: 32]  = lds_word;
      assign lds_wdata[ga*32 +: 32] = (d_op == `V_LDS_ST_IDX) ? vgpr[d_s1[3:0]][ga]
                                                              : vgpr[d_s1[3:0]][ga];
      assign gmem_wdata[ga*32 +: 32] = vgpr[d_s1[3:0]][ga];
    end
  endgenerate

  assign gmem_addr = sgpr[d_s0];
  assign imem_addr = pc;

  assign wmma_a = sgpr[d_dst];
  assign wmma_b = sgpr[d_dst + 5'd1];
  assign wmma_c = sgpr[d_dst + 5'd2];

  assign tdm_src = sgpr[d_dst];
  assign tdm_dst = sgpr[d_dst + 5'd1];
  assign tdm_len = sgpr[d_dst + 5'd2];

  // ------------------------------------------------------------------ FSM
  integer i;
  always @(posedge clk) begin
    if (!rst_n) begin
      state     <= S_IDLE;
      pc        <= 8'd0;
      pc_next   <= 8'd0;
      exec_mask <= 32'd0;
      vcc       <= 32'd0;
      scc       <= 1'b0;
      busy      <= 1'b0;
      done      <= 1'b0;
      error     <= 1'b0;
      lds_req   <= 1'b0;
      lds_we    <= 1'b0;
      gmem_req  <= 1'b0;
      gmem_we   <= 1'b0;
      wmma_req  <= 1'b0;
      tdm_req   <= 1'b0;
      instr     <= 32'd0;
      literal   <= 32'd0;
      gwait     <= 1'b0;
      lwait     <= 1'b0;
      d_op      <= 6'd0;
      d_imm     <= 1'b0;
      d_dst     <= 5'd0;
      d_s0      <= 5'd0;
      d_s1      <= 5'd0;
      d_s2      <= 5'd0;
      d_imm16   <= 16'd0;
      d_off11   <= 11'sd0;
    end else begin
      done <= 1'b0;

      case (state)
        S_IDLE: begin
          busy     <= 1'b0;
          lds_req  <= 1'b0;
          gmem_req <= 1'b0;
          wmma_req <= 1'b0;
          tdm_req  <= 1'b0;
          if (launch) begin
            pc        <= kernel_pc;
            pc_next   <= kernel_pc;
            exec_mask <= (wg_size >= 16'd32) ? 32'hffffffff
                                            : ((32'h1 << wg_size) - 32'h1);
            sgpr[0]   <= {16'd0, wg_id};
            sgpr[1]   <= arg_ptr;
            sgpr[2]   <= lds_base;
            sgpr[3]   <= {16'd0, wg_size};
            sgpr[4]   <= 32'd0;
            for (i = 5; i < `SGPR_NUM; i = i + 1) sgpr[i] <= 32'd0;
            vcc       <= 32'd0;
            scc       <= 1'b0;
            busy      <= 1'b1;
            error     <= 1'b0;
            state     <= S_FETCH;
          end
        end

        S_FETCH: state <= S_FETCH_W;

        S_FETCH_W: begin
          instr <= imem_data;
          if (imem_data[25]) begin
            pc    <= pc + 8'd1;       // literal word is next
            state <= S_LIT_FETCH;
          end else begin
            pc_next <= pc + 8'd1;
            state   <= S_DEC;
          end
        end

        S_LIT_FETCH: state <= S_LIT_W;

        S_LIT_W: begin
          literal <= imem_data;
          pc_next <= pc + 8'd1;
          state   <= S_DEC;
        end

        S_DEC: begin
          d_op    <= dec_op;
          d_imm   <= dec_imm;
          d_dst   <= dec_dst;
          d_s0    <= dec_s0;
          d_s1    <= dec_s1;
          d_s2    <= dec_s2;
          d_imm16 <= dec_i16;
          d_off11 <= dec_off;

          lds_req  <= 1'b0;
          lds_we   <= 1'b0;
          gmem_req <= 1'b0;
          gmem_we  <= 1'b0;
          wmma_req <= 1'b0;
          tdm_req  <= 1'b0;

          if (is_scalar) begin
            case (dec_op)
              `S_BRANCH:      begin pc <= pc + 8'd1 + dec_off[7:0]; state <= S_FETCH; end
              `S_CBRANCH_SCC: begin
                if (scc) pc <= pc + 8'd1 + dec_off[7:0];
                else     pc <= pc_next;
                state <= S_FETCH;
              end
              `S_ENDPGM: begin
                busy  <= 1'b0;
                done  <= 1'b1;
                state <= S_IDLE;
              end
              `S_NOP, `S_BARRIER, `S_WAITCNT: begin
                pc <= pc_next;
                state <= S_FETCH;
              end
              `S_TDM_COPY: begin
                tdm_req <= 1'b1;
                state   <= S_TDM_W;
              end
              `S_WMMA: begin
                wmma_req <= 1'b1;
                state    <= S_WMMA_W;
              end
              `S_SET_EXEC: begin
                exec_mask <= dec_imm ? literal : dec_a;
                pc        <= pc_next;
                state     <= S_FETCH;
              end
              default: state <= S_EXEC;
            endcase
          end else begin
            case (dec_op)
              `V_LDS_LD, `V_LDS_ST, `V_LDS_LD_IDX, `V_LDS_ST_IDX: begin
                lds_req <= 1'b1;
                lds_we  <= (dec_op == `V_LDS_ST) || (dec_op == `V_LDS_ST_IDX);
                lwait   <= 1'b1;
                state   <= S_LDS_W;
              end
              `V_MEM_LD, `V_MEM_ST: begin
                gmem_req <= 1'b1;
                gmem_we  <= (dec_op == `V_MEM_ST);
                gwait    <= 1'b1;
                state    <= S_GMEM_W;
              end
              default: state <= S_EXEC;
            endcase
          end
        end

        S_EXEC: begin
          if (is_scalar) begin
            case (d_op)
              `S_CMP_LT_U32: scc <= salu_scc;
              `S_ADD_U32, `S_SUB_U32, `S_AND_B32, `S_OR_B32, `S_XOR_B32,
              `S_SHL_B32, `S_SHR_B32, `S_MOV_B32, `S_GET_WG_ID,
              `S_GET_WG_SIZE, `S_GET_LANE_BASE, `S_LDS_ADDR, `S_CSR_READ:
                sgpr[d_dst] <= salu_r;
              default: ;
            endcase
          end else begin
            for (i = 0; i < `WAVE_SIZE; i = i + 1) begin
              if (exec_mask[i]) vgpr[d_dst[3:0]][i] <= lane_r[i];
            end
            if (d_op == `V_CMP_LT_I32) begin
              for (i = 0; i < `WAVE_SIZE; i = i + 1)
                vcc[i] <= exec_mask[i] & ($signed(lane_a[i]) < $signed(lane_b[i]));
            end
          end
          pc    <= pc_next;
          state <= S_FETCH;
        end

        S_LDS_W: begin
          if (lwait) begin
            lwait <= 1'b0;
          end else if (lds_conflict) begin
            error   <= 1'b1;
            busy    <= 1'b0;
            lds_req <= 1'b0;
            state   <= S_IDLE;
          end else if (lds_ready) begin
            if (!lds_we) begin
              for (i = 0; i < `WAVE_SIZE; i = i + 1)
                if (exec_mask[i]) vgpr[d_dst[3:0]][i] <= lds_rdata[i*32 +: 32];
            end
            lds_req <= 1'b0;
            lds_we  <= 1'b0;
            pc      <= pc_next;
            state   <= S_FETCH;
          end
        end

        S_GMEM_W: begin
          if (gwait) begin
            gwait <= 1'b0;
          end else if (gmem_ready) begin
            if (!gmem_we) begin
              for (i = 0; i < `WAVE_SIZE; i = i + 1)
                if (exec_mask[i]) vgpr[d_dst[3:0]][i] <= gmem_rdata[i*32 +: 32];
            end
            gmem_req <= 1'b0;
            gmem_we  <= 1'b0;
            pc       <= pc_next;
            state    <= S_FETCH;
          end
        end

        S_WMMA_W: begin
          if (wmma_done) begin
            wmma_req <= 1'b0;
            pc       <= pc_next;
            state    <= S_FETCH;
          end
        end

        S_TDM_W: begin
          if (tdm_done) begin
            tdm_req <= 1'b0;
            pc      <= pc_next;
            state   <= S_FETCH;
          end
        end

        default: state <= S_IDLE;
      endcase
    end
  end

endmodule
