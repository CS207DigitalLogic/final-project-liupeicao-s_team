`timescale 1ns / 1ps

module LED_Driver(
    input clk,
    input rst_n,
    input err_flag,
    input calc_busy,
    input conv_busy,
    input [3:0] current_state,
    output reg [1:0] led
);

// 状态定义
localparam [3:0] 
    IDLE            = 4'b0000,
    CALC_ERROR      = 4'b1001,
    CALC_EXEC       = 4'b1010,
    BONUS_RUN       = 4'b1100;

// 闪烁控制
reg [23:0] blink_counter = 0;
reg blink_state = 0;

// 简化的LED控制
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        led <= 2'b00;
        blink_counter <= 0;
        blink_state <= 0;
    end else begin
        // 更新闪烁计数器
        blink_counter <= blink_counter + 1;
        if (blink_counter >= 24'd5000000) begin
            blink_state <= ~blink_state;
            blink_counter <= 0;
        end
        
        // LED控制逻辑
        if (err_flag || current_state == CALC_ERROR) begin
            led[0] <= blink_state;  // 错误闪烁
            led[1] <= 1'b0;
        end else if (calc_busy || conv_busy || current_state == CALC_EXEC || current_state == BONUS_RUN) begin
            led[0] <= 1'b0;
            led[1] <= blink_state;  // 运行闪烁
        end else if (current_state == IDLE) begin
            led[0] <= 1'b0;
            led[1] <= 1'b1;         // 空闲常亮
        end else begin
            led[0] <= 1'b0;
            led[1] <= blink_state;  // 其他状态闪烁
        end
    end
end

endmodule