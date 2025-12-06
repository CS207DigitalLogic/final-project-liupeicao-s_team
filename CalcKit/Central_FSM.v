

`timescale 1ns / 1ps

module Central_FSM (
    input wire clk,                 // 系统时钟
    input wire rst_n,               // 系统复位 (Active Low)
    input wire [2:0] sw,            // 开关输入 (SW[2:0])
    input wire btn_c,               // 确认按键 (需为单脉冲信号)

    // --- 来自各子模块的状态跳转信号 (握手信号) ---
    input wire input_dim_done,      // INPUT_DIM -> INPUT_DATA: 接收 m,n 完成
    input wire input_data_done,     // INPUT_DATA -> IDLE: 接收 m*n 数据完成
    input wire gen_random_done,     // GEN_RANDOM -> IDLE: 随机填充完成
    input wire bonus_done,          // BONUS_RUN -> IDLE: 卷积及显示完成
    input wire display_id_conf,     // DISPLAY_WAIT -> DISPLAY_PRINT: 确认矩阵编号
    input wire uart_tx_done,        // DISPLAY_PRINT -> IDLE: UART 发送完成
    
    // --- 矩阵运算模式信号 ---
    input wire calc_mat_conf,       // CALC_SELECT_MAT -> CALC_CHECK: 输入矩阵ID并确认
    input wire check_valid,         // CALC_CHECK -> CALC_EXEC: 维度匹配 (Valid)
    input wire check_invalid,       // CALC_CHECK -> CALC_ERROR: 维度不匹配 (Invalid)
    input wire alu_done,            // CALC_EXEC -> CALC_DONE: ALU 计算结束
    input wire result_display_done, // CALC_DONE -> IDLE: 显示结果并返回
    input wire error_timeout,       // CALC_ERROR -> CALC_SELECT_MAT: 倒计时结束

    // --- 输出状态，用于控制数据通路 ---
    output reg [3:0] current_state
);

    // --- 状态定义 (State Encoding) ---
    localparam STATE_IDLE           = 4'd0;
    
    // 输入模式
    localparam STATE_INPUT_DIM      = 4'd1;  // 输入维度
    localparam STATE_INPUT_DATA     = 4'd2;  // 输入数据
    
    // 随机生成模式
    localparam STATE_GEN_RANDOM     = 4'd3;  // 随机生成
    
    // 卷积模式 (Bonus)
    localparam STATE_BONUS_RUN      = 4'd4;  // 卷积运算
    
    // 展示模式
    localparam STATE_DISPLAY_WAIT   = 4'd5;  // 选择矩阵展示
    localparam STATE_DISPLAY_PRINT  = 4'd6;  // UART 输出
    
    // 矩阵运算模式 (Calc Mode)
    localparam STATE_CALC_SELECT_OP = 4'd7;  // 选运算类型
    localparam STATE_CALC_SELECT_MAT= 4'd8;  // 选择操作数
    localparam STATE_CALC_CHECK     = 4'd9;  // 合法性检查
    localparam STATE_CALC_EXEC      = 4'd10; // 计算执行
    localparam STATE_CALC_DONE      = 4'd11; // 计算完成
    localparam STATE_CALC_ERROR     = 4'd12; // 错误倒计时

    // 内部状态寄存器
    reg [3:0] next_state;

    // --- 时序逻辑：状态更新 ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= STATE_IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    // --- 组合逻辑：下一状态判断 ---
    always @(*) begin
        // 默认保持当前状态，防止 latch
        next_state = current_state;

        case (current_state)
            // 1. 主菜单状态 (IDLE)
            STATE_IDLE: begin
                if (btn_c) begin
                    case (sw)
                        3'b000: next_state = STATE_INPUT_DIM;
                        3'b001: next_state = STATE_GEN_RANDOM;
                        3'b100: next_state = STATE_BONUS_RUN;
                        3'b010: next_state = STATE_DISPLAY_WAIT;
                        3'b011: next_state = STATE_CALC_SELECT_OP;
                        default: next_state = STATE_IDLE;
                    endcase
                end
            end

            // 2. 数据输入流程
            STATE_INPUT_DIM: begin
                if (input_dim_done) 
                    next_state = STATE_INPUT_DATA;
            end
            STATE_INPUT_DATA: begin
                if (input_data_done) 
                    next_state = STATE_IDLE;
            end

            // 3. 随机生成流程
            STATE_GEN_RANDOM: begin
                if (gen_random_done) 
                    next_state = STATE_IDLE;
            end

            // 4. 卷积运算 (Bonus)
            STATE_BONUS_RUN: begin
                if (bonus_done) 
                    next_state = STATE_IDLE;
            end

            // 5. 矩阵展示流程
            STATE_DISPLAY_WAIT: begin
                if (display_id_conf) 
                    next_state = STATE_DISPLAY_PRINT;
            end
            STATE_DISPLAY_PRINT: begin
                if (uart_tx_done) 
                    next_state = STATE_IDLE;
            end

            // 6. 矩阵运算模式 (Calc Mode)
            STATE_CALC_SELECT_OP: begin
                // 图中为 "按下 Btn_C" 跳转到选数
                if (btn_c) 
                    next_state = STATE_CALC_SELECT_MAT;
            end

            STATE_CALC_SELECT_MAT: begin
                if (calc_mat_conf) 
                    next_state = STATE_CALC_CHECK;
            end

            STATE_CALC_CHECK: begin
                if (check_valid) 
                    next_state = STATE_CALC_EXEC;
                else if (check_invalid) 
                    next_state = STATE_CALC_ERROR;
            end

            STATE_CALC_EXEC: begin
                if (alu_done) 
                    next_state = STATE_CALC_DONE;
            end

            STATE_CALC_DONE: begin
                // 显示结果并返回 IDLE (注意这里是大回环回到 IDLE)
                if (result_display_done) 
                    next_state = STATE_IDLE;
            end

            STATE_CALC_ERROR: begin
                // 倒计时结束，重新输入 (回到 SELECT_MAT)
                if (error_timeout) 
                    next_state = STATE_CALC_SELECT_MAT;
                // 支持倒计时内重新确认 (Early Retry)
                // 如果用户在倒计时期间按下了确认键，我们认为他重新指定了矩阵
                // 跳转回 CHECK 进行检查 (前提是 top.v 在 ERROR 状态下允许修改矩阵选择并产生 calc_mat_conf 信号)
                // 但 calc_mat_conf 是 SELECT_MAT 状态产生的。
                // 我们可以在 ERROR 状态下复用 calc_mat_conf 信号作为跳转条件。
                else if (calc_mat_conf)
                    next_state = STATE_CALC_CHECK;
            end

            default: next_state = STATE_IDLE;
        endcase
    end

endmodule
