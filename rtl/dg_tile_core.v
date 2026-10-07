`timescale 1ns/1ps
// Output-stationary tile: one activation vector, LANES output channels.
// Host packs convolution windows and schedules tiles. No DMA in this module.
module dg_tile_core #(parameter LANES=8, DEPTH=256)(
 input clk, input rst_n,
 input start, input [15:0] length, input model_id, input relu,
 input act_we, input [15:0] act_addr, input signed [7:0] act_data,
 input weight_we, input [15:0] weight_lane, input [15:0] weight_addr,
 input signed [7:0] weight_data,
 input param_we, input [15:0] param_lane, input [1:0] param_kind,
 input [31:0] param_data,
 output busy, output load_ready, output reg done, output reg error,
 output out_valid, input out_ready, output [15:0] out_lane,
 output out_model, output signed [31:0] out_acc,
 output signed [7:0] out_q
);
 localparam IDLE=0, FETCH=1, MAC=2, FINISH=3, EMIT=4;
 reg [2:0] state;
 reg [15:0] k, count, lane;
 reg active_model, active_relu;
 reg signed [31:0] biases [0:LANES-1];
 reg signed [31:0] multipliers [0:LANES-1];
 reg [5:0] shifts [0:LANES-1];
 wire signed [7:0] a;
 wire signed [31:0] accumulators [0:LANES-1];
 wire accept_start = start && state==IDLE && length>0 && length<=DEPTH;
 assign busy = state != IDLE;
 assign load_ready = !busy;
 assign out_valid = state == EMIT;
 assign out_lane = lane;
 assign out_model = active_model;
 assign out_acc = accumulators[lane];
 dg_tile_ram #(DEPTH) input_bank(clk, act_we && !busy,
   act_addr, act_data, state==FETCH, k, a);
 genvar g;
 generate for(g=0; g<LANES; g=g+1) begin: banks
   wire signed [7:0] w;
   dg_tile_ram #(DEPTH) weight_bank(clk,
     weight_we && !busy && weight_lane==g,
     weight_addr, weight_data, state==FETCH, k, w);
   dg_mac_lane mac(clk,rst_n,accept_start,state==MAC,a,w,
     biases[g],accumulators[g]);
 end endgenerate
 // One shared requantizer selected by output lane.
 dg_requant quant(out_acc,multipliers[lane],shifts[lane],active_relu,out_q);
 integer i;
 always @(posedge clk) begin
   if(!rst_n) begin
     state<=IDLE; k<=0; count<=0; lane<=0;
     active_model<=0; active_relu<=0; done<=0; error<=0;
     for(i=0;i<LANES;i=i+1) begin
       biases[i]<=0; multipliers[i]<=1; shifts[i]<=0;
     end
   end else begin
     done<=0; error<=0;
     if(param_we && !busy && param_lane<LANES) begin
       case(param_kind)
         0: biases[param_lane]<=param_data;
         1: if(!param_data[31]) multipliers[param_lane]<=param_data;
            else error<=1;
         2: if(param_data<=62) shifts[param_lane]<=param_data[5:0];
            else error<=1;
         default: error<=1;
       endcase
     end
     if(start && busy) error<=1;
     case(state)
       IDLE: if(start) begin
         if(length==0 || length>DEPTH) error<=1;
         else begin
           count<=length; k<=0; lane<=0;
           active_model<=model_id; active_relu<=relu; state<=FETCH;
         end
       end
       FETCH: state<=MAC;
       MAC: if(k==count-1) state<=FINISH;
            else begin k<=k+1; state<=FETCH; end
       FINISH: state<=EMIT;
       EMIT: if(out_ready) begin
         if(lane==LANES-1) begin state<=IDLE; done<=1; end
         else lane<=lane+1;
       end
       default: state<=IDLE;
     endcase
   end
 end
endmodule
