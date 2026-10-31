`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// Self-checking testbench for parallel_sorter (8 inputs, 3-clock folded sorter).
//
// Three phases, each compared against a reference insertion sort:
//   1. Exhaustive 0/1 vectors (all 2^8 patterns). Because the design is a pure
//      comparator network, the 0-1 principle says: if it sorts every 0/1 input,
//      it sorts every input.
//   2. Random full-range vectors.
//   3. Random small-range vectors (values 0..3) to stress duplicate handling.
//
// Prints "RESULT: PASS" or "RESULT: FAIL (<n> mismatches)" as its last line.
//------------------------------------------------------------------------------
module sorter_random_tb;

    parameter DATA_WIDTH  = 8;
    parameter N_RANDOM    = 20000;

    reg                   clk;
    reg                   rst_n;
    reg  [1:0]            sel;
    reg  [DATA_WIDTH-1:0] i0, i1, i2, i3, i4, i5, i6, i7;
    wire [DATA_WIDTH-1:0] x0, x1, x2, x3, x4, x5, x6, x7;

    parallel_sorter #(.DATA_WIDTH(DATA_WIDTH)) dut (
        .clk(clk), .rst_n(rst_n), .sel(sel),
        .i0(i0), .i1(i1), .i2(i2), .i3(i3), .i4(i4), .i5(i5), .i6(i6), .i7(i7),
        .x0(x0), .x1(x1), .x2(x2), .x3(x3), .x4(x4), .x5(x5), .x6(x6), .x7(x7)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer seed;
    integer n, v, k, a, b;
    integer errors, phase_errors, shown;
    reg [DATA_WIDTH-1:0] in_v  [0:7];
    reg [DATA_WIDTH-1:0] exp_v [0:7];
    reg [DATA_WIDTH-1:0] got_v [0:7];
    reg [DATA_WIDTH-1:0] tmp;
    reg                  bad;

    // Drive in_v[] into the DUT, run sel = 00 -> 01 -> 10 on three clock edges,
    // then compare x0..x7 with the reference sort.
    task run_one;
        begin
            i0 = in_v[0]; i1 = in_v[1]; i2 = in_v[2]; i3 = in_v[3];
            i4 = in_v[4]; i5 = in_v[5]; i6 = in_v[6]; i7 = in_v[7];

            // reference: insertion sort, ascending
            for (k = 0; k < 8; k = k + 1) exp_v[k] = in_v[k];
            for (a = 1; a < 8; a = a + 1) begin
                tmp = exp_v[a];
                b = a - 1;
                while (b >= 0 && exp_v[b] > tmp) begin
                    exp_v[b+1] = exp_v[b];
                    b = b - 1;
                end
                exp_v[b+1] = tmp;
            end

            @(negedge clk); sel = 2'b00;   // stage 0: distance-4 compare
            @(posedge clk);
            #1 sel = 2'b01;                // stage 1: distance-2 compare
            @(posedge clk);
            #1 sel = 2'b10;                // stage 2: distance-1 compare
            @(posedge clk);
            #1;

            got_v[0] = x0; got_v[1] = x1; got_v[2] = x2; got_v[3] = x3;
            got_v[4] = x4; got_v[5] = x5; got_v[6] = x6; got_v[7] = x7;

            bad = 0;
            for (k = 0; k < 8; k = k + 1)
                if (got_v[k] !== exp_v[k]) bad = 1;

            if (bad) begin
                errors       = errors + 1;
                phase_errors = phase_errors + 1;
                if (shown < 5) begin
                    shown = shown + 1;
                    $display("MISMATCH in=[%0d %0d %0d %0d %0d %0d %0d %0d] got=[%0d %0d %0d %0d %0d %0d %0d %0d] expected=[%0d %0d %0d %0d %0d %0d %0d %0d]",
                        in_v[0], in_v[1], in_v[2], in_v[3], in_v[4], in_v[5], in_v[6], in_v[7],
                        got_v[0], got_v[1], got_v[2], got_v[3], got_v[4], got_v[5], got_v[6], got_v[7],
                        exp_v[0], exp_v[1], exp_v[2], exp_v[3], exp_v[4], exp_v[5], exp_v[6], exp_v[7]);
                end
            end
        end
    endtask

    initial begin
        seed   = 1;
        errors = 0;
        shown  = 0;
        sel    = 2'b11;                    // hold
        rst_n  = 0;
        i0 = 0; i1 = 0; i2 = 0; i3 = 0; i4 = 0; i5 = 0; i6 = 0; i7 = 0;
        #12 rst_n = 1;

        // Phase 1: exhaustive 0/1
        phase_errors = 0;
        for (v = 0; v < 256; v = v + 1) begin
            for (k = 0; k < 8; k = k + 1) in_v[k] = (v >> k) & 1;
            run_one;
        end
        $display("phase 1  exhaustive 0/1 vectors : %5d run, %0d failed", 256, phase_errors);

        // Phase 2: random, full range
        phase_errors = 0;
        for (n = 0; n < N_RANDOM; n = n + 1) begin
            for (k = 0; k < 8; k = k + 1) in_v[k] = $random(seed);
            run_one;
        end
        $display("phase 2  random full-range      : %5d run, %0d failed", N_RANDOM, phase_errors);

        // Phase 3: random, small range (many duplicates)
        phase_errors = 0;
        for (n = 0; n < N_RANDOM; n = n + 1) begin
            for (k = 0; k < 8; k = k + 1) in_v[k] = $random(seed) & 3;
            run_one;
        end
        $display("phase 3  random small-range 0..3: %5d run, %0d failed", N_RANDOM, phase_errors);

        if (errors == 0) $display("RESULT: PASS");
        else             $display("RESULT: FAIL (%0d mismatches)", errors);
        $finish;
    end

endmodule
