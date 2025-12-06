`timescale 1ns / 1ps

module Timer_Unit(
    input clk,
    input rst_n,
    input start_timer,      
    input [3:0] config_time, // 动态可配置时间 (5-15s)
    output reg [3:0] time_left,  
    output reg timer_done   
);

// 100MHz
parameter CLK_FREQ = 100_000_000;  

localparam ONE_SECOND = CLK_FREQ;

reg [31:0] counter;        
reg [3:0] current_time;    

// 状态
localparam IDLE = 1'b0;
localparam COUNTING = 1'b1;
reg state;

// 有效配置时间逻辑 (限制在5-15s)
wire [3:0] target_time;
assign target_time = (config_time >= 5 && config_time <= 15) ? config_time : 4'd10;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IDLE;
        counter <= 32'b0;
        current_time <= 4'd10;  
        time_left <= 4'd10;
        timer_done <= 1'b0;
    end else begin
        case (state)
            IDLE: begin
                timer_done <= 1'b0;
                if (start_timer) begin
                    state <= COUNTING;
                    counter <= 32'b0;
                    current_time <= target_time;
                    time_left <= target_time;
                end else begin
                    current_time <= target_time;
                    time_left <= target_time;
                end
            end
            
            COUNTING: begin
                timer_done <= 1'b0;
                
                if (!start_timer) begin
                    state <= IDLE;
                    current_time <= target_time;
                    time_left <= target_time;
                end else begin
                    counter <= counter + 1;
                    
                    if (counter >= ONE_SECOND - 1) begin
                        counter <= 32'b0;
                        
                        if (current_time > 0) begin
                            current_time <= current_time - 1;
                            time_left <= current_time - 1;
                        end
                        
                        if (current_time == 1) begin
                            state <= IDLE;
                            timer_done <= 1'b1;
                            current_time <= target_time;
                            time_left <= 4'd0;
                        end
                    end else begin
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
