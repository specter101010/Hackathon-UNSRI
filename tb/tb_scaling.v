`timescale 1ns/1ps
module tb_scaling;
 parameter N=128;
 reg clk=0; always #5 clk=~clk;
 reg rst_n=0,start=0,act_we=0,weight_we=0,ready=0;
 reg [15:0] weight_lane=0;
 wire busy,load_ready,done,error,valid,model;
 wire [15:0] lane;
 wire signed [31:0] acc;
 wire signed [7:0] q;
 dg_tile_core #(N,256) dut(
 .clk(clk),.rst_n(rst_n),.start(start),.length(16'd1),
 .model_id(1'b1),.relu(1'b0),.act_we(act_we),.act_addr(16'd0),
 .act_data(-8'sd128),.weight_we(weight_we),.weight_lane(weight_lane),
 .weight_addr(16'd0),.weight_data(-8'sd128),
 .param_we(1'b0),.param_lane(16'd0),.param_kind(2'd0),.param_data(32'd0),
 .busy(busy),.load_ready(load_ready),.done(done),.error(error),
 .out_valid(valid),.out_ready(ready),.out_lane(lane),.out_model(model),
 .out_acc(acc),.out_q(q));
 integer j;
 initial begin
   repeat(3) @(negedge clk); rst_n=1;
   @(negedge clk); act_we=1;
   @(negedge clk); act_we=0;
   for(j=0;j<N;j=j+1) begin
     weight_we=1; weight_lane=j;
     @(negedge clk);
   end
   weight_we=0; start=1;
   @(negedge clk); start=0;
   wait(valid); @(negedge clk);
   for(j=0;j<N;j=j+1) begin
     if(!valid || lane!=j || acc!=16384 || q!=127 || model!=1)
       $fatal(1,"scaling lane=%0d acc=%0d",j,acc);
     ready=1; @(negedge clk);
   end
   ready=0;
   if(!done || busy || error) $fatal(1,"scaling completion");
   $display("PASS: %0d lanes elaborated and simulated",N); $finish;
 end
 initial begin #100000; $fatal(1,"watchdog scaling"); end
endmodule
