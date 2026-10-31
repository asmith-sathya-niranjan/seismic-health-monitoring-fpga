`timescale 1ns / 1ps

module top_shm_system (
    input        clk,
    input        btnC,
    input  [3:0] sw,
    inout        i2c_sda,
    output       i2c_scl,
    output [6:0] seg,
    output [3:0] an,
    output [15:0] led,
    output       servo,
    input        hx711_dout,
    output       hx711_sck
);

    wire rst = btnC;

    // =========================================================================
    // ACCELEROMETER SECTION
    // =========================================================================
    reg  [6:0] axi_addr;
    reg        axi_ren, axi_wen;
    reg  [7:0] axi_wdata;
    wire [7:0] axi_rdata;
    wire       axi_ready, axi_rvalid;

    reg [7:0] buffer [0:7];
    reg [2:0] ptr;
    reg       all_done;

    localparam MS_WAKE_WAIT=3'd0, MS_WAKE_GO=3'd1, MS_WAKE_DONE=3'd2;
    localparam MS_READ_WAIT=3'd3, MS_READ_GO=3'd4, MS_READ_DATA=3'd5;
    localparam MS_IDLE=3'd6;
    reg [2:0] ms;

    always @(posedge clk) begin
        if (rst) begin
            ms <= MS_WAKE_WAIT; ptr <= 0; all_done <= 0;
            axi_ren <= 0; axi_wen <= 0;
        end else begin
            axi_wen <= 0; axi_ren <= 0;
            case (ms)
                MS_WAKE_WAIT: if (axi_ready) begin
                    axi_addr <= 7'h68; axi_wdata <= 8'h00;
                    axi_wen <= 1; ms <= MS_WAKE_GO;
                end
                MS_WAKE_GO:   if (!axi_ready) ms <= MS_WAKE_DONE;
                MS_WAKE_DONE: if (axi_ready)  ms <= MS_READ_WAIT;
                MS_READ_WAIT: if (axi_ready && !all_done) begin
                    axi_addr  <= 7'h68;
                    axi_wdata <= 8'h3B + {5'b0, ptr};
                    axi_ren   <= 1; ms <= MS_READ_GO;
                end else if (all_done) ms <= MS_IDLE;
                MS_READ_GO:   if (!axi_ready) ms <= MS_READ_DATA;
                MS_READ_DATA: if (axi_rvalid) begin
                    buffer[ptr] <= axi_rdata;
                    if (ptr == 3'd7) all_done <= 1;
                    else ptr <= ptr + 1;
                    ms <= MS_READ_WAIT;
                end
                MS_IDLE: ms <= MS_IDLE;
            endcase
        end
    end

    axi_i2c_bridge i2c_phy (
        .clk(clk), .rst(rst), .addr(axi_addr),
        .write_en(axi_wen), .read_en(axi_ren), .wdata(axi_wdata),
        .rdata(axi_rdata), .ready(axi_ready), .rvalid(axi_rvalid),
        .scl(i2c_scl), .sda(i2c_sda)
    );

    reg [7:0] sorted [0:7];
    reg [7:0] median;
    reg [2:0] si, sj;
    reg [1:0] sort_st;
    integer k;

    always @(posedge clk) begin
        if (rst) begin
            sort_st <= 0; si <= 0; sj <= 0; median <= 0;
        end else case (sort_st)
            2'd0: if (all_done) begin
                for (k=0; k<8; k=k+1) sorted[k] <= buffer[k];
                si <= 0; sj <= 0; sort_st <= 1;
            end
            2'd1: begin
                if (sorted[sj] > sorted[sj+1]) begin
                    sorted[sj]   <= sorted[sj+1];
                    sorted[sj+1] <= sorted[sj];
                end
                if (sj == 3'd6) begin
                    sj <= 0;
                    if (si == 3'd6) sort_st <= 2;
                    else si <= si + 1;
                end else sj <= sj + 1;
            end
            2'd2: begin median <= sorted[4]; sort_st <= 2'd2; end
            default: sort_st <= 0;
        endcase
    end

    wire [7:0] disp_val = sw[3] ? buffer[sw[2:0]] : median;
    display_controller dc (
        .clk(clk), .val(disp_val), .seg(seg), .an(an)
    );

    // =========================================================================
    // HX711 SECTION
    // =========================================================================
    wire [23:0] weight_raw;
    wire        data_ready;

    hx711_reader u_hx711 (
        .clk        (clk),
        .rst        (rst),
        .dout       (hx711_dout),
        .pd_sck     (hx711_sck),
        .weight_raw (weight_raw),
        .data_ready (data_ready)
    );

    // ── Tare: latch the very first valid reading as baseline ─────────────────
    // Using just ONE reading to avoid accumulation bugs.
    // The HX711 idles with dout HIGH - first reading after dout goes LOW
    // is the resting load cell value.
    reg [23:0] tare       = 0;
    reg        tare_ready = 0;

    always @(posedge clk) begin
        if (rst) begin
            tare       <= 0;
            tare_ready <= 0;
        end else if (!tare_ready && data_ready) begin
            // Take the very first reading as tare - no averaging needed
            tare       <= weight_raw;
            tare_ready <= 1;
        end
    end

    // ── Latch last weight so comparison is stable between data_ready pulses ──
    reg [23:0] weight_latched = 0;
    always @(posedge clk) begin
        if (rst)
            weight_latched <= 0;
        else if (data_ready)
            weight_latched <= weight_raw;
    end

    // ── Signed difference using latched stable value ──────────────────────────
    wire signed [24:0] delta =
        $signed({1'b0, weight_latched}) - $signed({1'b0, tare});

    // ── THRESHOLD: how much load cell must move to count as a press ───────────
    // If LEDs never turn OFF when pressing → DECREASE this number
    // If LEDs flicker without pressing     → INCREASE this number
    // Your load cell is likely small range - start low and adjust
    localparam signed [24:0] THRESHOLD = 25'sd2000;

    // pressed is stable (not just 1-cycle wide) because it uses weight_latched
    wire pressed = tare_ready &&
                   ((delta > THRESHOLD) || (delta < -THRESHOLD));

    // ── Servo arm latch: stays armed after first press, reset by btnC ─────────
    reg servo_armed = 0;
    always @(posedge clk) begin
        if (rst)
            servo_armed <= 0;
        else if (pressed)
            servo_armed <= 1;
    end

    // =========================================================================
    // LEDs
    // LED[7:0]   = accelerometer disp_val
    // LED[11:8]  = 0000 always
    // LED[15:12] = HX711 status:
    //              Calibrating  → 0000 (all off, ~1 reading wait)
    //              Resting      → 1111 (all ON)
    //              Pressed      → 0000 (all OFF - inverted logic)
    // =========================================================================
    reg [15:0] led_out = 16'h0000;
    assign led = led_out;

    always @(posedge clk) begin
        led_out[7:0]  <= disp_val;
        led_out[11:8] <= 4'b0000;
        if (!tare_ready)
            led_out[15:12] <= 4'b0000;   // calibrating
        else if (pressed)
            led_out[15:12] <= 4'b0000;   // pressed → OFF
        else
            led_out[15:12] <= 4'b1111;   // resting → ON
    end

    // =========================================================================
    // SERVO
    // Before first press: output is CONSTANT 0 (servo gets no signal, stays still)
    // After first press:  normal PWM from accelerometer median
    // btnC resets armed state so servo locks again
    // =========================================================================
    localparam BASE_PULSE = 21'd50_000;
    localparam MAX_PULSE  = 21'd250_000;
    localparam MULTIPLIER = 21'd784;

    wire [20:0] raw_pulse = BASE_PULSE + ({13'd0, median} * MULTIPLIER);
    wire [20:0] pulse_val = (raw_pulse > MAX_PULSE) ? MAX_PULSE : raw_pulse;

    reg [20:0] pwm_cnt = 0;
    always @(posedge clk) begin
        if (rst) pwm_cnt <= 0;
        else if (pwm_cnt == 21'd1_999_999) pwm_cnt <= 0;
        else pwm_cnt <= pwm_cnt + 1;
    end

    // KEY FIX: when not armed, assign servo = 0 (no PWM at all, not even BASE)
    // A servo with no signal holds its last position mechanically
    // - it will NOT move without a PWM signal
    assign servo = servo_armed ? (pwm_cnt < pulse_val) : 1'b0;

endmodule


// =============================================================================
// HX711 READER
// =============================================================================
module hx711_reader (
    input  wire        clk,
    input  wire        rst,
    input  wire        dout,
    output reg         pd_sck,
    output reg [23:0]  weight_raw,
    output reg         data_ready
);
    // 100MHz / 200 = 500kHz SCK
    parameter CLK_DIV = 100;

    reg [7:0] clk_cnt = 0;
    reg       sck_r   = 0;

    always @(posedge clk) begin
        if (clk_cnt == CLK_DIV - 1) begin
            clk_cnt <= 0;
            sck_r   <= ~sck_r;
        end else
            clk_cnt <= clk_cnt + 1;
    end

    wire sck_rise = (clk_cnt == CLK_DIV - 1) &&  sck_r;
    wire sck_fall = (clk_cnt == CLK_DIV - 1) && ~sck_r;

    localparam IDLE=2'd0, READ=2'd1, PULSE=2'd2, DONE=2'd3;
    reg [1:0]  state   = IDLE;
    reg [4:0]  bit_cnt = 0;
    reg [23:0] shift   = 0;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state      <= IDLE;
            pd_sck     <= 0;
            bit_cnt    <= 0;
            data_ready <= 0;
            weight_raw <= 0;
            shift      <= 0;
        end else begin
            data_ready <= 0;
            case (state)
                IDLE: begin
                    pd_sck  <= 0;
                    bit_cnt <= 0;
                    shift   <= 0;
                    if (!dout) state <= READ;  // HX711 ready when DOUT goes LOW
                end
                READ: begin
                    if (sck_fall) pd_sck <= 1;
                    if (sck_rise) begin
                        pd_sck  <= 0;
                        shift   <= {shift[22:0], dout};
                        bit_cnt <= bit_cnt + 1;
                        if (bit_cnt == 5'd23) state <= PULSE;
                    end
                end
                PULSE: begin
                    if (sck_fall) pd_sck <= 1;
                    if (sck_rise) begin
                        pd_sck <= 0;
                        state  <= DONE;
                    end
                end
                DONE: begin
                    weight_raw <= shift;
                    data_ready <= 1;
                    state      <= IDLE;
                end
            endcase
        end
    end
endmodule


// =============================================================================
// AXI-I2C BRIDGE
// =============================================================================
module axi_i2c_bridge (
    input        clk, rst,
    input  [6:0] addr,
    input        write_en, read_en,
    input  [7:0] wdata,
    output reg [7:0] rdata,
    output reg   ready, rvalid,
    output reg   scl,
    inout        sda
);
    localparam PH0=10'd0, PH1=10'd250, PH2=10'd500, PH3=10'd750;
    reg [9:0] counter;
    wire ph0=(counter==PH0), ph1=(counter==PH1),
         ph2=(counter==PH2), ph3=(counter==PH3);

    reg sda_out, sda_oe;
    assign sda = sda_oe ? sda_out : 1'bz;

    reg sda_s1, sda_s2;
    always @(posedge clk) begin sda_s1 <= sda; sda_s2 <= sda_s1; end

    localparam S_IDLE=0, S_START=1, S_SEND=2, S_ACK=3,
               S_REP_START=4, S_RECV=5, S_MACK=6, S_STOP=7, S_ERR=8;
    reg [3:0] state;
    reg [7:0] shift_reg;
    reg [2:0] bit_cnt;
    reg [1:0] seq;
    reg       is_read, sent_regptr, sent_read_addr;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE; counter <= 0; scl <= 1;
            sda_out <= 1; sda_oe <= 1; ready <= 1; rvalid <= 0; rdata <= 0;
            is_read <= 0; sent_regptr <= 0; sent_read_addr <= 0;
            shift_reg <= 0; bit_cnt <= 0; seq <= 0;
        end else begin
            rvalid <= 0;
            case (state)
                S_IDLE: begin
                    ready <= 1; scl <= 1; sda_out <= 1; sda_oe <= 1;
                    counter <= 0; seq <= 0;
                    if (write_en || read_en) begin
                        is_read <= read_en; sent_regptr <= 0;
                        sent_read_addr <= 0;
                        shift_reg <= {addr, 1'b0}; bit_cnt <= 3'd7;
                        ready <= 0; state <= S_START;
                    end
                end
                S_START: begin
                    counter <= counter + 1;
                    case (seq)
                        2'd0: begin
                            sda_oe<=1; sda_out<=0; seq<=1; counter<=0;
                        end
                        2'd1: if (counter==PH1) begin
                            scl<=0; counter<=0; seq<=2;
                        end
                        2'd2: if (counter>=10) begin
                            counter<=0; state<=S_SEND;
                        end
                        default: state <= S_IDLE;
                    endcase
                end
                S_SEND: begin
                    counter <= counter + 1;
                    if (ph0) begin scl<=0; sda_oe<=1; sda_out<=shift_reg[7]; end
                    if (ph1) scl <= 1;
                    if (ph3) begin
                        shift_reg <= {shift_reg[6:0], 1'b0}; counter <= 0;
                        if (bit_cnt==0) state <= S_ACK;
                        else bit_cnt <= bit_cnt - 1;
                    end
                end
                S_ACK: begin
                    counter <= counter + 1;
                    if (ph0) begin scl<=0; sda_oe<=0; end
                    if (ph1) scl <= 1;
                    if (ph2) begin
                        if (sda_s2) begin state <= S_ERR; counter <= 0; end
                    end
                    if (ph3 && (state == S_ACK)) begin
                        counter <= 0;
                        if (!sent_regptr) begin
                            sent_regptr<=1; shift_reg<=wdata;
                            bit_cnt<=3'd7; state<=S_SEND;
                        end else if (!is_read) begin
                            seq<=0; state<=S_STOP;
                        end else if (!sent_read_addr) begin
                            seq<=0; state<=S_REP_START;
                        end else begin
                            bit_cnt<=3'd7; state<=S_RECV;
                        end
                    end
                end
                S_REP_START: begin
                    counter <= counter + 1;
                    case (seq)
                        2'd0: begin
                            scl<=0; sda_oe<=1; sda_out<=1;
                            if (counter==PH1) begin
                                scl<=1; counter<=0; seq<=1;
                            end
                        end
                        2'd1: if (counter==PH1) begin
                            sda_out<=0; counter<=0; seq<=2;
                        end
                        2'd2: if (counter==PH1) begin
                            scl<=0; sent_read_addr<=1;
                            shift_reg<={addr,1'b1}; bit_cnt<=3'd7;
                            counter<=0; state<=S_SEND;
                        end
                        default: state <= S_IDLE;
                    endcase
                end
                S_RECV: begin
                    counter <= counter + 1;
                    if (ph0) begin scl<=0; sda_oe<=0; end
                    if (ph1) scl <= 1;
                    if (ph3) begin
                        counter <= 0;
                        if (bit_cnt == 0) begin
                            rdata  <= {shift_reg[6:0], sda_s2};
                            rvalid <= 1;
                            state  <= S_MACK;
                        end else begin
                            shift_reg <= {shift_reg[6:0], sda_s2};
                            bit_cnt   <= bit_cnt - 1;
                        end
                    end
                end
                S_MACK: begin
                    counter <= counter + 1;
                    if (ph0) begin scl<=0; sda_oe<=1; sda_out<=1; end
                    if (ph1) scl <= 1;
                    if (ph3) begin counter<=0; seq<=0; state<=S_STOP; end
                end
                S_STOP: begin
                    counter <= counter + 1;
                    case (seq)
                        2'd0: begin
                            scl<=0; sda_oe<=1; sda_out<=0;
                            if (counter==PH1) begin
                                scl<=1; counter<=0; seq<=1;
                            end
                        end
                        2'd1: if (counter==PH1) begin
                            sda_out<=1; counter<=0; seq<=2;
                        end
                        2'd2: if (counter==PH1) begin
                            counter<=0; state<=S_IDLE;
                        end
                        default: state <= S_IDLE;
                    endcase
                end
                S_ERR: begin
                    scl<=0; sda_oe<=1; sda_out<=1;
                    counter<=0; seq<=0; state<=S_STOP;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule


// =============================================================================
// DISPLAY CONTROLLER
// =============================================================================
module display_controller (
    input        clk,
    input  [7:0] val,
    output reg [6:0] seg,
    output reg [3:0] an
);
    reg [3:0] bcd_h, bcd_t, bcd_u;
    integer   i;
    always @(*) begin
        bcd_h = 0; bcd_t = 0; bcd_u = 0;
        for (i=7; i>=0; i=i-1) begin
            if (bcd_h >= 5) bcd_h = bcd_h + 3;
            if (bcd_t >= 5) bcd_t = bcd_t + 3;
            if (bcd_u >= 5) bcd_u = bcd_u + 3;
            bcd_h = {bcd_h[2:0], bcd_t[3]};
            bcd_t = {bcd_t[2:0], bcd_u[3]};
            bcd_u = {bcd_u[2:0], val[i]};
        end
    end

    reg [17:0] refresh_cnt;
    always @(posedge clk) refresh_cnt <= refresh_cnt + 1;

    reg [3:0] active_digit;
    always @(*) begin
        case (refresh_cnt[17:16])
            2'b00: begin an=4'b1110; active_digit=bcd_u; end
            2'b01: begin an=4'b1101; active_digit=bcd_t; end
            2'b10: begin an=4'b1011; active_digit=bcd_h; end
            2'b11: begin an=4'b0111; active_digit=4'hF;  end
            default: begin an=4'b1111; active_digit=4'hF; end
        endcase
        case (active_digit)
            4'd0: seg=7'b1000000; 4'd1: seg=7'b1111001;
            4'd2: seg=7'b0100100; 4'd3: seg=7'b0110000;
            4'd4: seg=7'b0011001; 4'd5: seg=7'b0010010;
            4'd6: seg=7'b0000010; 4'd7: seg=7'b1111000;
            4'd8: seg=7'b0000000; 4'd9: seg=7'b0010000;
            default: seg=7'b1111111;
        endcase
    end
endmodule