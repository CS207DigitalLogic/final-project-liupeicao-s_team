module cmd_parser (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] rx_data,      // UART �յ���һ���ֽڣ�ASCII��
    input  wire       rx_valid,     // ��Ӧ data ��Ч����
    output reg [15:0] number_out,   // ��� 0-999
    output reg        number_valid  // ���ģ����� number_out
);

    reg [15:0] number_buffer; // �����ۻ�����
    reg        parsing_in_progress; // ��־�Ƿ����ڽ�������

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
                default: ascii_to_digit = 4'hF; // ��Ч
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            number_out          <= 16'd0;
            number_valid        <= 1'b0;
            number_buffer       <= 16'd0;
            parsing_in_progress <= 1'b0; // ��λ״̬
        end else begin
            number_valid <= 1'b0; // Ĭ������

            if (rx_valid) begin
                if (ascii_to_digit(rx_data) != 4'hF) begin // �յ����������ַ�
                    // �ۼ�����
                    number_buffer <= (number_buffer * 10) + ascii_to_digit(rx_data);
                    parsing_in_progress <= 1'b1; // ������ڽ�������
                end else if ( (rx_data == 8'h0D || rx_data == 8'h20 || rx_data == 8'h0A) && parsing_in_progress ) begin // �յ��ָ��� (�س������л�ո�) ��֮ǰ���������ۻ�
                    // ���ۻ����������
                    number_out          <= number_buffer;
                    number_valid        <= 1'b1; // ���������Ч
                    
                    // ��λΪ��һ�ν�����׼��
                    number_buffer       <= 16'd0;
                    parsing_in_progress <= 1'b0;
                end else begin // �յ������������ַ���������û���ۻ�����ʱ�յ��ָ���
                    // ���״̬����ֹ�����ۻ�
                    number_buffer       <= 16'd0;
                    parsing_in_progress <= 1'b0;
                end
            end
        end
    end

endmodule
