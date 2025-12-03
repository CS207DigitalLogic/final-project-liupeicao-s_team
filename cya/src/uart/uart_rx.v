`timescale 1ns / 1ps

module uart_rx #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115200
)(
    input  wire clk,
    input  wire rst_n,
    input  wire rx,          // 串口输入
    output reg  [7:0] data,  // 接收到的 1 字节数据
    output reg        valid  // 单拍脉冲，有新数据
);

    localparam integer BIT_TIME = CLK_FREQ / BAUD_RATE;

    localparam ST_IDLE  = 2'd0;
    localparam ST_START = 2'd1;
    localparam ST_DATA  = 2'd2;
    localparam ST_STOP  = 2'd3;

    reg [1:0] state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  rx_shift;
    
    // Synchronizer for RX
    reg rx_sync1, rx_sync2;
    wire rx_stable = rx_sync2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync1 <= 1'b1;
            rx_sync2 <= 1'b1;
        end else begin
            rx_sync1 <= rx;
            rx_sync2 <= rx_sync1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= ST_IDLE;
            clk_cnt  <= 16'd0;
            bit_idx  <= 3'd0;
            rx_shift <= 8'd0;
            data     <= 8'd0;
            valid    <= 1'b0;
        end else begin
            valid <= 1'b0; // 默认无新数据

            case (state)
                ST_IDLE: begin
                    clk_cnt <= 0;
                    bit_idx <= 0;
                    if (rx_stable == 1'b0) begin
                        // 检测到起始位下降
                        state   <= ST_START;
                        clk_cnt <= 0;
                    end
                end

                ST_START: begin
                    if (clk_cnt == (BIT_TIME/2)) begin
                        // 在起始位中间再确认一次
                        if (rx_stable == 1'b0) begin
                            clk_cnt <= 0;
                            bit_idx <= 0;
                            state   <= ST_DATA;
                        end else begin
                            // 误触发
                            state <= ST_IDLE;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                ST_DATA: begin
                    if (clk_cnt == BIT_TIME - 1) begin
                        clk_cnt      <= 0;
                        rx_shift[bit_idx] <= rx_stable; // LSB 先行
                        if (bit_idx == 3'd7) begin
                            bit_idx <= 0;
                            state   <= ST_STOP;
                        end else begin
                            bit_idx <= bit_idx + 1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                ST_STOP: begin
                    if (clk_cnt == BIT_TIME - 1) begin
                        clk_cnt <= 0;
                        // 简单认为 stop 位正确
                        data    <= rx_shift;
                        valid   <= 1'b1;
                        state   <= ST_IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
