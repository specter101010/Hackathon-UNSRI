`timescale 1ns/1ps

module dg_top_64 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  address,
    input  wire        read,
    input  wire        write,
    input  wire [3:0]  byteenable,
    input  wire [31:0] writedata,

    output wire [31:0] readdata,
    output wire        waitrequest,
    output wire        irq
);

    dg_csr_top #(
        .LANES (64),
        .DEPTH (256)
    ) u_dualguard (
        .clk         (clk),
        .rst_n       (rst_n),
        .address     (address),
        .read        (read),
        .write       (write),
        .byteenable  (byteenable),
        .writedata   (writedata),
        .readdata    (readdata),
        .waitrequest (waitrequest),
        .irq         (irq)
    );

endmodule