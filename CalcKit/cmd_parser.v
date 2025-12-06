module cmd_parser (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] rx_data,      // UART 收到的一个字节（ASCII）
    input  wire       rx_valid,     // 对应 data 有效单拍
    output reg [15:0] number_out,   // 输出 0-999
    output reg        number_valid  // 单拍，有新 number_out
);

    reg [15:0] number_buffer; // 用于累积数字
    reg        parsing_in_progress; // 标志是否正在解析数字

    function [3:0] ascii_to_digit;
        input [7:0] ascii_char;
        begin
            case (ascii_char)
                8'h30: ascii_to_digit = 4'd0;
                8'h31: ascii_to_digit = 4'd1;
                8'h32: ascii_to_digit = 4'd2;
                8'h33: ascii_to_digit = 4'd3;
                8'h34: ascii_to_digit = 4'd4;
                8'h35: ascii_to_digit = 4'd5;
                8'h36: ascii_to_digit = 4'd6;
                8'h37: ascii_to_digit = 4'd7;
                8'h38: ascii_to_digit = 4'd8;
                8'h39: ascii_to_digit = 4'd9;
                default: ascii_to_digit = 4'hF; // 无效
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            number_out          <= 16'd0;
            number_valid        <= 1'b0;
            number_buffer       <= 16'd0;
            parsing_in_progress <= 1'b0; // 复位状态
        end else begin
            number_valid <= 1'b0; // 默认拉低

            if (rx_valid) begin
                if (ascii_to_digit(rx_data) != 4'hF) begin // 收到的是数字字符
                    // 累加数字
                    number_buffer <= (number_buffer * 10) + ascii_to_digit(rx_data);
                    parsing_in_progress <= 1'b1; // 标记正在解析数字
                end else if ( (rx_data == 8'h0D || rx_data == 8'h20) && parsing_in_progress ) begin // 收到分隔符 (回车或空格) 且之前有数字在累积
                    // 将累积的数字输出
                    number_out          <= number_buffer;
                    number_valid        <= 1'b1; // 标记数字有效
                    
                    // 复位为下一次解析做准备
                    number_buffer       <= 16'd0;
                    parsing_in_progress <= 1'b0;
                end else begin // 收到其他非数字字符，或者在没有累积数字时收到分隔符
                    // 清除状态，防止错误累积
                    number_buffer       <= 16'd0;
                    parsing_in_progress <= 1'b0;
                end
            end
        end
    end

endmodule
