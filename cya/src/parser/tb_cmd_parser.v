`timescale 1ns / 1ps

module tb_cmd_parser;

    // Inputs
    reg clk;
    reg rst_n;
    reg [7:0] rx_data;
    reg rx_valid;

    // Outputs
    wire [15:0] number_out;
    wire number_valid;

    // Instantiate the Unit Under Test (UUT)
    cmd_parser uut (
        .clk(clk),
        .rst_n(rst_n),
        .rx_data(rx_data),
        .rx_valid(rx_valid),
        .number_out(number_out),
        .number_valid(number_valid)
    );

    // Clock Generation
    always begin
        clk = 1'b0;
        #5 clk = 1'b1;
        #5;
    end

    // Monitor number_valid signal
    always @(posedge number_valid) begin
        $display(">>> NUMBER_VALID TRIGGERED: number_out = %d", number_out);
    end

    // Stimulus block
    initial begin
        // Initialize
        rst_n = 0;
        rx_data = 8'b0;
        rx_valid = 0;
        #20;
        
        // Release reset
        rst_n = 1;
        #10;

        // Test case 1: "123"
        $display("\n=== Test 1: '123' ===");
        
        // 第一个字符 '1'
        rx_data = 8'h31;  // '1'
        rx_valid = 1;
        #10;
        rx_valid = 0;
        #20;
        
        // 第二个字符 '2'
        rx_data = 8'h32;  // '2'
        rx_valid = 1;
        #10;
        rx_valid = 0;
        #20;
        
        // 第三个字符 '3'
        rx_data = 8'h33;  // '3'
        rx_valid = 1;
        #10;
        rx_valid = 0;
        #30;  // 等待更长时间以捕获number_valid
        
        $display("Final check: number_out=%d, number_valid=%b", number_out, number_valid);

        // Test case 2: "456"
        #30;
        $display("\n=== Test 2: '456' ===");
        
        // 第一个字符 '4'
        rx_data = 8'h34;  // '4'
        rx_valid = 1;
        #10;
        rx_valid = 0;
        #20;
        
        // 第二个字符 '5'
        rx_data = 8'h35;  // '5'
        rx_valid = 1;
        #10;
        rx_valid = 0;
        #20;
        
        // 第三个字符 '6'
        rx_data = 8'h36;  // '6'
        rx_valid = 1;
        #10;
        rx_valid = 0;
        #30;  // 等待更长时间以捕获number_valid
        
        $display("Final check: number_out=%d, number_valid=%b", number_out, number_valid);

        // Test invalid character
        #30;
        $display("\n=== Test 3: Invalid 'A' ===");
        rx_data = 8'h41;  // 'A'
        rx_valid = 1;
        #10;
        rx_valid = 0;
        #20;
        
        $display("Result: Expected=No output, Got=%d, Valid=%b", number_out, number_valid);

        $finish;
    end
endmodule
