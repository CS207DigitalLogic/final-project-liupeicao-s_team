`timescale 1ns / 1ps

module Timer_Unit(
    input clk,
    input rst_n,
    input start_timer,      // 启动倒计时信号
    output reg [3:0] time_left,  // 剩余时间（0-10）
    output reg timer_done   // 倒计时完成信号
);

// 时钟频率定义（假设100MHz时钟）
parameter CLK_FREQ = 100_000_000;  // 100MHz
parameter TIMER_SECONDS = 10;      // 10秒倒计时

// 计算1秒需要的时钟周期数
localparam ONE_SECOND = CLK_FREQ;

// 内部计数器
reg [31:0] counter;        // 32位计数器，足够计数10秒
reg [3:0] current_time;    // 当前剩余时间

// 状态定义
localparam IDLE = 1'b0;
localparam COUNTING = 1'b1;
reg state;

// 倒计时逻辑
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 复位初始化
        state <= IDLE;
        counter <= 32'b0;
        current_time <= 4'd10;  // 从10开始倒计时
        time_left <= 4'd10;
        timer_done <= 1'b0;
    end else begin
        case (state)
            IDLE: begin
                // 空闲状态
                timer_done <= 1'b0;
                if (start_timer) begin
                    // 启动倒计时
                    state <= COUNTING;
                    counter <= 32'b0;
                    current_time <= 4'd10;
                    time_left <= 4'd10;
                end else begin
                    // 保持初始值
                    current_time <= 4'd10;
                    time_left <= 4'd10;
                end
            end
            
            COUNTING: begin
                // 倒计时进行中
                timer_done <= 1'b0;
                
                if (!start_timer) begin
                    // 如果start_timer提前结束，回到空闲状态
                    state <= IDLE;
                    current_time <= 4'd10;
                    time_left <= 4'd10;
                end else begin
                    // 更新计数器
                    counter <= counter + 1;
                    
                    // 每秒更新一次时间
                    if (counter >= ONE_SECOND - 1) begin
                        counter <= 32'b0;
                        
                        if (current_time > 0) begin
                            current_time <= current_time - 1;
                            time_left <= current_time - 1;
                        end
                        
                        // 检查是否倒计时结束
                        if (current_time == 1) begin
                            // 倒计时完成
                            state <= IDLE;
                            timer_done <= 1'b1;
                            current_time <= 4'd10;
                            time_left <= 4'd0;
                        end
                    end else begin
                        // 保持当前时间显示
                        time_left <= current_time;
                    end
                end
            end
            
            default: begin
                state <= IDLE;
                current_time <= 4'd10;
                time_left <= 4'd10;
                timer_done <= 1'b0;
            end
        endcase
    end
end

endmodule