`timescale 1ns / 1ps

module tb_output_formatter;

    // Inputs
    reg [7:0] matrix_data;

    // Outputs
    wire [7:0] formatted_data;
    wire new_line;

    // Instantiate the Unit Under Test (UUT)
    output_formatter uut (
        .matrix_data(matrix_data),
        .formatted_data(formatted_data),
        .new_line(new_line)
    );

    // Stimulus block
    initial begin
        // Send matrix data (e.g., ASCII for numbers and newline)
        matrix_data = 8'd49; // '1'
        #10;
        matrix_data = 8'd50; // '2'
        #10;
        matrix_data = 8'd51; // '3'
        #10;
        matrix_data = 8'd10; // Newline (ASCII LF)
        #10;
        matrix_data = 8'd52; // '4'
        #10;

        // Check formatted data and new_line output
        // The expected output should show formatted data, and new_line should go high when ASCII LF (10) is encountered.

        // Finish simulation
        $finish;
    end

endmodule
