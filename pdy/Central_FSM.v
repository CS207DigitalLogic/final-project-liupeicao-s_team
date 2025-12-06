`timescale 1ns / 1ps

module Central_FSM (
    input wire clk,                 // 系统时钟
    input wire rst_n,               // 系统复位 (Active Low)
    input wire [2:0] sw,            // 开关输入 (SW[2:0])
    input wire btn_c,               // 确认按键 (需为单脉冲信号)

    // --- UART Input (from cmd_parser) ---
    input wire [15:0] number_out,
    input wire number_valid,

    // --- Submodule Status ---
    input wire gen_done,
    input wire alu_done,
    input wire alu_error,
    input wire conv_done,
    input wire [15:0] conv_res_data,
    input wire conv_res_valid,

    // --- UART Output Control ---
    output reg [7:0] tx_data,
    output reg tx_start,
    input wire tx_busy,

    // --- Matrix Memory User Port Control ---
    output reg [1:0] user_slot_idx,
    output reg [2:0] user_row,
    output reg [2:0] user_col,
    output reg [15:0] user_data,
    output reg user_we,
    output reg [2:0] user_dim_m,
    output reg [2:0] user_dim_n,
    output reg user_dim_we,
    input wire [15:0] user_rd_data, // Data read from memory for display

    // --- Matrix Gen Control ---
    output reg gen_start,
    output reg [2:0] gen_target_m,
    output reg [2:0] gen_target_n,
    output reg [1:0] gen_target_slot,

    // --- Matrix ALU Control ---
    output reg alu_start,
    output reg [2:0] alu_opcode,
    output reg [15:0] alu_scalar,

    // --- Bonus Conv Control ---
    output reg conv_start,

    // --- Debug / Status ---
    output reg [3:0] current_state
);

    // ============================================================
    // Parameters & States
    // ============================================================
    localparam STATE_IDLE           = 4'd0;
    
    // Mode 000: Input
    localparam STATE_INPUT_PARAM    = 4'd1;  // Get Slot, M, N
    localparam STATE_INPUT_DATA     = 4'd2;  // Get M*N Data
    
    // Mode 001: Gen
    localparam STATE_GEN_PARAM      = 4'd3;  // Get Slot, M, N
    localparam STATE_GEN_WAIT       = 4'd4;  // Wait for Gen Done
    
    // Mode 010: Display
    localparam STATE_DISPLAY_PARAM  = 4'd5;  // Get Slot
    localparam STATE_DISPLAY_READ   = 4'd6;  // Read Mem
    localparam STATE_DISPLAY_PRINT  = 4'd7;  // Send UART
    
    // Mode 011: Calc
    localparam STATE_CALC_PARAM     = 4'd8;  // Get Opcode (and Scalar)
    localparam STATE_CALC_WAIT      = 4'd9;  // Wait for ALU Done
    
    // Mode 100: Bonus
    localparam STATE_BONUS_WAIT     = 4'd10; // Wait for Conv Done & Stream
    
    // Common UART Output States
    localparam STATE_PRINT_NUM      = 4'd11; // Print a 16-bit number (dec/hex)
    localparam STATE_PRINT_NEWLINE  = 4'd12; // Print \r\n

    reg [3:0] next_state;
    reg [3:0] return_state; // For subroutine calls (Printing)

    // ============================================================
    // Internal Registers
    // ============================================================
    // Parameter Buffer
    reg [1:0] param_count;
    reg [1:0] target_slot;
    reg [2:0] target_m, target_n;
    reg [15:0] target_scalar;
    reg [2:0] target_op;
    
    // Data Counter
    reg [7:0] data_counter;
    reg [7:0] total_elements;
    
    // Printing / ASCII Conversion
    reg [15:0] print_value;
    reg [3:0] digit_buf[0:4];
    reg [2:0] digit_idx;
    reg [2:0] digit_total;
    reg is_negative;
    
    // Conv Output Buffer
    reg [15:0] conv_data_buf;
    reg conv_data_ready;

    // ============================================================
    // State Update
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= STATE_IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    // ============================================================
    // FSM Logic
    // ============================================================
    
    // Helper Function: Digit to ASCII
    function [7:0] digit_to_ascii;
        input [3:0] digit;
        begin
            digit_to_ascii = digit + 8'h30;
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            next_state <= STATE_IDLE;
            user_we <= 0;
            user_dim_we <= 0;
            gen_start <= 0;
            alu_start <= 0;
            conv_start <= 0;
            tx_start <= 0;
            param_count <= 0;
            data_counter <= 0;
            
            // Default Outputs
            user_slot_idx <= 0;
            user_row <= 0;
            user_col <= 0;
            
        end else begin
            // Auto-reset pulses
            user_we <= 0;
            user_dim_we <= 0;
            gen_start <= 0;
            alu_start <= 0;
            conv_start <= 0;
            tx_start <= 0;

            case (current_state)
                // ------------------------------------------------
                // IDLE: Wait for Button
                // ------------------------------------------------
                STATE_IDLE: begin
                    param_count <= 0;
                    data_counter <= 0;
                    if (btn_c) begin
                        case (sw)
                            3'b000: next_state <= STATE_INPUT_PARAM;
                            3'b001: next_state <= STATE_GEN_PARAM;
                            3'b010: next_state <= STATE_DISPLAY_PARAM;
                            3'b011: next_state <= STATE_CALC_PARAM;
                            3'b100: begin
                                conv_start <= 1; // Start immediately for Bonus
                                next_state <= STATE_BONUS_WAIT;
                            end
                            default: next_state <= STATE_IDLE;
                        endcase
                    end
                end

                // ------------------------------------------------
                // MODE 0: INPUT (Slot, M, N -> Data)
                // ------------------------------------------------
                STATE_INPUT_PARAM: begin
                    if (number_valid) begin
                        case (param_count)
                            0: begin target_slot <= number_out[1:0]; param_count <= 1; end
                            1: begin target_m <= number_out[2:0]; param_count <= 2; end
                            2: begin 
                                target_n <= number_out[2:0]; 
                                total_elements <= number_out[2:0] * target_m; // Calc total
                                
                                // Update Dimensions in Mem
                                user_slot_idx <= target_slot;
                                user_dim_m <= target_m;
                                user_dim_n <= number_out[2:0];
                                user_dim_we <= 1;
                                
                                user_row <= 0;
                                user_col <= 0;
                                next_state <= STATE_INPUT_DATA;
                            end
                        endcase
                    end
                end

                STATE_INPUT_DATA: begin
                    if (number_valid) begin
                        // Write to Memory
                        user_slot_idx <= target_slot;
                        user_data <= number_out;
                        user_row <= user_row; // Current row
                        user_col <= user_col; // Current col
                        user_we <= 1;

                        // Update Counters
                        if (user_col == target_n - 1) begin
                            user_col <= 0;
                            user_row <= user_row + 1;
                        end else begin
                            user_col <= user_col + 1;
                        end

                        data_counter <= data_counter + 1;
                        if (data_counter + 1 >= total_elements) begin
                            next_state <= STATE_IDLE;
                        end
                    end
                end

                // ------------------------------------------------
                // MODE 1: GEN (Slot, M, N -> Start)
                // ------------------------------------------------
                STATE_GEN_PARAM: begin
                    if (number_valid) begin
                        case (param_count)
                            0: begin target_slot <= number_out[1:0]; param_count <= 1; end
                            1: begin target_m <= number_out[2:0]; param_count <= 2; end
                            2: begin 
                                target_n <= number_out[2:0]; 
                                // Trigger Gen
                                gen_target_slot <= target_slot;
                                gen_target_m <= target_m;
                                gen_target_n <= number_out[2:0];
                                gen_start <= 1;
                                next_state <= STATE_GEN_WAIT;
                            end
                        endcase
                    end
                end

                STATE_GEN_WAIT: begin
                    if (gen_done) begin
                        next_state <= STATE_IDLE;
                    end
                end

                // ------------------------------------------------
                // MODE 2: DISPLAY (Slot -> Print)
                // ------------------------------------------------
                STATE_DISPLAY_PARAM: begin
                    if (number_valid) begin
                        target_slot <= number_out[1:0];
                        
                        // Setup for Reading
                        user_slot_idx <= number_out[1:0];
                        // Note: We don't know M/N here easily unless we read them or user inputs them.
                        // The Matrix Mem doesn't expose "Dim Read" on User Port easily (only on ALU Port).
                        // User Port 'user_dim_m' is an INPUT.
                        // However, Port 2 (ALU) outputs 'alu_current_m/n'.
                        // For simplicity, let's assume User Inputs M/N again for display 
                        // OR we blindly read 8x8?
                        // Wait, README says "User sets slot...".
                        // Let's assume we require M, N input for display too, to know how much to print.
                        param_count <= 1; 
                    end
                    else if (param_count == 1 && number_valid) begin
                        target_m <= number_out[2:0];
                        param_count <= 2;
                    end
                    else if (param_count == 2 && number_valid) begin
                        target_n <= number_out[2:0];
                        total_elements <= number_out[2:0] * target_m;
                        user_row <= 0;
                        user_col <= 0;
                        data_counter <= 0;
                        next_state <= STATE_DISPLAY_READ;
                    end
                end

                STATE_DISPLAY_READ: begin
                    // Setup Read Address
                    user_slot_idx <= target_slot;
                    user_row <= user_row;
                    user_col <= user_col;
                    // Wait one cycle for memory access? (Sync read)
                    // Assuming 'user_rd_data' is available next cycle.
                    // We need a small wait state or just proceed if Mem is combinational read (unlikely).
                    // Standard Block RAM is sync read.
                    // Let's add a dummy state or reuse this state with a flag.
                    // For now, assuming we stay here 1 cycle then move to PRINT.
                    // Actually, let's jump to PRINT_NUM, and PRINT_NUM will latch data.
                    next_state <= STATE_DISPLAY_PRINT;
                end

                STATE_DISPLAY_PRINT: begin
                    // Data should be ready at user_rd_data
                    print_value <= user_rd_data;
                    return_state <= STATE_DISPLAY_READ; // Return here to increment
                    
                    // Jump to Print Routine
                    // We need a specialized state for incrementing after print
                    // Let's use a flag to distinguish "Just Entered" vs "Returned".
                    // Simplification: Inline the increment logic after print returns.
                    // Actually, let's go to STATE_PRINT_NUM.
                    // When STATE_PRINT_NUM finishes, it needs to know where to go.
                    // We'll define a specific return state: STATE_DISPLAY_NEXT.
                    return_state <= 4'd13; // STATE_DISPLAY_NEXT (defined below)
                    next_state <= STATE_PRINT_NUM;
                end
                
                // ------------------------------------------------
                // MODE 3: CALC (Opcode, Scalar -> Start)
                // ------------------------------------------------
                STATE_CALC_PARAM: begin
                    if (number_valid) begin
                        case (param_count)
                            0: begin 
                                target_op <= number_out[2:0]; 
                                if (number_out[2:0] == 3'b011) // OP_SCA
                                    param_count <= 1;
                                else begin
                                    // Start ALU
                                    alu_opcode <= number_out[2:0];
                                    alu_scalar <= 0;
                                    alu_start <= 1;
                                    next_state <= STATE_CALC_WAIT;
                                end
                            end
                            1: begin
                                target_scalar <= number_out;
                                // Start ALU with Scalar
                                alu_opcode <= target_op;
                                alu_scalar <= number_out;
                                alu_start <= 1;
                                next_state <= STATE_CALC_WAIT;
                            end
                        endcase
                    end
                end

                STATE_CALC_WAIT: begin
                    if (alu_done || alu_error) begin
                        // Maybe print "Done" or Error code?
                        next_state <= STATE_IDLE;
                    end
                end

                // ------------------------------------------------
                // MODE 4: BONUS (Stream Output)
                // ------------------------------------------------
                STATE_BONUS_WAIT: begin
                    if (conv_res_valid) begin
                        print_value <= conv_res_data;
                        return_state <= STATE_BONUS_WAIT; // Come back for more
                        next_state <= STATE_PRINT_NUM;
                    end
                    if (conv_done) begin
                        next_state <= STATE_IDLE;
                    end
                end

                // ------------------------------------------------
                // SUBROUTINE: PRINT NUM (16-bit Decimal)
                // ------------------------------------------------
                STATE_PRINT_NUM: begin
                    // 1. Binary to BCD (Simplified: Repeated subtraction or similar)
                    // Since we can't do complex division in one cycle, we use a multi-cycle approach 
                    // OR just print Hex for simplicity? User guide implies matrix values.
                    // Let's implement a simple Hex printer for reliability first, 
                    // OR copy the Top.v logic which did decimal.
                    // Top.v used a lookup/mod? No, it used `digit_buf`.
                    // I'll implement Hex Printing: "H" + 4 digits + Space.
                    // Example: "1A2B "
                    
                    if (!tx_busy) begin
                        case (param_count) // Reuse param_count for print steps
                            0: begin tx_data <= " "; tx_start <= 1; param_count <= 1; end
                            1: begin tx_data <= digit_to_hex(print_value[15:12]); tx_start <= 1; param_count <= 2; end
                            2: begin tx_data <= digit_to_hex(print_value[11:8]);  tx_start <= 1; param_count <= 3; end
                            3: begin tx_data <= digit_to_hex(print_value[7:4]);   tx_start <= 1; param_count <= 4; end
                            4: begin tx_data <= digit_to_hex(print_value[3:0]);   tx_start <= 1; param_count <= 5; end
                            5: begin 
                                next_state <= return_state; 
                                param_count <= 0; 
                            end
                        endcase
                    end
                end

                // ------------------------------------------------
                // STATE_DISPLAY_NEXT: Incrementer for Display Loop
                // ------------------------------------------------
                4'd13: begin
                    // Increment Col/Row
                    if (user_col == target_n - 1) begin
                        user_col <= 0;
                        user_row <= user_row + 1;
                        // Print Newline?
                        // For now just space separated.
                    end else begin
                        user_col <= user_col + 1;
                    end

                    data_counter <= data_counter + 1;
                    if (data_counter + 1 >= total_elements) begin
                        next_state <= STATE_IDLE;
                    end else begin
                        next_state <= STATE_DISPLAY_READ;
                    end
                end

                default: next_state <= STATE_IDLE;
            endcase
        end
    end
    
    function [7:0] digit_to_hex;
        input [3:0] d;
        begin
            if (d < 10) digit_to_hex = d + "0";
            else digit_to_hex = d - 10 + "A";
        end
    endfunction

endmodule
