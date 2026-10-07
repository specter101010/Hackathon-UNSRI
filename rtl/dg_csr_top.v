`timescale 1ns/1ps
// Avalon-MM 32-bit agent: byte addresses, readLatency=0, no bursts.
// Full-word aligned writes only. Single clock domain, synchronous reset.
module dg_csr_top #(parameter LANES=8, DEPTH=256)(
 input clk, input rst_n, input [7:0] address,
 input read, input write, input [3:0] byteenable,
 input [31:0] writedata, output reg [31:0] readdata,
 output waitrequest, output irq
);
 localparam [15:0] LANES_VALUE=LANES, DEPTH_VALUE=DEPTH;
 reg [15:0] length, index_reg, lane_reg;
 reg model_id, relu, sticky_done, sticky_error;
 reg [31:0] cycles;
 wire busy, done, error, valid, model;
 wire [15:0] out_lane;
 wire signed [31:0] out_acc;
 wire signed [7:0] out_q;
 wire aligned = address[1:0]==0;
 wire wr = write && aligned && byteenable==4'hf;
 wire ctrl = wr && address==8'h00;
 wire load = wr && !busy;
 wire pop = ctrl && writedata[2];
 assign waitrequest=0;
 assign irq=sticky_done || sticky_error;
 dg_tile_core #(LANES,DEPTH) core(
   .clk(clk),.rst_n(rst_n),.start(ctrl && writedata[0]),
   .length(length),.model_id(model_id),.relu(relu),
   .act_we(load && address==8'h18),.act_addr(index_reg),
   .act_data(writedata[7:0]),
   .weight_we(load && address==8'h1c),.weight_lane(lane_reg),
   .weight_addr(index_reg),.weight_data(writedata[7:0]),
   .param_we(load && (address==8'h20 || address==8'h24 || address==8'h28)),
   .param_lane(lane_reg),
   .param_kind(address==8'h20 ? 2'd0 : address==8'h24 ? 2'd1 : 2'd2),
   .param_data(writedata),.busy(busy),.load_ready(),
   .done(done),.error(error),.out_valid(valid),.out_ready(pop),
   .out_lane(out_lane),.out_model(model),.out_acc(out_acc),.out_q(out_q));
 always @* begin
   readdata=0;
   if(read && aligned) case(address)
     8'h04: readdata={28'd0,sticky_error,sticky_done,valid,busy};
     8'h08: readdata={16'd0,length};
     8'h0c: readdata={30'd0,relu,model_id};
     8'h10: readdata={16'd0,index_reg};
     8'h14: readdata={16'd0,lane_reg};
     8'h30: readdata={{24{out_q[7]}},out_q};
     8'h34: readdata=out_acc;
     8'h38: readdata={15'd0,model,out_lane};
     8'h3c: readdata=cycles;
     8'h40: readdata={16'd0,LANES_VALUE};
     8'h44: readdata={16'd0,DEPTH_VALUE};
     default: readdata=0;
   endcase
 end
 always @(posedge clk) begin
   if(!rst_n) begin
     length<=1; index_reg<=0; lane_reg<=0; model_id<=0; relu<=0;
     sticky_done<=0; sticky_error<=0; cycles<=0;
   end else begin
     if(ctrl && writedata[1]) begin sticky_done<=0; sticky_error<=0; end
     if(ctrl && writedata[0] && !busy) begin cycles<=0; sticky_done<=0; end
     else if(busy) cycles<=cycles+1;
     if(done) sticky_done<=1;
     if(error) sticky_error<=1;
     if(write && (!aligned || byteenable!=4'hf)) sticky_error<=1;
     if(wr && !ctrl && busy) sticky_error<=1;
     if(load) case(address)
       8'h08: if(writedata<=DEPTH && writedata>0) length<=writedata[15:0];
              else sticky_error<=1;
       8'h0c: if(writedata<=3) begin model_id<=writedata[0]; relu<=writedata[1]; end
              else sticky_error<=1;
       8'h10: if(writedata<DEPTH) index_reg<=writedata[15:0]; else sticky_error<=1;
       8'h14: if(writedata<LANES) lane_reg<=writedata[15:0]; else sticky_error<=1;
       8'h00,8'h18,8'h1c,8'h20,8'h24,8'h28: ;
       default: sticky_error<=1;
     endcase
   end
 end
endmodule
