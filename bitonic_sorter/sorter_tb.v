////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer:
//
// Create Date:   19:55:00 09/18/2025
// Design Name:   parallel_sorter
// Module Name:   sorter_tb
// Project Name:  ParallelSorter
// Target Device:  
// Tool versions:  
// Description: 
//
// Verilog Test Fixture created by ISE for module: parallel_sorter
//
// Dependencies:
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
////////////////////////////////////////////////////////////////////////////////

// This testbench module simulates the parallel_sorter to verify its functionality.
`timescale 1ns / 1ps

module sorter_tb;

    // Define parameters
    parameter DATA_WIDTH = 8;
    parameter CLK_PERIOD = 10;

    // Declare signals for connecting to the Device Under Test (DUT)
    reg clk;
    reg rst_n;
    reg [1:0] sel;

    reg [DATA_WIDTH-1:0] i0, i1, i2, i3, i4, i5, i6, i7;
    wire [DATA_WIDTH-1:0] x0, x1, x2, x3, x4, x5, x6, x7;

    // Instantiate the parallel_sorter
    parallel_sorter #(.DATA_WIDTH(DATA_WIDTH)) DUT (
        .clk(clk),
        .rst_n(rst_n),
        .sel(sel),
        .i0(i0),
        .i1(i1),
        .i2(i2),
        .i3(i3),
        .i4(i4),
        .i5(i5),
        .i6(i6),
        .i7(i7),
        .x0(x0),
        .x1(x1),
        .x2(x2),
        .x3(x3),
        .x4(x4),
        .x5(x5),
        .x6(x6),
        .x7(x7)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Stimulus generation and monitoring
    initial begin
        // Print header for the output
        $display("---------------------------------------------------------");
        $display("Pipelined Sorter Simulation");
        $display("---------------------------------------------------------");
        $display("Time (ns) | sel | Inputs                                | Outputs");
        $display("---------------------------------------------------------");

        // Initial state
        rst_n = 0;
        sel = 2'b00;
        i0 = 8'd25; i1 = 8'd10; i2 = 8'd90; i3 = 8'd5;
        i4 = 8'd35; i5 = 8'd70; i6 = 8'd42; i7 = 8'd8;
        
        // Wait for a few clock cycles to apply reset
        @(posedge clk);
        #1;
        rst_n = 1;

        // Monitor outputs
        $monitor("%4t       |  %b  | %2d %2d %2d %2d %2d %2d %2d %2d | %2d %2d %2d %2d %2d %2d %2d %2d", 
                  $time, sel, i0, i1, i2, i3, i4, i5, i6, i7, x0, x1, x2, x3, x4, x5, x6, x7);

        // Stage 0: Initial input loading and first comparison
        @(posedge clk);
        #1; sel = 2'b00;

        // Stage 1: Second comparison stage
        @(posedge clk);
        #1; sel = 2'b01;

        // Stage 2: Final comparison and output stage
        @(posedge clk);
        #1; sel = 2'b10;

        // Wait to capture the final sorted output
        @(posedge clk);

        // End simulation
        #100;
        $finish;
    end

endmodule

