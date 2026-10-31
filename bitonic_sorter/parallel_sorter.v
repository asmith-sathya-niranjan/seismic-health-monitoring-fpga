module parallel_sorter #(parameter DATA_WIDTH = 8) (
    input clk,
    input rst_n, // Active-low reset
    input [1:0] sel, // Selection input for multiplexers (00, 01, or 10)
    input [DATA_WIDTH-1:0] i0, i1, i2, i3, i4, i5, i6, i7, // 8 unsorted inputs
    output [DATA_WIDTH-1:0] x0, x1, x2, x3, x4, x5, x6, x7 // 8 sorted outputs
);
    /*
     * 3-STAGE BITONIC SORTER
     * 
     * This assumes inputs are PRE-SORTED into a bitonic sequence BEFORE entering.
     * The testbench should sort the inputs first to create:
     *   - Lower half ascending: i0 <= i1 <= i2 <= i3
     *   - Upper half descending: i4 >= i5 >= i6 >= i7
     * 
     * If your inputs are random, you need to sort them first!
     * 
     * Stage 0 (sel=00): Distance 4 comparisons
     * Stage 1 (sel=01): Distance 2 comparisons  
     * Stage 2 (sel=10): Distance 1 comparisons (final sorted output)
     */
    
    // Wires to hold the outputs of the PEs
    wire [DATA_WIDTH-1:0] pe1_s1, pe1_s2;
    wire [DATA_WIDTH-1:0] pe2_s1, pe2_s2;
    wire [DATA_WIDTH-1:0] pe3_s1, pe3_s2;
    wire [DATA_WIDTH-1:0] pe4_s1, pe4_s2;
    
    // Registers corresponding to the x0..x7 outputs
    reg [DATA_WIDTH-1:0] r_x0, r_x1, r_x2, r_x3, r_x4, r_x5, r_x6, r_x7;
   
    // Internal wires for bitonic pre-sorted inputs
    wire [DATA_WIDTH-1:0] sorted_i0, sorted_i1, sorted_i2, sorted_i3;
    wire [DATA_WIDTH-1:0] sorted_i4, sorted_i5, sorted_i6, sorted_i7;
    
    // ===== PRE-SORT INPUTS INTO BITONIC SEQUENCE =====
    // Sort lower half (ascending): i0,i1,i2,i3 -> sorted_i0,sorted_i1,sorted_i2,sorted_i3
    // Sort upper half (descending): i4,i5,i6,i7 -> sorted_i4,sorted_i5,sorted_i6,sorted_i7
    
    // Simple sorting network for 4 elements (lower half - ascending)
    wire [DATA_WIDTH-1:0] l_stage1_0 = (i0 < i1) ? i0 : i1;
    wire [DATA_WIDTH-1:0] l_stage1_1 = (i0 < i1) ? i1 : i0;
    wire [DATA_WIDTH-1:0] l_stage1_2 = (i2 < i3) ? i2 : i3;
    wire [DATA_WIDTH-1:0] l_stage1_3 = (i2 < i3) ? i3 : i2;
    
    wire [DATA_WIDTH-1:0] l_stage2_0 = (l_stage1_0 < l_stage1_2) ? l_stage1_0 : l_stage1_2;
    wire [DATA_WIDTH-1:0] l_stage2_1 = (l_stage1_1 < l_stage1_3) ? l_stage1_1 : l_stage1_3;
    wire [DATA_WIDTH-1:0] l_stage2_2 = (l_stage1_0 < l_stage1_2) ? l_stage1_2 : l_stage1_0;
    wire [DATA_WIDTH-1:0] l_stage2_3 = (l_stage1_1 < l_stage1_3) ? l_stage1_3 : l_stage1_1;
    
    // After stage 2: _0 is the global min and _3 the global max. Only the
    // middle pair (_1, _2) is still unordered, so the last compare is (_1, _2).
    assign sorted_i0 = l_stage2_0;
    assign sorted_i1 = (l_stage2_1 < l_stage2_2) ? l_stage2_1 : l_stage2_2;
    assign sorted_i2 = (l_stage2_1 < l_stage2_2) ? l_stage2_2 : l_stage2_1;
    assign sorted_i3 = l_stage2_3;
    
    // Simple sorting network for 4 elements (upper half - descending)
    wire [DATA_WIDTH-1:0] u_stage1_0 = (i4 > i5) ? i4 : i5;
    wire [DATA_WIDTH-1:0] u_stage1_1 = (i4 > i5) ? i5 : i4;
    wire [DATA_WIDTH-1:0] u_stage1_2 = (i6 > i7) ? i6 : i7;
    wire [DATA_WIDTH-1:0] u_stage1_3 = (i6 > i7) ? i7 : i6;
    
    wire [DATA_WIDTH-1:0] u_stage2_0 = (u_stage1_0 > u_stage1_2) ? u_stage1_0 : u_stage1_2;
    wire [DATA_WIDTH-1:0] u_stage2_1 = (u_stage1_1 > u_stage1_3) ? u_stage1_1 : u_stage1_3;
    wire [DATA_WIDTH-1:0] u_stage2_2 = (u_stage1_0 > u_stage1_2) ? u_stage1_2 : u_stage1_0;
    wire [DATA_WIDTH-1:0] u_stage2_3 = (u_stage1_1 > u_stage1_3) ? u_stage1_3 : u_stage1_1;
    
    // Same idea, descending: _0 is the global max, _3 the global min.
    assign sorted_i4 = u_stage2_0;
    assign sorted_i5 = (u_stage2_1 > u_stage2_2) ? u_stage2_1 : u_stage2_2;
    assign sorted_i6 = (u_stage2_1 > u_stage2_2) ? u_stage2_2 : u_stage2_1;
    assign sorted_i7 = u_stage2_3;
    
    // Assign final module outputs from internal registers
    assign x0 = r_x0;
    assign x1 = r_x1;
    assign x2 = r_x2;
    assign x3 = r_x3;
    assign x4 = r_x4;
    assign x5 = r_x5;
    assign x6 = r_x6;
    assign x7 = r_x7;
   
    // Input multiplexers for PE1 - now use sorted inputs
    wire [DATA_WIDTH-1:0] pe1_in_a, pe1_in_b;
    assign pe1_in_a = (sel == 2'b00) ? sorted_i0 : // Stage 0: sorted_i0
                      (sel == 2'b01) ? r_x0 :       // Stage 1: x0
                      (sel == 2'b10) ? r_x0 :       // Stage 2: x0
                      8'hXX;
    assign pe1_in_b = (sel == 2'b00) ? sorted_i4 : // Stage 0: sorted_i4 (distance 4)
                      (sel == 2'b01) ? r_x2 :       // Stage 1: x2 (distance 2)
                      (sel == 2'b10) ? r_x1 :       // Stage 2: x1 (distance 1)
                      8'hXX;
    
    // Input multiplexers for PE2
    wire [DATA_WIDTH-1:0] pe2_in_a, pe2_in_b;
    assign pe2_in_a = (sel == 2'b00) ? sorted_i1 : // Stage 0: sorted_i1
                      (sel == 2'b01) ? r_x1 :       // Stage 1: x1
                      (sel == 2'b10) ? r_x2 :       // Stage 2: x2
                      8'hXX;
    assign pe2_in_b = (sel == 2'b00) ? sorted_i5 : // Stage 0: sorted_i5 (distance 4)
                      (sel == 2'b01) ? r_x3 :       // Stage 1: x3 (distance 2)
                      (sel == 2'b10) ? r_x3 :       // Stage 2: x3 (distance 1)
                      8'hXX;
    
    // Input multiplexers for PE3
    wire [DATA_WIDTH-1:0] pe3_in_a, pe3_in_b;
    assign pe3_in_a = (sel == 2'b00) ? sorted_i2 : // Stage 0: sorted_i2
                      (sel == 2'b01) ? r_x4 :       // Stage 1: x4
                      (sel == 2'b10) ? r_x4 :       // Stage 2: x4
                      8'hXX;
    assign pe3_in_b = (sel == 2'b00) ? sorted_i6 : // Stage 0: sorted_i6 (distance 4)
                      (sel == 2'b01) ? r_x6 :       // Stage 1: x6 (distance 2)
                      (sel == 2'b10) ? r_x5 :       // Stage 2: x5 (distance 1)
                      8'hXX;
    
    // Input multiplexers for PE4
    wire [DATA_WIDTH-1:0] pe4_in_a, pe4_in_b;
    assign pe4_in_a = (sel == 2'b00) ? sorted_i3 : // Stage 0: sorted_i3
                      (sel == 2'b01) ? r_x5 :       // Stage 1: x5
                      (sel == 2'b10) ? r_x6 :       // Stage 2: x6
                      8'hXX;
    assign pe4_in_b = (sel == 2'b00) ? sorted_i7 : // Stage 0: sorted_i7 (distance 4)
                      (sel == 2'b01) ? r_x7 :       // Stage 1: x7 (distance 2)
                      (sel == 2'b10) ? r_x7 :       // Stage 2: x7 (distance 1)
                      8'hXX;
    
    // Instantiate PEs (each PE outputs S1=min, S2=max)
    pe #(.DATA_WIDTH(DATA_WIDTH)) PE1 (.A(pe1_in_a), .B(pe1_in_b), .S1(pe1_s1), .S2(pe1_s2));
    pe #(.DATA_WIDTH(DATA_WIDTH)) PE2 (.A(pe2_in_a), .B(pe2_in_b), .S1(pe2_s1), .S2(pe2_s2));
    pe #(.DATA_WIDTH(DATA_WIDTH)) PE3 (.A(pe3_in_a), .B(pe3_in_b), .S1(pe3_s1), .S2(pe3_s2));
    pe #(.DATA_WIDTH(DATA_WIDTH)) PE4 (.A(pe4_in_a), .B(pe4_in_b), .S1(pe4_s1), .S2(pe4_s2));
   
    // Output routing - follows the bitonic merge pattern
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_x0 <= 0; r_x1 <= 0; r_x2 <= 0; r_x3 <= 0;
            r_x4 <= 0; r_x5 <= 0; r_x6 <= 0; r_x7 <= 0;
        end else begin
            case (sel)
                2'b00: begin // Stage 0: Distance 4 comparisons
                    r_x0 <= pe1_s1; // min(sorted_i0, sorted_i4)
                    r_x1 <= pe2_s1; // min(sorted_i1, sorted_i5)
                    r_x2 <= pe3_s1; // min(sorted_i2, sorted_i6)
                    r_x3 <= pe4_s1; // min(sorted_i3, sorted_i7)
                    r_x4 <= pe1_s2; // max(sorted_i0, sorted_i4)
                    r_x5 <= pe2_s2; // max(sorted_i1, sorted_i5)
                    r_x6 <= pe3_s2; // max(sorted_i2, sorted_i6)
                    r_x7 <= pe4_s2; // max(sorted_i3, sorted_i7)
                end
                
                2'b01: begin // Stage 1: Distance 2 comparisons
                    r_x0 <= pe1_s1; // min(x0, x2)
                    r_x1 <= pe2_s1; // min(x1, x3)
                    r_x2 <= pe1_s2; // max(x0, x2)
                    r_x3 <= pe2_s2; // max(x1, x3)
                    r_x4 <= pe3_s1; // min(x4, x6)
                    r_x5 <= pe4_s1; // min(x5, x7)
                    r_x6 <= pe3_s2; // max(x4, x6)
                    r_x7 <= pe4_s2; // max(x5, x7)
                end
                
                2'b10: begin // Stage 2: Distance 1 comparisons (FINAL SORTED OUTPUT)
                    r_x0 <= pe1_s1; // min(x0, x1)
                    r_x1 <= pe1_s2; // max(x0, x1)
                    r_x2 <= pe2_s1; // min(x2, x3)
                    r_x3 <= pe2_s2; // max(x2, x3)
                    r_x4 <= pe3_s1; // min(x4, x5)
                    r_x5 <= pe3_s2; // max(x4, x5)
                    r_x6 <= pe4_s1; // min(x6, x7)
                    r_x7 <= pe4_s2; // max(x6, x7)
                end
                
                default: begin
                    r_x0 <= r_x0; r_x1 <= r_x1; r_x2 <= r_x2; r_x3 <= r_x3;
                    r_x4 <= r_x4; r_x5 <= r_x5; r_x6 <= r_x6; r_x7 <= r_x7;
                end
            endcase
        end
    end
   
endmodule

/*
 * COMPLETE SORTER - Works with ANY arbitrary inputs!
 * 
 * The inputs are automatically pre-sorted into a bitonic sequence:
 *   - Lower 4 elements sorted ascending
 *   - Upper 4 elements sorted descending
 * Then the 3-stage bitonic merge produces the final sorted output.
 * 
 * Clock sequence:
 *   Clock 0: sel = 2'b00 (Stage 0)
 *   Clock 1: sel = 2'b01 (Stage 1)
 *   Clock 2: sel = 2'b10 (Stage 2 - SORTED OUTPUT!)
 * 
 * Example: Input [10, 25, 8, 90, 5, 35, 70, 42]
 * After Clock 2: Output [5, 8, 10, 25, 35, 42, 70, 90]
 */