`timescale 1ns/1ps
// One synchronous-read bank. Contents are intentionally not reset.
module dg_tile_ram #(parameter DEPTH=256)(
 input clk, input we, input [15:0] waddr, input signed [7:0] wdata,
 input re, input [15:0] raddr, output reg signed [7:0] q
);
 (* ramstyle = "M10K" *) reg signed [7:0] mem [0:DEPTH-1];
 always @(posedge clk) begin
   if (we && waddr < DEPTH) mem[waddr] <= wdata;
   if (re && raddr < DEPTH) q <= mem[raddr];
 end
endmodule
