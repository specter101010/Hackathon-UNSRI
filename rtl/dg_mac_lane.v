`timescale 1ns/1ps
module dg_mac_lane(
 input clk, input rst_n, input clear, input enable,
 input signed [7:0] a, input signed [7:0] w,
 input signed [31:0] bias, output reg signed [31:0] acc
);
 wire signed [15:0] product = a * w;
 wire signed [31:0] extended_product = {{16{product[15]}},product};
 always @(posedge clk) begin
   if (!rst_n) acc <= 0;
   else if (clear) acc <= bias;
   else if (enable) acc <= acc + extended_product;
 end
endmodule
