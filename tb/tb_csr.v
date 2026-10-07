`timescale 1ns/1ps
module tb_csr;
 reg clk=0; always #5 clk=~clk;
 reg rst_n=0;
 reg [7:0] address=0;
 reg read=0, write=0;
 reg [3:0] byteenable=15;
 reg [31:0] writedata=0;
 wire [31:0] readdata;
 wire waitrequest,irq;
 dg_csr_top #(4,256) dut(clk,rst_n,address,read,write,byteenable,
   writedata,readdata,waitrequest,irq);
 integer a[0:255]; integer w[0:3][0:255];
 integer b[0:3]; integer m[0:3]; integer sh[0:3];
 integer trial,k,j,n,expected,scaled,sign,seed=93217;
 reg [31:0] got;
 task wr;
   input [7:0] addr; input [31:0] val;
   begin
     @(negedge clk); address=addr; writedata=val; write=1;
     @(negedge clk); write=0;
   end
 endtask
 task rd;
   input [7:0] addr; output [31:0] val;
   begin
     @(negedge clk); address=addr; read=1;
     #1; val=readdata;
     @(negedge clk); read=0;
   end
 endtask
 task wait_valid;
   integer timeout;
   reg [31:0] s;
   begin
     timeout=0; s=0;
     while(!s[1] && timeout<2000) begin rd(4,s); timeout=timeout+1; end
     if(!s[1]) $fatal(1,"timeout");
   end
 endtask
 initial begin
   $dumpfile("tile.vcd"); $dumpvars(0,tb_csr);
   repeat(3) @(negedge clk); rst_n=1;
   for(trial=0;trial<12;trial=trial+1) begin
     n=trial==0 ? 1 : trial==1 ? 256 : 3+trial*2;
     wr(0,2); wr(8,n); wr(12,trial%4);
     for(k=0;k<n;k=k+1) begin
       a[k]=($random(seed)&255)-128;
       if(trial==0) a[k]=-128;
       wr(16,k); wr(24,a[k]);
     end
     for(j=0;j<4;j=j+1) begin
       b[j]=j*5-10; m[j]=j+1; sh[j]=trial%6;
       wr(20,j); wr(32,b[j]); wr(36,m[j]); wr(40,sh[j]);
       for(k=0;k<n;k=k+1) begin
         w[j][k]=($random(seed)&255)-128;
         if(trial==0) w[j][k]=j==0 ? -128 : 127;
         wr(16,k); wr(28,w[j][k]);
       end
     end
     wr(0,1); wait_valid;
     // Attempted config mutation while busy must be rejected.
     wr(12,3); rd(4,got);
     if(!got[3]) $fatal(1,"busy write must set error");
     for(j=0;j<4;j=j+1) begin
       expected=b[j];
       for(k=0;k<n;k=k+1) expected=expected+a[k]*w[j][k];
       rd(52,got);
       if($signed(got)!=expected) $fatal(1,"acc t=%0d lane=%0d got=%0d expected=%0d",trial,j,$signed(got),expected);
       scaled=expected*m[j]; sign=scaled<0 ? -1 : 1;
       if(scaled<0) scaled=-scaled;
       if(sh[j]>0) scaled=(scaled+(1<<(sh[j]-1)))>>sh[j];
       scaled=scaled*sign;
       if((trial%4)>=2 && scaled<0) scaled=0;
       if(scaled>127) scaled=127;
       if(scaled< -128) scaled=-128;
       rd(48,got);
       if($signed(got)!=scaled) $fatal(1,"quant mismatch");
       // Output must remain stable without POP, including model/lane tag.
       repeat(3) @(negedge clk);
       rd(52,got); if($signed(got)!=expected) $fatal(1,"backpressure");
       rd(56,got);
       if(got!={15'd0,(trial%2==1),16'(j)}) $fatal(1,"tag mismatch");
       wr(0,4);
     end
     repeat(3) @(negedge clk);
     rd(4,got); if(!got[2] || got[0]) $fatal(1,"completion status");
   end
   wr(0,2); wr(8,0); rd(4,got);
   if(!got[3]) $fatal(1,"invalid length");
   wr(0,2); wr(8,257); rd(4,got);
   if(!got[3]) $fatal(1,"oversized length");
   wr(0,2); wr(20,0); wr(40,63);
   repeat(3) @(negedge clk); rd(4,got);
   if(!got[3]) $fatal(1,"invalid shift");
   wr(0,2); wr(36,32'h80000000);
   repeat(3) @(negedge clk); rd(4,got);
   if(!got[3]) $fatal(1,"invalid multiplier");
   wr(0,2); byteenable=1; wr(8,1); byteenable=15; rd(4,got);
   if(!got[3]) $fatal(1,"partial write rejection");
   $display("PASS: 12 tiles, 48 dot products; reload, signed extremes, ReLU, saturation, backpressure, busy lock, CSR errors");
   $finish;
 end
 initial begin #10000000; $fatal(1,"watchdog"); end
endmodule
