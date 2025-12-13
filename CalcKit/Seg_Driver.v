`timescale 1ns / 1ps

module Seg_Driver (
    input wire clk,
    input wire rst_n,
    
    // System Status
    input wire [3:0] current_state, // FSM State
    input wire [3:0] time_left,     // Timer for error/countdown
    input wire [2:0] sw_mode,       // SW[7:5]
    input wire [7:0] in_count,      // Input count
    input wire [2:0] alu_opcode,    // ALU Operation type
    input wire [31:0] bonus_cycles, // Bonus result
    
    // Output Interface
    output reg [7:0] seg_cs,        // Chip Select (Active High)
    output reg [7:0] seg_data_0,    // Left Group Data (Active High)
    output reg [7:0] seg_data_1     // Right Group Data (Active High)
);

    // =========================================================================
    // 1. Parameter Definitions
    // =========================================================================
    
    // Segment Codes (Active High, LSB=a, MSB=dp)
    // Format: {dp, g, f, e, d, c, b, a}
    localparam CHAR_0 = 8'h3F; // 0011 1111
    localparam CHAR_1 = 8'h06; // 0000 0110
    localparam CHAR_2 = 8'h5B; // 0101 1011
    localparam CHAR_3 = 8'h4F; // 0100 1111
    localparam CHAR_4 = 8'h66; // 0110 0110
    localparam CHAR_5 = 8'h6D; // 0110 1101
    localparam CHAR_6 = 8'h7D; // 0111 1101
    localparam CHAR_7 = 8'h07; // 0000 0111
    localparam CHAR_8 = 8'h7F; // 0111 1111
    localparam CHAR_9 = 8'h6F; // 0110 1111
    
    localparam CHAR_A = 8'h77; // A: a,b,c,e,f,g
    localparam CHAR_b = 8'h7C; // b: c,d,e,f,g
    localparam CHAR_C = 8'h39; // C: a,d,e,f
    localparam CHAR_d = 8'h5E; // d: b,c,d,e,g
    localparam CHAR_E = 8'h79; // E: a,d,e,f,g
    localparam CHAR_F = 8'h71; // F: a,e,f,g
    localparam CHAR_H = 8'h76; // H: b,c,e,f,g
    localparam CHAR_I = 8'h30; // I: b,c (like 1) or 06? Let's use 30 (e,f) for left align? No, just 06 or 30.
                               // Manual 1 is b,c. Let's use 06.
    localparam CHAR_J = 8'h1E; // J: b,c,d,e
    localparam CHAR_L = 8'h38; // L: d,e,f
    localparam CHAR_n = 8'h54; // n: c,e,g
    localparam CHAR_o = 8'h5C; // o: c,d,e,g
    localparam CHAR_P = 8'h73; // P: a,b,e,f,g
    localparam CHAR_r = 8'h50; // r: e,g
    localparam CHAR_S = 8'h6D; // S: Same as 5
    localparam CHAR_t = 8'h78; // t: d,e,f,g
    localparam CHAR_U = 8'h3E; // U: b,c,d,e,f
    localparam CHAR_y = 8'h6E; // y: b,c,d,f,g
    localparam CHAR_MINUS = 8'h40; // g
    localparam CHAR_BLANK = 8'h00; 

    // FSM States (From Central_FSM)
    localparam STATE_IDLE           = 4'd0;
    localparam STATE_INPUT_DIM      = 4'd1;
    localparam STATE_INPUT_DATA     = 4'd2;
    localparam STATE_DISPLAY        = 4'd3;
    localparam STATE_BONUS          = 4'd4;
    localparam STATE_CONFIG         = 4'd5;
    localparam STATE_CALC_SELECT    = 4'd6;
    localparam STATE_CALC_CHECK     = 4'd9;
    localparam STATE_CALC_EXEC      = 4'd10;
    localparam STATE_CALC_DONE      = 4'd11;
    localparam STATE_CALC_ERROR     = 4'd12;
    localparam STATE_CONFIG_MODE    = 4'd13;

    // =========================================================================
    // 2. Display Content Logic
    // =========================================================================
    reg [7:0] disp_val [0:7]; // 8 digits content

    always @(*) begin
        // Default Blank
        disp_val[7] = CHAR_BLANK; disp_val[6] = CHAR_BLANK; disp_val[5] = CHAR_BLANK; disp_val[4] = CHAR_BLANK;
        disp_val[3] = CHAR_BLANK; disp_val[2] = CHAR_BLANK; disp_val[1] = CHAR_BLANK; disp_val[0] = CHAR_BLANK;
        
        // Priority 1: Error State (Highest Priority)
    // Supports explicit Error State (12) OR implicit Error Flag via Time Left (if needed)
    // Current design: top.v sets state to CALC_ERROR when error occurs.
    if (current_state == STATE_CALC_ERROR) begin
        // "Err "
        disp_val[7] = CHAR_E;
        disp_val[6] = CHAR_r;
        disp_val[5] = CHAR_r;
        disp_val[4] = CHAR_BLANK;
        
        // No Countdown, just Err. Blank the rest or show something else?
        // User requirement: "此阶段不显示倒计时数字，仅显示固定的 Err 字符"
        disp_val[3] = CHAR_BLANK;
        disp_val[2] = CHAR_BLANK;
        disp_val[1] = CHAR_BLANK;
        disp_val[0] = CHAR_BLANK;
    end
    // Priority 2: IDLE State
        else if (current_state == STATE_IDLE) begin
            // "IDLE"
            // Display on Left or Right? Usually Left or spread.
            // Let's put "IDLE" on 7,6,5,4 (Left Group)
            disp_val[7] = 8'h30; // I (using existing definition or 06)
            disp_val[6] = CHAR_d;
            disp_val[5] = CHAR_L;
            disp_val[4] = CHAR_E;
        end
        // Priority 3: Config State
        else if (current_state == STATE_CONFIG_MODE) begin
            // "ConF"
            disp_val[7] = CHAR_C; disp_val[6] = CHAR_o; disp_val[5] = CHAR_n; disp_val[4] = CHAR_F;
            // Maybe show something on right?
        end
        else begin
            case (sw_mode)
                3'b000: begin // Input Mode -> "InPut XX"
                    disp_val[7] = CHAR_I; disp_val[6] = CHAR_n; disp_val[5] = CHAR_P; disp_val[4] = CHAR_U; disp_val[3] = CHAR_t;
                    // Show in_count at 1,0
                    disp_val[1] = get_hex_char(in_count[7:4]);
                    disp_val[0] = get_hex_char(in_count[3:0]);
                end
                
                3'b010: begin // Display Mode -> "diSP"
                    disp_val[7] = CHAR_d; disp_val[6] = CHAR_1; // 'i'
                    disp_val[5] = CHAR_S; disp_val[4] = CHAR_P;
                end
                
                3'b011: begin // Calc Mode
                    // "CALC  X" (X = Opcode Char)
                    // Requirement: Keep Rightmost (disp_val[0]) as 'C'.
                    // Requirement: Set Left 4 (disp_val[4]) as Opcode Symbol.
                    
                    disp_val[7] = CHAR_C; disp_val[6] = CHAR_A; disp_val[5] = CHAR_L; 
                    
                    // Set Opcode on Left 4 (H1)
                    case (alu_opcode)
                        3'b000: disp_val[4] = CHAR_A; // Add
                        3'b001: disp_val[4] = CHAR_b; // Sub
                        3'b010: disp_val[4] = CHAR_C; // Mul
                        3'b011: disp_val[4] = CHAR_S; // Scalar
                        3'b100: disp_val[4] = CHAR_t; // Transpose
                        default: disp_val[4] = CHAR_MINUS;
                    endcase
                    
                    disp_val[3] = CHAR_BLANK; disp_val[2] = CHAR_BLANK; disp_val[1] = CHAR_BLANK;
                    disp_val[0] = CHAR_C; // Rightmost fixed to C
                end
                
                3'b100: begin // Bonus Mode -> "bonUS J" or Cycles
                    if (bonus_cycles > 0) begin
                        // Show cycles (Hex or Decimal? Usually Hex for large numbers, or lower bits)
                        // Assuming showing lower 16 bits in hex for now
                        disp_val[7] = get_hex_char(bonus_cycles[15:12]);
                        disp_val[6] = get_hex_char(bonus_cycles[11:8]);
                        disp_val[5] = get_hex_char(bonus_cycles[7:4]);
                        disp_val[4] = get_hex_char(bonus_cycles[3:0]);
                        
                        disp_val[1] = CHAR_C; disp_val[0] = CHAR_y; // "Cy"
                    end else begin
                        disp_val[7] = CHAR_b; disp_val[6] = CHAR_o; disp_val[5] = CHAR_n; disp_val[4] = CHAR_U; disp_val[3] = CHAR_S;
                        disp_val[0] = CHAR_J; // Conv Op
                    end
                end
                
                3'b101: begin // Config -> "ConF"
                    disp_val[7] = CHAR_C; disp_val[6] = CHAR_o; disp_val[5] = CHAR_n; disp_val[4] = CHAR_F;
                end
                
                default: begin
                    disp_val[7] = CHAR_MINUS; disp_val[6] = CHAR_MINUS;
                end
            endcase
        end
    end

    // =========================================================================
    // 3. Scanning Logic
    // =========================================================================
    // 100MHz clock. Refresh rate ~1kHz per digit -> 8kHz total scan.
    // 100,000,000 / 8,000 = 12,500.
    // Use 14-bit counter (16384). MSB change freq = 100M/16384 = 6.1kHz. Good.
    // Or 17 bit for slower debug visible scan.
    // Let's use 16 bit. 100M / 65536 = 1.5kHz. 1.5kHz / 8 = 190Hz. Good.
    
    reg [15:0] scan_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) scan_cnt <= 0;
        else scan_cnt <= scan_cnt + 1;
    end
    
    wire [2:0] scan_idx = scan_cnt[15:13]; // 0 to 7
    
    // Output Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            seg_cs <= 8'b00000000;
            seg_data_0 <= 8'b00000000;
            seg_data_1 <= 8'b00000000;
        end else begin
            // 1. Chip Select (Active High Decoder)
            case (scan_idx)
                3'd0: seg_cs <= 8'b00000001; // Left 1
                3'd1: seg_cs <= 8'b00000010; // Left 2
                3'd2: seg_cs <= 8'b00000100; // Left 3
                3'd3: seg_cs <= 8'b00001000; // Left 4
                3'd4: seg_cs <= 8'b00010000; // Right 1
                3'd5: seg_cs <= 8'b00100000; // Right 2
                3'd6: seg_cs <= 8'b01000000; // Right 3
                3'd7: seg_cs <= 8'b10000000; // Right 4
            endcase
            
            // 2. Data Output
            // If scan_idx is 0-3, we are driving Group 0 (Left). Group 1 (Right) should be 0?
            // Actually, seg_cs selects the digit.
            // But seg_data_0 goes to Left pins, seg_data_1 goes to Right pins.
            // If we activate seg_cs[0] (Left 1), we must drive seg_data_0. seg_data_1 is don't care (but safe to be 0).
            // If we activate seg_cs[4] (Right 1), we must drive seg_data_1. seg_data_0 is don't care.
            
            if (scan_idx < 4) begin
                // Left Group Scan (0-3)
                // Left Group Segments are on seg_data_1 (B4... Group 0)
                seg_data_1 <= disp_val[7 - scan_idx]; 
                seg_data_0 <= 8'b00000000; // Off
            end else begin
                // Right Group Scan (4-7)
                // Right Group Segments are on seg_data_0 (D4... Group 1)
                seg_data_1 <= 8'b00000000; // Off
                
                // Map disp_val[3..0] to Right Group
                // disp_val[3] -> Scan 4 (Right 1)
                // ...
                // disp_val[0] -> Scan 7 (Right 4)
                case(scan_idx)
                    4: seg_data_0 <= disp_val[3];
                    5: seg_data_0 <= disp_val[2];
                    6: seg_data_0 <= disp_val[1];
                    7: seg_data_0 <= disp_val[0];
                    default: seg_data_0 <= 8'b00000000;
                endcase
            end
        end
    end

    // Helper Function: Hex to Segment
    function [7:0] get_hex_char;
        input [3:0] val;
        begin
            case(val)
                4'h0: get_hex_char = CHAR_0;
                4'h1: get_hex_char = CHAR_1;
                4'h2: get_hex_char = CHAR_2;
                4'h3: get_hex_char = CHAR_3;
                4'h4: get_hex_char = CHAR_4;
                4'h5: get_hex_char = CHAR_5;
                4'h6: get_hex_char = CHAR_6;
                4'h7: get_hex_char = CHAR_7;
                4'h8: get_hex_char = CHAR_8;
                4'h9: get_hex_char = CHAR_9;
                4'hA: get_hex_char = CHAR_A;
                4'hB: get_hex_char = CHAR_b;
                4'hC: get_hex_char = CHAR_C;
                4'hD: get_hex_char = CHAR_d;
                4'hE: get_hex_char = CHAR_E;
                4'hF: get_hex_char = CHAR_F;
                default: get_hex_char = CHAR_BLANK;
            endcase
        end
    endfunction

endmodule
