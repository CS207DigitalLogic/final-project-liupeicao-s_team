`timescale 1ns / 1ps

module tb_uart_rx;

    // Inputs
    reg clk;
    reg rst_n;
    reg rx;

    // Outputs
    wire [7:0] data;
    wire valid;

    // Instantiate the Unit Under Test (UUT)
    uart_rx uut (
        .clk(clk),
        .rst_n(rst_n),
        .rx(rx),
        .data(data),
        .valid(valid)
    );

    // Clock Generation
    always begin
        clk = 1'b0;
        #5 clk = 1'b1; // 100MHz clock (10ns period)
    end

    // Stimulus block
    initial begin
        // Initialize Inputs
        rst_n = 0;
        rx = 1;
        #10;

        // Apply reset
        rst_n = 1;
        #10;

        // Send a byte (e.g., ASCII 'A' = 8'b01000001)
        rx = 0; #10; // Start bit
        rx = 1; #10; // Data bit 0
        rx = 0; #10; // Data bit 1
        rx = 0; #10; // Data bit 2
        rx = 0; #10; // Data bit 3
        rx = 0; #10; // Data bit 4
        rx = 1; #10; // Data bit 5
        rx = 0; #10; // Data bit 6
        rx = 1; #10; // Data bit 7 (stop bit)
        rx = 1; #10; // Stop bit

        // Wait for a while to observe the result
        #100;

        // Finish simulation
        $finish;
    end

endmodule
