`timescale 1ns / 1ps

module Timer_Unit(
    input clk,
    input rst_n,
    input start_timer,      // ��������ʱ�ź�
    output reg [3:0] time_left,  // ʣ��ʱ�䣨0-10��
    output reg timer_done   // ����ʱ����ź�
);

// ʱ��Ƶ�ʶ��壨����100MHzʱ�ӣ�
parameter CLK_FREQ = 100_000_000;  // 100MHz
parameter TIMER_SECONDS = 10;      // 10�뵹��ʱ

// ����1����Ҫ��ʱ��������
localparam ONE_SECOND = CLK_FREQ;

// �ڲ�������
reg [31:0] counter;        // 32λ���������㹻����10��
reg [3:0] current_time;    // ��ǰʣ��ʱ��

// ״̬����
localparam IDLE = 1'b0;
localparam COUNTING = 1'b1;
reg state;

// ����ʱ�߼�
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // ��λ��ʼ��
        state <= IDLE;
        counter <= 32'b0;
        current_time <= 4'd10;  // ��10��ʼ����ʱ
        time_left <= 4'd10;
        timer_done <= 1'b0;
    end else begin
        case (state)
            IDLE: begin
                // ����״̬
                timer_done <= 1'b0;
                if (start_timer) begin
                    // ��������ʱ
                    state <= COUNTING;
                    counter <= 32'b0;
                    current_time <= 4'd10;
                    time_left <= 4'd10;
                end else begin
                    // ���ֳ�ʼֵ
                    current_time <= 4'd10;
                    time_left <= 4'd10;
                end
            end
            
            COUNTING: begin
                // ����ʱ������
                timer_done <= 1'b0;
                
                if (!start_timer) begin
                    // ���start_timer��ǰ�������ص�����״̬
                    state <= IDLE;
                    current_time <= 4'd10;
                    time_left <= 4'd10;
                end else begin
                    // ���¼�����
                    counter <= counter + 1;
                    
                    // ÿ�����һ��ʱ��
                    if (counter >= ONE_SECOND - 1) begin
                        counter <= 32'b0;
                        
                        if (current_time > 0) begin
                            current_time <= current_time - 1;
                            time_left <= current_time - 1;
                        end
                        
                        // ����Ƿ񵹼�ʱ����
                        if (current_time == 1) begin
                            // ����ʱ���
                            state <= IDLE;
                            timer_done <= 1'b1;
                            current_time <= 4'd10;
                            time_left <= 4'd0;
                        end
                    end else begin
                        // ���ֵ�ǰʱ����ʾ
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