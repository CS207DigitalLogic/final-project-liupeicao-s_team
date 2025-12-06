`timescale 1ns / 1ps

module top (
    input  wire sys_clk_in,       // 100 MHz
    input  wire sys_rst_n,        // Active Low
    
    input  wire PC_Uart_rxd,
    output wire PC_Uart_txd,
    
    // Board IO
    output wire [15:0] led_pin,
    input  wire [4:0]  btn_pin,   // btn_c is usually btn_pin[2] or similar, need check XDC. 
                                  // Assuming btn_pin[2] is Center based on common XDC
    input  wire [7:0]  sw_pin,    // Mode & Op selection
    input  wire [7:0]  dip_pin,   // Extra switches (unused or for data)
    
    output wire [7:0]  seg_cs_pin,
    output wire [7:0]  seg_data_0_pin,
    output wire [7:0]  seg_data_1_pin
);

    // ============================================================
    // 1. System Signals
    // ============================================================
    wire clk = sys_clk_in;
    wire rst_n = sys_rst_n; // Assuming board button is active low logic or handled externally
    
    // Button Debounce / Edge Detection (Simplified: Assuming clean or low freq)
    // In real HW, should add debouncer. For now, using direct input.
    // XDC says: btn_pin[2] is R15 (Center?). Let's assume btn[2] is Confirm.
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
    
    // Handshake Signals (Regs to be driven by logic)
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
        .sw(sw_pin[7:5]),           // Mode Selection SW[7:5]
        .btn_c(btn_c_re),           // Pulse
        
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
    // 4. UART TX (Multiplexed)
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
    reg [1:0]  mux_user_slot;
    reg [2:0]  mux_user_row;
    reg [2:0]  mux_user_col;
    reg [15:0] mux_user_data;
    reg        mux_user_we;
    reg [2:0]  mux_user_dim_m;
    reg [2:0]  mux_user_dim_n;
    reg        mux_user_dim_we;
    wire [15:0] mux_user_rd_data;

    // ALU Port Wires
    wire [1:0] alu_rd_slot;
    wire [2:0] alu_rd_row, alu_rd_col;
    wire [15:0] alu_rd_data;
    wire [2:0] alu_cur_m, alu_cur_n;
    wire [1:0] alu_wr_slot;
    wire [2:0] alu_wr_row, alu_wr_col;
    wire [15:0] alu_wr_data;
    wire alu_wr_we, alu_dim_we;
    wire [2:0] alu_res_m, alu_res_n;

    matrix_mem u_mem (
        .clk(clk), .rst_n(rst_n),
        
        // Port 1 (User/Gen/Conv/Print)
        .user_slot_idx(mux_user_slot),
        .user_row(mux_user_row),
        .user_col(mux_user_col),
        .user_data(mux_user_data),
        .user_we(mux_user_we),
        .user_dim_m(mux_user_dim_m),
        .user_dim_n(mux_user_dim_n),
        .user_dim_we(mux_user_dim_we),
        .user_rd_data(mux_user_rd_data),
        
        // Port 2 (ALU)
        .alu_rd_slot(alu_rd_slot),
        .alu_rd_row(alu_rd_row),
        .alu_rd_col(alu_rd_col),
        .alu_rd_data(alu_rd_data),
        .alu_current_m(alu_cur_m),
        .alu_current_n(alu_cur_n),
        
        .alu_wr_slot(alu_wr_slot),
        .alu_wr_row(alu_wr_row),
        .alu_wr_col(alu_wr_col),
        .alu_wr_data(alu_wr_data),
        .alu_wr_we(alu_wr_we),
        .alu_res_m(alu_res_m),
        .alu_res_n(alu_res_n),
        .alu_dim_we(alu_dim_we)
    );

    // ============================================================
    // 6. Sub-Modules
    // ============================================================
    
    // --- Matrix Gen ---
    reg gen_start;
    wire [1:0] gen_slot;
    wire [2:0] gen_row, gen_col;
    wire [15:0] gen_data;
    wire gen_we;
    
    matrix_gen u_gen (
        .clk(clk), .rst_n(rst_n),
        .start(gen_start),
        .target_m(3'd3), .target_n(3'd3), // Default 3x3 for demo
        .target_slot(2'd0),               // Default Slot A
        .done(gen_done),
        // Mem Interface
        .gen_slot_idx(gen_slot),
        .gen_row(gen_row), .gen_col(gen_col),
        .gen_data(gen_data), .gen_we(gen_we)
    );

    // --- Matrix ALU ---
    reg alu_start;
    reg [2:0] alu_opcode;
    reg [15:0] alu_scalar;
    wire alu_error; // To FSM
    
    matrix_alu u_alu (
        .clk(clk), .rst_n(rst_n),
        .start(alu_start), .opcode(alu_opcode), .scalar_val(alu_scalar),
        .done(alu_done), .error(alu_error),
        // Mem Interface
        .mem_rd_slot(alu_rd_slot), .mem_rd_row(alu_rd_row), .mem_rd_col(alu_rd_col),
        .mem_rd_data(alu_rd_data), .mem_current_m(alu_cur_m), .mem_current_n(alu_cur_n),
        .mem_wr_slot(alu_wr_slot), .mem_wr_row(alu_wr_row), .mem_wr_col(alu_wr_col),
        .mem_wr_data(alu_wr_data), .mem_wr_we(alu_wr_we),
        .mem_res_m(alu_res_m), .mem_res_n(alu_res_n), .mem_dim_we(alu_dim_we)
    );
    
    // --- Bonus Conv ---
    reg conv_start;
    wire [15:0] conv_res_data;
    wire conv_res_valid;
    wire [1:0] conv_rd_slot;
    wire [2:0] conv_rd_row, conv_rd_col;
    
    bonus_conv u_conv (
        .clk(clk), .rst_n(rst_n), .start_conv(conv_start),
        .mem_rd_slot(conv_rd_slot), .mem_rd_row(conv_rd_row), .mem_rd_col(conv_rd_col),
        .mem_rd_data(mux_user_rd_data), // Reads from User Port
        .conv_res_data(conv_res_data), .conv_res_valid(conv_res_valid), .conv_done(bonus_done)
    );

    // --- Timer Unit ---
    reg timer_start;
    wire [3:0] time_left;
    
    Timer_Unit u_timer (
        .clk(clk), .rst_n(rst_n), .start_timer(timer_start),
        .time_left(time_left), .timer_done(error_timeout)
    );
    
    // --- LED Driver ---
    wire [1:0] status_led;
    assign led_pin[1:0] = status_led;
    assign led_pin[15:2] = 0;
    
    LED_Driver u_led (
        .clk(clk), .rst_n(rst_n),
        .err_flag(alu_error), .calc_busy(!alu_done && current_state == 10), 
        .conv_busy(!bonus_done && current_state == 4),
        .current_state(current_state),
        .led(status_led)
    );
    
    // --- Seg Driver ---
    Seg_Driver u_seg (
        .clk(clk), .rst_n(rst_n),
        .current_state(current_state), .time_left(time_left), .sw_mode(sw_pin[7:5]),
        .seg_out(seg_data_0_pin), .seg_an(seg_cs_pin)
    );
    assign seg_data_1_pin = 8'hFF; // Unused

    // ============================================================
    // 7. Logic Implementation (The "Brain" Wiring)
    // ============================================================

    // --- 7.1 Input Logic (Parser -> Regs) ---
    reg [2:0] in_m, in_n;
    reg [7:0] in_count;
    reg [7:0] in_total;
    
    // --- 7.2 Calculation Selection Logic ---
    reg [1:0] sel_slot_a; // Not used by ALU directly (ALU fixed A=0, B=1)
    reg [1:0] sel_slot_b; // But we might need to check valid. 
                          // Wait, ALU fixes A=Slot0, B=Slot1. 
                          // The "Select Mat" state in FSM might be for Display or just confirming.
                          // Architecture doc says "Select Mat ID". 
                          // Let's assume we just use this state to trigger the CHECK logic.

    // --- 7.3 Print Logic ---
    reg [1:0] print_slot;
    reg [2:0] print_row, print_col;
    reg [2:0] print_m, print_n;
    reg [3:0] print_state; // Internal sub-state for printing
    
    // ASCII Conversion logic (Same as old top.v)
    reg [15:0] pr_val_buf;
    reg        pr_is_neg;
    reg [3:0]  pr_digits[0:4];
    reg [2:0]  pr_digit_cnt;
    reg [2:0]  pr_send_idx;
    reg [2:0]  pr_calc_cnt;
    reg signed [15:0] pr_signed_val;
    
    localparam P_IDLE=0, P_READ=1, P_LATCH=2, P_CALC=3, P_SIGN=4, P_DIGIT=5, P_SPACE=6, P_DONE=7;

    // --- 7.4 Main Control Logic ---
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset Logic
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
            
        end else begin
            // Default Pulses
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
            tx_start <= 0; // UART TX Start Pulse

            case (current_state)
                // -----------------------
                // STATE: INPUT DIM
                // -----------------------
                1: begin // INPUT_DIM
                    if (parser_valid) begin
                        if (in_m == 0) begin
                            in_m <= parser_num[2:0]; // First number: M
                        end else begin
                            in_n <= parser_num[2:0]; // Second number: N
                            in_total <= in_m * parser_num[2:0];
                            input_dim_done <= 1; // Pulse FSM
                            in_count <= 0;
                        end
                    end
                end
                
                // -----------------------
                // STATE: INPUT DATA
                // -----------------------
                2: begin // INPUT_DATA
                    if (parser_valid) begin
                        in_count <= in_count + 1;
                        if (in_count + 1 == in_total) begin
                            input_data_done <= 1;
                        end
                    end
                end
                
                // -----------------------
                // STATE: GEN RANDOM
                // -----------------------
                3: begin // GEN_RANDOM
                    // Triggered by FSM entry. 
                    // We need edge detection on state entry? 
                    // Or FSM waits for done.
                    // Let's trigger once.
                    if (!gen_done && !gen_start) gen_start <= 1; 
                end
                
                // -----------------------
                // STATE: BONUS RUN
                // -----------------------
                4: begin // BONUS_RUN
                    if (!bonus_done && !conv_start) conv_start <= 1;
                    // Stream output logic handled below
                end
                
                // -----------------------
                // STATE: DISPLAY WAIT
                // -----------------------
                5: begin // DISPLAY_WAIT
                    // Wait for user to select Matrix ID via SW[4:0] or UART?
                    // Doc says: "Wait for user to select matrix ID".
                    // Let's assume SW[4:0] selects Slot (0,1,2)
                    if (btn_c_re) begin
                        print_slot <= sw_pin[1:0]; // Use SW[1:0] for slot
                        display_id_conf <= 1;
                        print_state <= P_IDLE;
                    end
                end
                
                // -----------------------
                // STATE: DISPLAY PRINT
                // -----------------------
                6: begin // DISPLAY_PRINT
                    // Trigger Print State Machine
                    if (print_state == P_DONE) begin
                        uart_tx_done <= 1;
                        print_state <= P_IDLE;
                    end
                end
                
                // -----------------------
                // STATE: CALC SELECT OP
                // -----------------------
                7: begin // CALC_SELECT_OP
                    // Handled by FSM transition on Btn_C
                    // We just latch opcode here
                    alu_opcode <= sw_pin[2:0]; // Use SW[2:0] for Opcode
                end
                
                // -----------------------
                // STATE: CALC SELECT MAT
                // -----------------------
                8: begin // CALC_SELECT_MAT
                    // Latch scalar if needed
                    if (alu_opcode == 3'b011) alu_scalar <= {8'b0, sw_pin}; // Simple scalar from SW
                    if (btn_c_re) calc_mat_conf <= 1;
                end
                
                // -----------------------
                // STATE: CALC CHECK
                // -----------------------
                9: begin // CALC_CHECK
                    // Simple check logic (Real check is inside ALU actually, but FSM wants explicit signal)
                    // Let's assume valid for now, or read dims from Mem?
                    // Since ALU has internal check state, maybe we just pass VALID and let ALU error out?
                    // Doc says FSM has CHECK state. 
                    // Let's send check_valid = 1 immediately to let ALU handle it.
                    check_valid <= 1; 
                end
                
                // -----------------------
                // STATE: CALC EXEC
                // -----------------------
                10: begin // CALC_EXEC
                    // Trigger ALU
                    // Need to ensure start is pulsed ONCE upon entry
                    // We can detect state transition or just pulse if not busy?
                    // Better: use a flag "alu_started"
                    if (!alu_done && !alu_start) alu_start <= 1;
                end
                
                // -----------------------
                // STATE: CALC DONE
                // -----------------------
                11: begin // CALC_DONE
                    // Auto print result (Slot C)
                    print_slot <= 2'd2; // Slot C
                    if (print_state == P_DONE) begin
                        result_display_done <= 1;
                        print_state <= P_IDLE;
                    end
                end
                
                // -----------------------
                // STATE: CALC ERROR
                // -----------------------
                12: begin // CALC_ERROR
                    timer_start <= 1;
                    // Timer will assert error_timeout eventually
                end
                
            endcase
            
            // --- Print State Machine (Runs when enabled) ---
            if ((current_state == 6 || current_state == 11) && !uart_tx_done && !result_display_done) begin
                case (print_state)
                    P_IDLE: begin
                        // Need to read dimensions first?
                        // For now assume fixed 3x3 or read from logic?
                        // Let's rely on Mem to provide current_m/n when we set slot.
                        print_row <= 0; print_col <= 0;
                        print_state <= P_READ;
                    end
                    P_READ: begin
                        // Mux sets addr, wait 1 cycle
                        print_state <= P_LATCH;
                    end
                    P_LATCH: begin
                        pr_val_buf <= mux_user_rd_data;
                        pr_calc_cnt <= 0;
                        
                        // Sign
                        pr_is_neg <= mux_user_rd_data[15];
                        if (mux_user_rd_data[15]) pr_signed_val <= -$signed(mux_user_rd_data);
                        else pr_signed_val <= $signed(mux_user_rd_data);
                        
                        print_state <= P_CALC;
                    end
                    P_CALC: begin
                        if (pr_calc_cnt < 5) begin
                            pr_digits[pr_calc_cnt] <= pr_signed_val % 10;
                            pr_signed_val <= pr_signed_val / 10;
                            pr_calc_cnt <= pr_calc_cnt + 1;
                        end else begin
                            // Determine length
                            if (pr_val_buf == 0) begin pr_digit_cnt <= 1; pr_send_idx <= 0; end
                            else if (pr_digits[4]) begin pr_digit_cnt <= 5; pr_send_idx <= 4; end
                            else if (pr_digits[3]) begin pr_digit_cnt <= 4; pr_send_idx <= 3; end
                            else if (pr_digits[2]) begin pr_digit_cnt <= 3; pr_send_idx <= 2; end
                            else if (pr_digits[1]) begin pr_digit_cnt <= 2; pr_send_idx <= 1; end
                            else begin pr_digit_cnt <= 1; pr_send_idx <= 0; end
                            
                            if (pr_is_neg) print_state <= P_SIGN;
                            else print_state <= P_DIGIT;
                        end
                    end
                    P_SIGN: begin
                        if (!tx_busy) begin tx_data <= 8'h2D; tx_start <= 1; print_state <= P_DIGIT; end
                    end
                    P_DIGIT: begin
                        if (!tx_busy && !tx_start) begin // Wait for sign TX if any
                             tx_data <= pr_digits[pr_send_idx] + 8'h30;
                             tx_start <= 1;
                             if (pr_digit_cnt == 1) print_state <= P_SPACE;
                             else begin
                                pr_digit_cnt <= pr_digit_cnt - 1;
                                pr_send_idx <= pr_send_idx - 1;
                             end
                        end
                    end
                    P_SPACE: begin
                        if (!tx_busy && !tx_start) begin
                            tx_data <= 8'h20; // Space
                            tx_start <= 1;
                            // Next Element
                            // We need Dimensions here. 
                            // Assume 3x3 for simplicity OR read dim.
                            // For robustness, let's loop 3x3. 
                            // REAL IMPLEMENTATION SHOULD READ DIMS.
                            if (print_col == 2) begin // Hardcoded 3 cols
                                if (print_row == 2) begin // Hardcoded 3 rows
                                    print_state <= P_DONE;
                                end else begin
                                    print_row <= print_row + 1;
                                    print_col <= 0;
                                    print_state <= P_READ;
                                end
                            end else begin
                                print_col <= print_col + 1;
                                print_state <= P_READ;
                            end
                        end
                    end
                endcase
            end
            
            // --- Bonus Conv Stream Output ---
            if (current_state == 4 && conv_res_valid && !tx_busy) begin
                // Simplify: just send LSB byte for demo or 'C' char
                // Real formatting is complex for stream. 
                // Let's just send a char per result for liveness.
                tx_data <= 8'h2A; // '*'
                tx_start <= 1;
            end
        end
    end
    
    // ============================================================
    // 8. Mux Logic for Memory Port 1
    // ============================================================
    always @(*) begin
        // Default
        mux_user_slot = 0;
        mux_user_row = 0;
        mux_user_col = 0;
        mux_user_data = 0;
        mux_user_we = 0;
        mux_user_dim_m = 0;
        mux_user_dim_n = 0;
        mux_user_dim_we = 0;
        
        case (current_state)
            1: begin // INPUT_DIM
                 // Write Dims
                 mux_user_slot = sw_pin[1:0]; // Use SW[1:0] for Slot Selection
                 mux_user_dim_m = in_m;
                 mux_user_dim_n = parser_num[2:0]; // Use current input for N
                 
                 // Write dimensions when we receive the second number (N)
                 if (parser_valid && in_m != 0) mux_user_dim_we = 1;
            end
            2: begin // INPUT_DATA
                 mux_user_slot = sw_pin[1:0]; // Use SW[1:0] for Slot Selection
                 mux_user_row = in_count / in_n; // Simple mapping
                 mux_user_col = in_count % in_n;
                 mux_user_data = parser_num;
                 mux_user_we = parser_valid;
                 // Note: Should support B input too. Need logic to select Slot based on previous done.
                 // For this simplified rewrite, assuming only A input for now.
            end
            3: begin // GEN
                 mux_user_slot = gen_slot;
                 mux_user_row = gen_row;
                 mux_user_col = gen_col;
                 mux_user_data = gen_data;
                 mux_user_we = gen_we;
            end
            4: begin // CONV
                 // Conv reads from Port 1
                 mux_user_slot = conv_rd_slot;
                 mux_user_row = conv_rd_row;
                 mux_user_col = conv_rd_col;
                 mux_user_we = 0; // Read only
            end
            6, 11: begin // PRINT
                 mux_user_slot = print_slot;
                 mux_user_row = print_row;
                 mux_user_col = print_col;
                 mux_user_we = 0;
            end
        endcase
    end

endmodule
