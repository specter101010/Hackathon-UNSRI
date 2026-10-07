`timescale 1ns/1ps
// Custom symmetric INT8 contract; NOT TFLite bit-exact requantization.
// multiplier must be 0..2^31-1, shift 0..62. Round ties away from zero.
module dg_requant(
 input signed [31:0] acc, input signed [31:0] multiplier,
 input [5:0] shift, input relu, output reg signed [7:0] value
);
 reg signed [63:0] product, rounded;
 reg [63:0] magnitude, half, scaled;
 always @* begin
   product = acc * multiplier;
   magnitude = product[63] ? -product : product;
   half = (shift == 0) ? 64'd0 : (64'd1 << (shift-1));
   scaled = (magnitude + half) >> shift;
   rounded = product[63] ? -$signed(scaled) : $signed(scaled);
   if (relu && rounded < 0) value = 0;
   else if (rounded > 127) value = 8'sd127;
   else if (rounded < -128) value = -8'sd128;
   else value = rounded[7:0];
 end
endmodule
