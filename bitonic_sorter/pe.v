`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    19:49:20 09/18/2025 
// Design Name: 
// Module Name:    pe 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////

module pe #(parameter DATA_WIDTH = 8) (
    input [DATA_WIDTH-1:0] A,
    input [DATA_WIDTH-1:0] B,
    output reg [DATA_WIDTH-1:0] S1, // S1 = min(A, B)
    output reg [DATA_WIDTH-1:0] S2  // S2 = max(A, B)
);

    // This always block performs the comparison and assignment.
    // It is a combinational block that updates whenever A or B changes.
    always @(*) begin
        if (A <= B) begin
            S1 = A;
            S2 = B;
        end else begin
            S1 = B;
            S2 = A;
        end
    end

endmodule