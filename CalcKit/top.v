`timescale 1ns / 1ps

module top (
    input  wire sys_clk_in,       // 100 MHz
    input  wire sys_rst_n,        // Active Low
    
    input  wire PC_Uart_rxd,
    output wire PC_Uart_txd,
    
    // Board IO
    output wire [15:0] led_pin,
    input  wire [4:0]  btn_pin,   // btn_c is usually btn_pin[2]
    input  wire [7:0]  sw_pin,    // Mode & Op selection
    input  wire [7:0]  dip_pin,   // Extra switches
    
    output wire [7:0]  seg_cs_pin,
    output wire [7:0]  seg_data_0_pin,
    output wire [7:0]  seg_data_1_pin
);

    // ============================================================
    // 1. System Signals
    // ============================================================
    wire clk = sys_clk_in;
    wire rst_n = sys_rst_n; 
    
    wire btn_c = btn_pin[2]; 
    reg  btn_c_d, btn_c_re;
    always @(posedge clk) begin
        btn_c_d <= btn_c;
        btn_c_re <= btn_c && !btn_c_d; // Rising Edge
    end

    // ============================================================
    // 2. Central FSM Instance
    // ============================================================
    wire [3:0] current_state;
    
    // Handshake Signals
    reg input_dim_done;
    reg input_data_done;
    wire gen_random_done;
    wire bonus_done;
    reg display_id_conf;
    reg uart_tx_done;
    
    reg calc_mat_conf;
    reg check_valid;
    reg check_invalid;
    wire alu_done;
    reg result_display_done;
    wire error_timeout;

    Central_FSM u_fsm (
        .clk(clk),
        .rst_n(rst_n),
        .sw(sw_pin[7:5]),           
        .btn_c(btn_c_re),           
        
        .input_dim_done(input_dim_done),
        .input_data_done(input_data_done),
        .gen_random_done(gen_random_done),
        .bonus_done(bonus_done),
        .display_id_conf(display_id_conf),
        .uart_tx_done(uart_tx_done),
        
        .calc_mat_conf(calc_mat_conf),
        .check_valid(check_valid),
        .check_invalid(check_invalid),
        .alu_done(alu_done),
        .result_display_done(result_display_done),
        .error_timeout(error_timeout),
        
        .current_state(current_state)
    );

    // ============================================================
    // 3. UART RX & Parser
    // ============================================================
    wire [7:0] rx_data;
    wire rx_valid;
    uart_rx #(.CLK_FREQ(100_000_000), .BAUD_RATE(115200)) u_rx (
        .clk(clk), .rst_n(rst_n), .rx(PC_Uart_rxd), .data(rx_data), .valid(rx_valid)
    );

    wire [15:0] parser_num;
    wire parser_valid;
    cmd_parser u_parser (
        .clk(clk), .rst_n(rst_n), .rx_data(rx_data), .rx_valid(rx_valid),
        .number_out(parser_num), .number_valid(parser_valid)
    );

    // ============================================================
    // 4. UART TX
    // ============================================================
    reg [7:0] tx_data;
    reg tx_start;
    wire tx_busy;
    uart_tx #(.CLK_FREQ(100_000_000), .BAUD_RATE(115200)) u_tx (
        .clk(clk), .rst_n(rst_n), .data(tx_data), .start(tx_start), .tx(PC_Uart_txd), .busy(tx_busy)
    );

    // ============================================================
    // 5. Matrix Memory
    // ============================================================
    // User Port Mux Wires
    reg [2:0]  mux_user_row;
    reg [2:0]  mux_user_col;
    reg [15:0] mux_user_data;
    reg        mux_user_we;
    reg [2:0]  mux_user_dim_m;
    reg [2:0]  mux_user_dim_n;
    reg        mux_user_dim_we;
    
    // Read Port Wires (Display)
    reg [2:0]  mux_rd_m, mux_rd_n;
    reg [1:0]  mux_rd_id;
    reg [2:0]  mux_rd_row, mux_rd_col;
    wire [15:0] mux_user_rd_data;
    wire [1:0]  mux_user_rd_count;

    // ALU Port Wires (Placeholder connection for now)
    wire [15:0] alu_a_data, alu_b_data;
    
    // For now, map ALU ports to some default or zero to pass compilation
    // Since we focus on Input/Storage, ALU might be broken in this turn.
    
    matrix_mem u_mem (
        .clk(clk), .rst_n(rst_n),
        
        // Port 1: User Write
        .user_dim_m(mux_user_dim_m),
        .user_dim_n(mux_user_dim_n),
        .user_dim_we(mux_user_dim_we),
        .user_row(mux_user_row),
        .user_col(mux_user_col),
        .user_data(mux_user_data),
        .user_we(mux_user_we),
        
        // Port 1: User Read
        .user_rd_m(mux_rd_m),
        .user_rd_n(mux_rd_n),
        .user_rd_id(mux_rd_id),
        .user_rd_row(mux_rd_row),
        .user_rd_col(mux_rd_col),
        .user_rd_data(mux_user_rd_data),
        .user_rd_count(mux_user_rd_count),
        
        // Port 2: ALU A (Dummy/Partial)
        .alu_a_m(3'd0), .alu_a_n(3'd0), .alu_a_id(2'd0), .alu_a_row(3'd0), .alu_a_col(3'd0),
        .alu_a_data(alu_a_data),
        
        // Port 2: ALU B (Dummy/Partial)
        .alu_b_m(3'd0), .alu_b_n(3'd0), .alu_b_id(2'd0), .alu_b_row(3'd0), .alu_b_col(3'd0),
        .alu_b_data(alu_b_data),
        
        // Port 2: ALU Result (Dummy/Partial)
        .alu_res_m(3'd0), .alu_res_n(3'd0), .alu_res_dim_we(1'b0),
        .alu_res_row(3'd0), .alu_res_col(3'd0), .alu_res_data(16'd0), .alu_res_we(1'b0)
    );

    // ============================================================
    // 6. Sub-Modules
    // ============================================================
    
    // --- Matrix Gen (Stubbed for now, need update) ---
    reg gen_start;
    wire gen_done = 0; // Disable Gen for now
    wire gen_we = 0;
    wire [15:0] gen_data = 0;
    wire [2:0] gen_row = 0, gen_col = 0;
    wire [1:0] gen_slot = 0;

    // --- Matrix ALU (Stubbed) ---
    reg alu_start;
    reg [2:0] alu_opcode;
    reg [15:0] alu_scalar;
    wire alu_error = 0;
    assign alu_done = 1; // Always done to prevent hang

    // --- Bonus Conv (Stubbed) ---
    reg conv_start;
    wire [15:0] conv_res_data;
    wire conv_res_valid = 0;
    assign bonus_done = 1;
    wire [31:0] bonus_cycles = 0;

    // --- Timer Unit ---
    reg timer_start;
    wire [3:0] time_left;
    reg [3:0] config_timer_val;

    Timer_Unit u_timer (
        .clk(clk), .rst_n(rst_n), .start_timer(timer_start),
        .config_time(config_timer_val),
        .time_left(time_left), .timer_done(error_timeout)
    );
    
    // --- Input Error Timer ---
    reg [25:0] error_led_timer;
    wire input_error_active = (error_led_timer != 0);

    // --- LED Driver ---
    wire [1:0] status_led;
    assign led_pin[1:0] = status_led;
    assign led_pin[15:2] = 0;
    
    // Explicit Error State Handling
    wire err_flag = alu_error || input_error_active;
    
    LED_Driver u_led (
        .clk(clk), .rst_n(rst_n),
        .err_flag(err_flag), 
        .calc_busy(!alu_done && current_state == 10), 
        .conv_busy(!bonus_done && current_state == 4),
        .current_state(current_state),
        .led(status_led)
    );
    
    // --- Seg Driver ---
    reg [7:0] in_count;
    
    // Pass Error State to Seg Driver
    // Use a temp wire to inject Error State if input_error_active is high
    wire [3:0] seg_state = (input_error_active) ? 4'd12 : current_state;
    
    Seg_Driver u_seg (
        .clk(clk), .rst_n(rst_n),
        .current_state(seg_state), 
        .time_left(time_left), .sw_mode(sw_pin[7:5]),
        .in_count(in_count), 
        .alu_opcode(alu_opcode), 
        .bonus_cycles(bonus_cycles), 
        .seg_cs(seg_cs_pin),
        .seg_data_0(seg_data_0_pin),
        .seg_data_1(seg_data_1_pin)
    );

    // ============================================================
    // 7. Logic Implementation
    // ============================================================

    // --- 7.1 Input Logic ---
    reg [2:0] in_m, in_n;
    reg [7:0] in_total;
    
    // Clear Memory State logic
    reg clearing_mem;
    reg [4:0] clear_cnt;
    
    // --- 7.3 Print Logic ---
    reg [2:0] print_row, print_col;
    reg [2:0] print_m, print_n; 
    reg [3:0] print_state; 
    
    // ASCII Conversion
    reg [15:0] pr_val_buf;
    reg        pr_is_neg;
    reg [3:0]  pr_digits[0:4];
    reg [2:0]  pr_digit_cnt;
    reg [2:0]  pr_send_idx;
    reg [2:0]  pr_calc_cnt;
    reg signed [15:0] pr_signed_val;
    
    localparam P_IDLE=0, P_START=1, P_READ=2, P_LATCH=3, P_CALC=4, P_SIGN=5, P_DIGIT=6, P_SPACE=7, P_ROW_END=8, P_MATRIX_END=9, P_DONE=10;

    reg [3:0] reset_cnt;
    reg [19:0] reset_timer;
    
    // Check Logic (Stubbed)
    reg check_pass;
    always @(*) check_pass = 1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            input_dim_done <= 0;
            input_data_done <= 0;
            display_id_conf <= 0;
            uart_tx_done <= 0;
            calc_mat_conf <= 0;
            check_valid <= 0;
            check_invalid <= 0;
            result_display_done <= 0;
            
            gen_start <= 0;
            alu_start <= 0;
            conv_start <= 0;
            timer_start <= 0;
            
            in_m <= 0; in_n <= 0; in_count <= 0; in_total <= 0;
            
            print_state <= P_IDLE;
            tx_start <= 0;
            error_led_timer <= 0;
            
            reset_cnt <= 0;
            reset_timer <= 0;
            
            config_timer_val <= 4'd10; 
            
            clearing_mem <= 0;
            clear_cnt <= 0;
            
        end else begin
            input_dim_done <= 0;
            input_data_done <= 0;
            gen_start <= 0;
            display_id_conf <= 0;
            uart_tx_done <= 0;
            calc_mat_conf <= 0;
            check_valid <= 0;
            check_invalid <= 0;
            alu_start <= 0;
            result_display_done <= 0;
            conv_start <= 0;
            tx_start <= 0; 
            timer_start <= 0; 
            
            if (error_led_timer > 0) error_led_timer <= error_led_timer - 1;

            // Reset Logic
            if (btn_c_re) begin
                 reset_cnt <= reset_cnt + 1;
                 reset_timer <= 0;
            end else if (reset_timer < 20'd100_0000) begin 
                 reset_timer <= reset_timer + 1;
            end else begin
                 reset_cnt <= 0;
            end
            
            if (reset_cnt >= 8) begin
                 // Trigger Soft Reset
                 in_m <= 0; in_n <= 0; in_count <= 0;
                 print_state <= P_IDLE;
                 reset_cnt <= 0;
            end
            
            if (current_state == 0) begin
                in_m <= 0;
                in_n <= 0;
            end

            case (current_state)
                // -----------------------
                // STATE: INPUT DIM
                // -----------------------
                1: begin // INPUT_DIM
                    if (input_error_active) begin
                        // Wait for Error Timer
                    end else begin
                        if (in_count != 0) in_count <= 0; 
                        
                        if (parser_valid) begin
                            if (parser_num >= 1 && parser_num <= 5) begin
                                if (in_m == 0) begin
                                    in_m <= parser_num[2:0]; 
                                end else begin
                                    if (parser_num[2:0] != 0) begin
                                        in_n <= parser_num[2:0]; 
                                        in_total <= in_m * parser_num[2:0];
                                        input_dim_done <= 1; // Transition
                                        in_count <= 0;
                                        
                                        // Start Clearing Mem Logic
                                        clearing_mem <= 1;
                                        clear_cnt <= 0;
                                    end else begin
                                        check_invalid <= 1; 
                                        error_led_timer <= 26'd100_000_000;
                                        // Reset inputs
                                        in_m <= 0;
                                    end
                                end
                            end else begin
                                check_invalid <= 1; 
                                error_led_timer <= 26'd100_000_000; 
                                // Reset inputs
                                in_m <= 0;
                            end
                        end
                    end
                end
                
                // -----------------------
                // STATE: INPUT DATA
                // -----------------------
                2: begin // INPUT_DATA
                    if (input_error_active) begin
                         // Wait for timer
                         // When timer expires, FSM will still be in INPUT_DATA unless we force transition?
                         // User says: "After 1s... automatically return to manual input state (G4 blink)"
                         // If we are in INPUT_DATA, we should return to INPUT_DIM or IDLE?
                         // "Return to un-input state" usually means start over (INPUT_DIM).
                         // We need to trigger a reset or transition.
                         if (error_led_timer == 1) begin
                             // Timer about to expire.
                             // Force FSM to IDLE or INPUT_DIM?
                             // FSM: INPUT_DATA -> IDLE if input_data_done.
                             // Let's use input_data_done to go to IDLE, then user re-enters?
                             // Or use a special flag.
                             // Actually, let's just go to IDLE.
                             input_data_done <= 1;
                         end
                    end else if (clearing_mem) begin
                        // Logic handled in Mux Section, just increment here
                        if (clear_cnt == 25) clearing_mem <= 0;
                        else clear_cnt <= clear_cnt + 1;
                    end else begin
                        if (parser_valid) begin
                            if (parser_num <= 9) begin
                                // Valid
                                if (in_count < in_total) begin
                                    in_count <= in_count + 1;
                                    if (in_count + 1 == in_total) begin
                                        input_data_done <= 1;
                                    end
                                end else begin
                                    // Truncate (Ignore)
                                end
                            end else begin
                                // Invalid (>9)
                                // Error LED 1s
                                error_led_timer <= 26'd100_000_000;
                            end
                        end
                        
                        // Manual Finish (if padding needed and user stops)
                        if (btn_c_re) begin
                            input_data_done <= 1;
                        end
                    end
                end
                
                // -----------------------
                // STATE: GEN RANDOM
                // -----------------------
                3: begin 
                    if (!gen_done && !gen_start) gen_start <= 1;
                    else gen_start <= 0; 
                end
                
                // -----------------------
                // STATE: BONUS RUN
                // -----------------------
                4: begin 
                    if (!bonus_done && !conv_start) conv_start <= 1;
                    else conv_start <= 0; 
                end
                
                // -----------------------
                // STATE: DISPLAY WAIT
                // -----------------------
                5: begin 
                    if (btn_c_re) begin
                        // display_id_conf <= 1; // Disabled for now
                        print_state <= P_IDLE;
                    end
                end
                
                // -----------------------
                // STATE: DISPLAY PRINT
                // -----------------------
                6: begin 
                    if (print_state == P_DONE) begin
                        uart_tx_done <= 1;
                        print_state <= P_IDLE;
                    end
                end
                
                // -----------------------
                // STATE: CONFIG
                // -----------------------
                13: begin 
                    if (parser_valid) begin
                        if (parser_num >= 5 && parser_num <= 15) begin
                            config_timer_val <= parser_num[3:0];
                        end
                    end
                end
                
            endcase
            
            // --- Print State Machine (Partial) ---
            if ((current_state == 6 || current_state == 11) && !uart_tx_done && !result_display_done) begin
                // ... (Keep existing print logic if needed, or stub)
                // For this task, we can ignore print details as long as it compiles.
                // But let's keep the logic structure to avoid syntax errors.
                case (print_state)
                    P_IDLE: begin print_row <= 0; print_col <= 0; print_state <= P_START; end
                    P_START: begin if (!tx_busy) begin tx_data <= 8'h5B; tx_start <= 1; print_state <= P_READ; end end
                    P_READ: begin print_state <= P_LATCH; end
                    P_LATCH: begin pr_val_buf <= mux_user_rd_data; print_state <= P_MATRIX_END; end // Short circuit for now
                    P_MATRIX_END: begin if (!tx_busy) begin tx_data <= 8'h0A; tx_start <= 1; print_state <= P_DONE; end end
                endcase
            end
        end
    end
    
    // ============================================================
    // 8. Mux Logic for Memory Port 1
    // ============================================================
    always @(*) begin
        // Default
        mux_user_row = 0;
        mux_user_col = 0;
        mux_user_data = 0;
        mux_user_we = 0;
        mux_user_dim_m = 0;
        mux_user_dim_n = 0;
        mux_user_dim_we = 0;
        
        mux_rd_m = 0; mux_rd_n = 0; mux_rd_id = 0;
        mux_rd_row = 0; mux_rd_col = 0;
        
        case (current_state)
            1: begin // INPUT_DIM
                 mux_user_dim_m = in_m;
                 mux_user_dim_n = parser_num[2:0]; 
                 
                 // Write dimensions when we receive the second number (N)
                 if (parser_valid && in_m != 0) mux_user_dim_we = 1;
            end
            2: begin // INPUT_DATA
                 if (clearing_mem) begin
                     // Writing 0s to initialize
                     mux_user_we = 1;
                     mux_user_data = 0;
                     mux_user_row = clear_cnt / 5; // Assuming 5x5 max, row=cnt/5
                     mux_user_col = clear_cnt % 5;
                     
                     // NOTE: We need to know which DIM we are clearing?
                     // matrix_mem uses "user_dim_m/n" to determine spec?
                     // NO, matrix_mem remembers "active_phys_slot".
                     // So we just provide row/col/data/we.
                 end else begin
                     // User Input
                     mux_user_row = in_count / in_n; 
                     mux_user_col = in_count % in_n;
                     mux_user_data = parser_num;
                     // Only write if valid and within range
                     if (parser_valid && parser_num <= 9 && in_count < in_total) mux_user_we = 1;
                 end
            end
            6, 11: begin // PRINT
                 mux_rd_m = print_m; 
                 mux_rd_n = print_n;
                 mux_rd_id = 1; // Default to ID 1
                 mux_rd_row = print_row;
                 mux_rd_col = print_col;
            end
        endcase
    end

endmodule
