`timescale 1ns/1ps
module tb_requant;
 reg signed [31:0] acc,multiplier;
 reg [5:0] shift;
 reg relu;
 wire signed [7:0] value;
 dg_requant dut(acc,multiplier,shift,relu,value);
 task check;
   input signed [31:0] a,m; input [5:0] s; input r;
   input signed [7:0] expected;
   begin acc=a; multiplier=m; shift=s; relu=r; #1;
     if(value!==expected) $fatal(1,"requant a=%0d m=%0d s=%0d got=%0d exp=%0d",a,m,s,value,expected);
   end
 endtask
 initial begin
   check(1,1,1,0,1); check(-1,1,1,0,-1);
   check(3,1,1,0,2); check(-3,1,1,0,-2);
   check(2147483647,2147483647,62,0,1);
   check(-2147483648,2147483647,62,0,-1);
   check(-2147483648,1,0,0,-128);
   check(2147483647,1,0,0,127);
   check(-123,1,0,1,0); check(12,0,0,0,0);
   $display("PASS: 10 requant boundary vectors"); $finish;
 end
endmodule
