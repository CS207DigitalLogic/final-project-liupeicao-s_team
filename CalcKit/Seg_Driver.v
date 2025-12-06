`timescale 1ns / 1ps

module Seg_Driver (
    input wire clk,
    input wire rst_n,
    input wire [3:0] current_state, // 来自 FSM 的状态
    input wire [3:0] time_left,     // 来自 Timer 的倒计时
    input wire [2:0] sw_mode,       // 开关模式 SW[7:5]
    input wire [7:0] in_count,      // 当前输入计数
    input wire [2:0] alu_opcode,    // 新增: ALU Opcode for display
    input wire [31:0] bonus_cycles, // 新增: Bonus 周期数
    
    output reg [7:0] seg_out,       // 段选 (CA/CC depending on board, assuming Active Low for now based on top.v 'FF' init)
    output reg [7:0] seg_an         // 位选 (Active Low)
);

    // 状态定义 (参考 Central_FSM)
    localparam STATE_IDLE           = 4'd0;
    localparam STATE_CALC_ERROR     = 4'd12;
    // 其他状态可根据需要显示不同内容

    // 字符编码 (共阴/共阳需确认，这里假设低电平有效点亮段)
    // . g f e d c b a
    localparam CHAR_0 = 8'hC0; 
    localparam CHAR_1 = 8'hF9;
    localparam CHAR_2 = 8'hA4;
    localparam CHAR_3 = 8'hB0;
    localparam CHAR_4 = 8'h99;
    localparam CHAR_5 = 8'h92;
    localparam CHAR_6 = 8'h82;
    localparam CHAR_7 = 8'hF8;
    localparam CHAR_8 = 8'h80;
    localparam CHAR_9 = 8'h90;
    
    localparam CHAR_A = 8'h88;
    localparam CHAR_C = 8'hC6;
    localparam CHAR_E = 8'h86;
    localparam CHAR_G = 8'hC2; // 'G' like in Gen
    localparam CHAR_H = 8'h89;
    localparam CHAR_I = 8'hCF; // 'I'
    localparam CHAR_L = 8'hC7;
    localparam CHAR_N = 8'hC8; // 'n'
    localparam CHAR_O = 8'hC0; // 'O' (0)
    localparam CHAR_P = 8'h8C;
    localparam CHAR_R = 8'hAF; // 'r'
    localparam CHAR_S = 8'h92; // 'S' (5)
    localparam CHAR_U = 8'hC1; // 'U'
    localparam CHAR_b = 8'h83; // 'b' (Bonus)
    localparam CHAR_d = 8'hA1; // 'd'
    localparam CHAR_o = 8'hA3; // 'o'
    localparam CHAR_T = 8'h87; // 't' used for Transpose (T)
    localparam CHAR_J = 8'hE1; // 'J' (approx)
    localparam CHAR_t = 8'h87; // 't'
    localparam CHAR_F = 8'h8E; // 'F'
    localparam CHAR_BLANK = 8'hFF;
    localparam CHAR_MINUS = 8'hBF; // '-'
    localparam CHAR_y     = 8'h91; // 'y'

    reg [7:0] disp_data [0:7]; // 8个数码管的显示内容
    
    // Need Opcode input
    // But interface only has sw_mode[2:0]
    // Wait, top.v passes sw_pin[7:5] as sw_mode.
    // But opcode is selected by sw_pin[4:2] in top.v logic.
    // We need opcode passed to Seg_Driver to display T, A, B, C, J
    // Or we can infer it from sw_mode if user uses sw[4:2] for opcode selection?
    // But Seg_Driver only gets `sw_mode` (3 bits).
    // We need to add `alu_opcode` input to Seg_Driver.
    
    // 1. 根据状态解码显示内容
    always @(*) begin
        // 默认全灭
        disp_data[7] = CHAR_BLANK; disp_data[6] = CHAR_BLANK; disp_data[5] = CHAR_BLANK; disp_data[4] = CHAR_BLANK;
        disp_data[3] = CHAR_BLANK; disp_data[2] = CHAR_BLANK; disp_data[1] = CHAR_BLANK; disp_data[0] = CHAR_BLANK;

        if (current_state == STATE_CALC_ERROR) begin
            // 显示 "Err  XX" (XX为倒计时)
            disp_data[7] = CHAR_E;
            disp_data[6] = CHAR_R;
            disp_data[5] = CHAR_R;
            disp_data[4] = CHAR_BLANK;
            // 倒计时数字
            if (time_left >= 10) begin
                disp_data[1] = CHAR_1;
                disp_data[0] = CHAR_0;
            end else begin
                disp_data[1] = CHAR_BLANK;
                case(time_left)
                    0: disp_data[0] = CHAR_0;
                    1: disp_data[0] = CHAR_1;
                    2: disp_data[0] = CHAR_2;
                    3: disp_data[0] = CHAR_3;
                    4: disp_data[0] = CHAR_4;
                    5: disp_data[0] = CHAR_5;
                    6: disp_data[0] = CHAR_6;
                    7: disp_data[0] = CHAR_7;
                    8: disp_data[0] = CHAR_8;
                    9: disp_data[0] = CHAR_9;
                    default: disp_data[0] = CHAR_MINUS;
                endcase
            end
        end else begin
            // 根据模式开关显示
            case (sw_mode)
                3'b000: begin // Input Dim -> "InPut"
                    disp_data[7] = CHAR_I; disp_data[6] = CHAR_N; disp_data[5] = CHAR_P; disp_data[4] = CHAR_U; disp_data[3] = CHAR_t;
                    // Show count on last 2 digits
                    if (in_count > 0) begin
                         case (in_count % 10)
                             0: disp_data[0] = CHAR_0; 1: disp_data[0] = CHAR_1; 2: disp_data[0] = CHAR_2; 3: disp_data[0] = CHAR_3;
                             4: disp_data[0] = CHAR_4; 5: disp_data[0] = CHAR_5; 6: disp_data[0] = CHAR_6; 7: disp_data[0] = CHAR_7;
                             8: disp_data[0] = CHAR_8; 9: disp_data[0] = CHAR_9; default: disp_data[0] = CHAR_BLANK;
                         endcase
                         case ((in_count / 10) % 10)
                             0: disp_data[1] = CHAR_0; 1: disp_data[1] = CHAR_1; 2: disp_data[1] = CHAR_2; 3: disp_data[1] = CHAR_3;
                             4: disp_data[1] = CHAR_4; 5: disp_data[1] = CHAR_5; 6: disp_data[1] = CHAR_6; 7: disp_data[1] = CHAR_7;
                             8: disp_data[1] = CHAR_8; 9: disp_data[1] = CHAR_9; default: disp_data[1] = CHAR_BLANK;
                         endcase
                    end
                end
                3'b001: begin // Gen Random -> "Gen"
                    disp_data[7] = CHAR_G; disp_data[6] = CHAR_E; disp_data[5] = CHAR_N;
                end
                3'b010: begin // Display -> "diSP"
                    disp_data[7] = CHAR_d; disp_data[6] = CHAR_I; disp_data[5] = CHAR_S; disp_data[4] = CHAR_P;
                end
                3'b011: begin // Calc -> "CALC" + Opcode
                    disp_data[7] = CHAR_C; disp_data[6] = CHAR_A; disp_data[5] = CHAR_L; disp_data[4] = CHAR_C;
                    // Display Opcode char at digit 0
                    // Opcode: 000(ADD), 001(SUB), 010(MUL), 011(SCA), 100(TRA)
                    // User Req: T(Trans), A(Add), B(Scalar/Beta?), C(Mul?), J(Conv)
                    // Mapping:
                    // ADD (000) -> A
                    // SUB (001) -> S (User didn't specify SUB char, assuming 'S' or maybe only ADD is required?)
                    // MUL (010) -> C (User said Matrix Mul C)
                    // SCA (011) -> B (User said Scalar Mul B)
                    // TRA (100) -> T
                    // CONV is Bonus mode (sw_mode=100), handled below.
                    
                    case (alu_opcode)
                        3'b000: disp_data[0] = CHAR_A; // ADD
                        3'b001: disp_data[0] = CHAR_S; // SUB (User didn't specify, using S)
                        3'b010: disp_data[0] = CHAR_C; // MUL (User: C)
                        3'b011: disp_data[0] = CHAR_b; // SCA (User: B) - Using 'b' for B
                        3'b100: disp_data[0] = CHAR_T; // TRA (User: T)
                        default: disp_data[0] = CHAR_BLANK;
                    endcase
                end
                3'b100: begin // Bonus -> "bonUS" + J
                    if (bonus_cycles > 0) begin
                        // Display "Cy" + count
                        disp_data[7] = CHAR_C; disp_data[6] = CHAR_y; 
                        disp_data[5] = CHAR_BLANK; disp_data[4] = CHAR_BLANK;
                        disp_data[3] = (bonus_cycles >= 1000) ? get_char((bonus_cycles/1000)%10) : CHAR_BLANK;
                        disp_data[2] = (bonus_cycles >= 100) ? get_char((bonus_cycles/100)%10) : CHAR_BLANK;
                        disp_data[1] = (bonus_cycles >= 10) ? get_char((bonus_cycles/10)%10) : CHAR_BLANK;
                        disp_data[0] = get_char(bonus_cycles%10);
                    end else begin
                        disp_data[7] = CHAR_b; disp_data[6] = CHAR_o; disp_data[5] = CHAR_N; disp_data[4] = CHAR_U; disp_data[3] = CHAR_S;
                        disp_data[0] = CHAR_J;
                    end
                end
                3'b101: begin // Config -> "ConF"
                    disp_data[7] = CHAR_C; disp_data[6] = CHAR_o; disp_data[5] = CHAR_N; disp_data[4] = CHAR_F;
                    // Show current config value? We need input for that. 
                    // Seg_Driver doesn't have config_val input.
                    // But we have 'time_left' input. In config mode (State 0), time_left is not active.
                    // Wait, top.v connects 'time_left' from Timer_Unit.
                    // Timer_Unit output time_left depends on 'start_timer'.
                    // If timer not started, time_left is 0 or reset value.
                    // To show the config value, we need to pass it to Seg_Driver.
                    // Let's just show "ConF" for now to be safe, or "ConF 10" if we can.
                    // Actually, user sets it blindly? No, usually want feedback.
                    // For now, just "ConF" is better than "----".
                    // If user enters number, parser works in top.v.
                    // We can reuse 'in_count' or 'time_left' if we multiplex in top.v?
                    // Too risky to change top.v interface now.
                    // Just "ConF" is enough to show mode is active.
                end
                default: begin // "----"
                    disp_data[7] = CHAR_MINUS; disp_data[6] = CHAR_MINUS; disp_data[5] = CHAR_MINUS; disp_data[4] = CHAR_MINUS;
                end
            endcase
        end
    end

    // 2. 动态扫描逻辑
    reg [19:0] scan_cnt; // 扫描分频
    reg [2:0]  scan_idx; // 当前扫描位 0-7
    
    // User reports "All 8s" -> Likely Segments Active High or Anode Active High inverted?
    // If user sees 8s with my code (seg_an active low scan, seg_out active low char), 
    // then 'FF' output (BLANK) is turning all ON.
    // This implies Segment lines are Active High (Common Cathode).
    // If so, we need to invert seg_out.
    // Also, if Anodes are Active Low, we keep seg_an.
    // Let's invert seg_out logic.
    
    reg [7:0] seg_out_inv;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan_cnt <= 0;
            scan_idx <= 0;
            seg_an   <= 8'hFF;
            seg_out  <= 8'h00; // Inverted BLANK (FF -> 00)
        end else begin
            // 刷新率控制: 100MHz / 2^17 ~= 762Hz (每位 ~100Hz)
            scan_cnt <= scan_cnt + 1;
            if (scan_cnt[16]) begin 
                scan_cnt <= 0;
                scan_idx <= scan_idx + 1;
            end

            // 位选输出 (Active Low)
            case (scan_idx)
                3'd0: seg_an <= 8'b1111_1110;
                3'd1: seg_an <= 8'b1111_1101;
                3'd2: seg_an <= 8'b1111_1011;
                3'd3: seg_an <= 8'b1111_0111;
                3'd4: seg_an <= 8'b1110_1111;
                3'd5: seg_an <= 8'b1101_1111;
                3'd6: seg_an <= 8'b1011_1111;
                3'd7: seg_an <= 8'b0111_1111;
            endcase

            // 段选输出
            // Remove inversion ~disp_data[scan_idx]
            // Assuming Common Anode (0=ON) and CHAR_x codes are Active Low (0=ON)
            seg_out <= disp_data[scan_idx];
        end
    end

    function [7:0] get_char;
        input [3:0] val;
        begin
            case(val)
                0: get_char = CHAR_0; 1: get_char = CHAR_1; 2: get_char = CHAR_2; 3: get_char = CHAR_3;
                4: get_char = CHAR_4; 5: get_char = CHAR_5; 6: get_char = CHAR_6; 7: get_char = CHAR_7;
                8: get_char = CHAR_8; 9: get_char = CHAR_9; default: get_char = CHAR_BLANK;
            endcase
        end
    endfunction

endmodule
