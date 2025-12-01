`timescale 1ns / 1ps

module tb_bonus_conv;

    reg clk;
    reg rst_n;
    reg start_conv;

    // Wires for Bonus Conv
    wire [15:0] conv_res_data;
    wire        conv_res_valid;
    wire        conv_done;
    wire [1:0]  mem_rd_slot;
    wire [2:0]  mem_rd_row;
    wire [2:0]  mem_rd_col;
    wire [15:0] mem_rd_data;

    // Wires for Matrix Mem
    // We need to drive User Port to load kernel
    reg [1:0]  user_slot_idx;
    reg [2:0]  user_row;
    reg [2:0]  user_col;
    reg [15:0] user_data;
    reg        user_we;
    reg [2:0]  user_dim_m;
    reg [2:0]  user_dim_n;
    reg        user_dim_we;

    // Unused Mem ports
    wire [15:0] user_rd_data;
    wire [15:0] alu_rd_data_unused; // We use this port for bonus_conv read
    wire [2:0]  alu_current_m;
    wire [2:0]  alu_current_n;

    // Instantiate Matrix Mem
    matrix_mem u_mem (
        .clk(clk),
        .rst_n(rst_n),
        // User Port
        .user_slot_idx(user_slot_idx),
        .user_row(user_row),
        .user_col(user_col),
        .user_data(user_data),
        .user_we(user_we),
        .user_dim_m(user_dim_m),
        .user_dim_n(user_dim_n),
        .user_dim_we(user_dim_we),
        .user_rd_data(user_rd_data),
        
        // ALU Port (Connected to Bonus Conv)
        .alu_rd_slot(mem_rd_slot),
        .alu_rd_row(mem_rd_row),
        .alu_rd_col(mem_rd_col),
        .alu_rd_data(mem_rd_data),
        .alu_current_m(alu_current_m),
        .alu_current_n(alu_current_n),
        
        // Write port unused by Bonus Conv (in this test)
        .alu_wr_slot(2'b0),
        .alu_wr_row(3'b0),
        .alu_wr_col(3'b0),
        .alu_wr_data(16'b0),
        .alu_wr_we(1'b0),
        .alu_res_m(3'b0),
        .alu_res_n(3'b0),
        .alu_dim_we(1'b0)
    );

    // Instantiate Bonus Conv
    bonus_conv u_conv (
        .clk(clk),
        .rst_n(rst_n),
        .start_conv(start_conv),
        .mem_rd_slot(mem_rd_slot),
        .mem_rd_row(mem_rd_row),
        .mem_rd_col(mem_rd_col),
        .mem_rd_data(mem_rd_data),
        .conv_res_data(conv_res_data),
        .conv_res_valid(conv_res_valid),
        .conv_done(conv_done)
    );

    // Clock Generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Helper task to write kernel element
    task write_kernel_element;
        input [2:0] r;
        input [2:0] c;
        input [15:0] val;
        begin
            user_slot_idx = 0; // Slot A
            user_row = r;
            user_col = c;
            user_data = val;
            user_we = 1;
            @(posedge clk);
            user_we = 0;
            @(posedge clk); // Wait a bit
        end
    endtask

    // Main Test Process
    integer i, j;
    reg [15:0] kernel_vals [0:2][0:2];

    initial begin
        // Initialize inputs
        rst_n = 0;
        start_conv = 0;
        user_we = 0;
        user_dim_we = 0;
        
        // Define Kernel (Sobel Vertical Edge? or simple)
        // Let's use a simple kernel to verify math:
        // 1 0 1
        // 0 1 0
        // 1 0 1
        kernel_vals[0][0] = 1; kernel_vals[0][1] = 0; kernel_vals[0][2] = 1;
        kernel_vals[1][0] = 0; kernel_vals[1][1] = 1; kernel_vals[1][2] = 0;
        kernel_vals[2][0] = 1; kernel_vals[2][1] = 0; kernel_vals[2][2] = 1;

        #20 rst_n = 1;
        #20;

        $display("Loading Kernel into Matrix Mem Slot A...");
        // Write Dimension
        user_slot_idx = 0;
        user_dim_m = 3;
        user_dim_n = 3;
        user_dim_we = 1;
        @(posedge clk);
        user_dim_we = 0;
        
        // Write Data
        for(i=0; i<3; i=i+1) begin
            for(j=0; j<3; j=j+1) begin
                write_kernel_element(i, j, kernel_vals[i][j]);
            end
        end
        
        $display("Kernel Loaded.");
        #50;
        
        $display("Starting Convolution...");
        start_conv = 1;
        @(posedge clk);
        start_conv = 0;
        
        // Wait for done
        wait(conv_done);
        #100;
        
        $display("Convolution Complete.");
        $finish;
    end

    // Output Monitoring and Printing
    integer out_row_cnt = 0;
    integer out_col_cnt = 0;
    
    // Print header
    initial begin
        wait(conv_res_valid); // Wait for first data
        $display("\n=== Convolution Result Matrix (8x10) ===");
    end

    always @(posedge clk) begin
        if (conv_res_valid) begin
            // Print number with fixed width
            $write("%6d ", $signed(conv_res_data));
            
            out_col_cnt = out_col_cnt + 1;
            if (out_col_cnt == 10) begin
                $write("\n"); // New line after 10 columns
                out_col_cnt = 0;
                out_row_cnt = out_row_cnt + 1;
            end
        end
    end

endmodule
