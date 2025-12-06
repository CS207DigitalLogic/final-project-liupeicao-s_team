`timescale 1ns / 1ps

module uart_tx #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115200
)(
    input  wire clk,
    input  wire rst_n,
    input  wire [7:0] data,    // 要发送的字节
    input  wire start,         // 上升沿/单拍触发
    output reg  tx,            // 串口输出
    output reg  busy           // 发送中
);

    localparam integer BIT_TIME = CLK_FREQ / BAUD_RATE;

    localparam ST_IDLE  = 2'd0;
    localparam ST_START = 2'd1;
    localparam ST_DATA  = 2'd2;
    localparam ST_STOP  = 2'd3;

    reg [1:0] state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  tx_buf;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= ST_IDLE;
            clk_cnt <= 0;
            bit_idx <= 0;
            tx_buf  <= 8'd0;
            tx      <= 1'b1;   // 空闲为高
            busy    <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    tx      <= 1'b1;
                    busy    <= 1'b0;
                    clk_cnt <= 0;
                    bit_idx <= 0;
                    if (start) begin
                        // 缓存数据，开始发送
                        tx_buf  <= data;
                        busy    <= 1'b1;
                        state   <= ST_START;
                    end
                end

                ST_START: begin
                    tx <= 1'b0;  // 起始位
                    if (clk_cnt == BIT_TIME - 1) begin
                        clk_cnt <= 0;
                        state   <= ST_DATA;
                        bit_idx <= 0;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                ST_DATA: begin
                    tx <= tx_buf[bit_idx];
                    if (clk_cnt == BIT_TIME - 1) begin
                        clk_cnt <= 0;
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
                    tx <= 1'b1; // 停止位
                    if (clk_cnt == BIT_TIME - 1) begin
                        clk_cnt <= 0;
                        state   <= ST_IDLE;
                        busy    <= 1'b0;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
