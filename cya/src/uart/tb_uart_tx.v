`timescale 1ns / 1ps

module tb_uart_tx;

    // Inputs
    reg clk;
    reg rst_n;
    reg [7:0] data;
    reg start;

    // Outputs
    wire tx;
    wire busy;

    // Instantiate the Unit Under Test (UUT)
    uart_tx uut (
        .clk(clk),
        .rst_n(rst_n),
        .data(data),
        .start(start),
        .tx(tx),
        .busy(busy)
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
        data = 8'b0;
        start = 0;
        #10;

        // Apply reset
        rst_n = 1;
        #10;

        // Start sending a byte (e.g., ASCII 'A' = 8'b01000001)
        data = 8'b01000001; // 'A'
        start = 1;
        #10;
        start = 0;

        // Wait for transmission to complete
        #100;

        // Finish simulation
        $finish;
    end

endmodule
