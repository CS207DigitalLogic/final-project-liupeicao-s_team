`timescale 1ns / 1ps

module Seg_Driver (
    input wire clk,
    input wire rst_n,
    input wire [3:0] current_state, // 来自 FSM 的状态
    input wire [3:0] time_left,     // 来自 Timer 的倒计时
    input wire [2:0] sw_mode,       // 开关模式 SW[7:5]
    input wire [7:0] in_count,      // 当前输入计数
    input wire [2:0] alu_opcode,    // ALU Opcode for display
    input wire [31:0] bonus_cycles, // Bonus 周期数
    
    output reg [7:0] seg_out,       // 段选 (Active High)
    output reg [7:0] seg_an         // 位选 (Active High)
);

    // =========================================================================
    // 1. Segment Encoding (Reference: lab5_verilog_basic4.pdf Style)
    //    Format: Active High Binary (1 = ON)
    //    Mapping: [7:0] = a b c d e f g . (MSB=a, LSB=dot/unused)
    // =========================================================================
    
    // Digits 0-9
    localparam CHAR_0 = 8'b1111_1100; // a,b,c,d,e,f
    localparam CHAR_1 = 8'b0110_0000; // b,c
    localparam CHAR_2 = 8'b1101_1010; // a,b,d,e,g
    localparam CHAR_3 = 8'b1111_0010; // a,b,c,d,g
    localparam CHAR_4 = 8'b0110_0110; // b,c,f,g
    localparam CHAR_5 = 8'b1011_0110; // a,c,d,f,g
    localparam CHAR_6 = 8'b1011_1110; // a,c,d,e,f,g
    localparam CHAR_7 = 8'b1110_0000; // a,b,c
    localparam CHAR_8 = 8'b1111_1110; // All
    localparam CHAR_9 = 8'b1111_0110; // a,b,c,d,f,g

    // Letters & Symbols
    localparam CHAR_A = 8'b1110_1110; // A
    localparam CHAR_b = 8'b0011_1110; // b
    localparam CHAR_C = 8'b1001_1100; // C
    localparam CHAR_c = 8'b0001_1010; // c
    localparam CHAR_d = 8'b0111_1010; // d
    localparam CHAR_E = 8'b1001_1110; // E
    localparam CHAR_F = 8'b1000_1110; // F
    localparam CHAR_G = 8'b1011_1100; // G (a,c,d,e,f)
    localparam CHAR_H = 8'b0110_1110; // H
    localparam CHAR_I = 8'b0010_0000; // I (b,c -> 1? or e,f -> I? Using 1 style)
    localparam CHAR_L = 8'b0001_1100; // L
    localparam CHAR_n = 8'b0010_1010; // n
    localparam CHAR_o = 8'b0011_1010; // o
    localparam CHAR_P = 8'b1100_1110; // P
    localparam CHAR_r = 8'b0000_1010; // r
    localparam CHAR_S = 8'b1011_0110; // S (Same as 5)
    localparam CHAR_t = 8'b0001_1110; // t
    localparam CHAR_U = 8'b0111_1100; // U
    localparam CHAR_u = 8'b0011_1000; // u
    localparam CHAR_y = 8'b0111_0110; // y
    localparam CHAR_MINUS = 8'b0000_0010; // -
    localparam CHAR_BLANK = 8'b0000_0000; // Blank

    // State Definition
    // 假设 Error 状态为 14 (基于旧代码 8'b1001_1110 截断为 4'b1110)
    localparam STATE_CALC_ERROR = 4'd14; 

    reg [7:0] digit_map [0:7]; // 8 Digits Buffer

    // Helper Function: Hex to Char Code
    function [7:0] get_hex;
        input [3:0] val;
        begin
            case(val)
                4'h0: get_hex = CHAR_0;
                4'h1: get_hex = CHAR_1;
                4'h2: get_hex = CHAR_2;
                4'h3: get_hex = CHAR_3;
                4'h4: get_hex = CHAR_4;
                4'h5: get_hex = CHAR_5;
                4'h6: get_hex = CHAR_6;
                4'h7: get_hex = CHAR_7;
                4'h8: get_hex = CHAR_8;
                4'h9: get_hex = CHAR_9;
                4'hA: get_hex = CHAR_A;
                4'hB: get_hex = CHAR_b;
                4'hC: get_hex = CHAR_C;
                4'hD: get_hex = CHAR_d;
                4'hE: get_hex = CHAR_E;
                4'hF: get_hex = CHAR_F;
                default: get_hex = CHAR_BLANK;
            endcase
        end
    endfunction

    // =========================================================================
    // 2. Display Logic Mapping
    // =========================================================================
    always @(*) begin
        // Default Clean
        digit_map[7] = CHAR_BLANK; digit_map[6] = CHAR_BLANK; digit_map[5] = CHAR_BLANK; digit_map[4] = CHAR_BLANK;
        digit_map[3] = CHAR_BLANK; digit_map[2] = CHAR_BLANK; digit_map[1] = CHAR_BLANK; digit_map[0] = CHAR_BLANK;

        if (current_state == STATE_CALC_ERROR) begin
            // "Err XX" (XX = time_left)
            digit_map[7] = CHAR_E;
            digit_map[6] = CHAR_r;
            digit_map[5] = CHAR_r;
            
            if (time_left < 10) begin
                digit_map[1] = CHAR_BLANK;
                digit_map[0] = get_hex(time_left);
            end else begin
                digit_map[1] = CHAR_1;
                digit_map[0] = get_hex(time_left - 10);
            end
        end else begin
            case (sw_mode)
                // -----------------------------------------------------------------
                // Mode 0: IDLE / INPUT -> "InPut"
                // -----------------------------------------------------------------
                3'b000: begin 
                    digit_map[7] = CHAR_1; // I
                    digit_map[6] = CHAR_n;
                    digit_map[5] = CHAR_P;
                    digit_map[4] = CHAR_u;
                    digit_map[3] = CHAR_t;
                    
                    // Show Count in Hex
                    digit_map[1] = get_hex(in_count[7:4]);
                    digit_map[0] = get_hex(in_count[3:0]);
                end
                
                // -----------------------------------------------------------------
                // Mode 1: GEN RANDOM -> "GEn"
                // -----------------------------------------------------------------
                3'b001: begin 
                    digit_map[7] = CHAR_G;
                    digit_map[6] = CHAR_E;
                    digit_map[5] = CHAR_n;
                end
                
                // -----------------------------------------------------------------
                // Mode 2: DISPLAY -> "diSP"
                // -----------------------------------------------------------------
                3'b010: begin 
                    digit_map[7] = CHAR_d;
                    digit_map[6] = CHAR_1; // i
                    digit_map[5] = CHAR_S;
                    digit_map[4] = CHAR_P;
                end
                
                // -----------------------------------------------------------------
                // Mode 3: CALC -> "CALC" + Opcode
                // -----------------------------------------------------------------
                3'b011: begin 
                    digit_map[7] = CHAR_C;
                    digit_map[6] = CHAR_A;
                    digit_map[5] = CHAR_L;
                    digit_map[4] = CHAR_C;
                    
                    // Opcode Display
                    case(alu_opcode)
                        3'b000: digit_map[0] = CHAR_A; // Add
                        3'b001: digit_map[0] = CHAR_b; // Sub
                        3'b010: digit_map[0] = CHAR_C; // Mul
                        3'b011: digit_map[0] = CHAR_S; // Sca
                        3'b100: digit_map[0] = CHAR_t; // Tra
                        default: digit_map[0] = CHAR_MINUS;
                    endcase
                end
                
                // -----------------------------------------------------------------
                // Mode 4: BONUS -> "bOnUS"
                // -----------------------------------------------------------------
                3'b100: begin 
                    if (bonus_cycles > 0) begin
                        // Display Cycles (Hex) - Full 32 bits
                        digit_map[7] = get_hex(bonus_cycles[31:28]);
                        digit_map[6] = get_hex(bonus_cycles[27:24]);
                        digit_map[5] = get_hex(bonus_cycles[23:20]);
                        digit_map[4] = get_hex(bonus_cycles[19:16]);
                        digit_map[3] = get_hex(bonus_cycles[15:12]);
                        digit_map[2] = get_hex(bonus_cycles[11:8]);
                        digit_map[1] = get_hex(bonus_cycles[7:4]);
                        digit_map[0] = get_hex(bonus_cycles[3:0]);
                    end else begin
                        digit_map[7] = CHAR_b;
                        digit_map[6] = CHAR_0; // O
                        digit_map[5] = CHAR_n;
                        digit_map[4] = CHAR_U;
                        digit_map[3] = CHAR_S;
                    end
                end
                
                default: begin
                    // Undefined Mode
                    digit_map[3] = CHAR_MINUS; digit_map[2] = CHAR_MINUS; digit_map[1] = CHAR_MINUS; digit_map[0] = CHAR_MINUS;
                end
            endcase
        end
    end

    // =========================================================================
    // 3. Dynamic Scan Logic
    // =========================================================================
    reg [19:0] scan_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan_cnt <= 0;
            seg_an <= 8'h00; // Reset All Off (Active High)
            seg_out <= 8'h00; // Reset All Off
        end else begin
            scan_cnt <= scan_cnt + 1;
            
            // Scan Speed: ~95Hz (100MHz / 2^20 * 8 is slow, 2^17 is better)
            // Use blocking assignments in always block for next state or just standard sync update
            // Here using the scan_cnt directly to derive select
        end
    end
    
    wire [2:0] scan_sel = scan_cnt[19:17]; 

    always @(*) begin
        // Anode Control (Active High)
        // 0000_0001, 0000_0010, ...
        case(scan_sel)
            3'd0: seg_an = 8'b0000_0001;
            3'd1: seg_an = 8'b0000_0010;
            3'd2: seg_an = 8'b0000_0100;
            3'd3: seg_an = 8'b0000_1000;
            3'd4: seg_an = 8'b0001_0000;
            3'd5: seg_an = 8'b0010_0000;
            3'd6: seg_an = 8'b0100_0000;
            3'd7: seg_an = 8'b1000_0000;
        endcase
        
        // Segment Output Control (Active High)
        seg_out = digit_map[scan_sel];
    end

endmodule
