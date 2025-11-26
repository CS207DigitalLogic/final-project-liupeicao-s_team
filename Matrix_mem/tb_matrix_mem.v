`timescale 1ns / 1ps

module tb_matrix_mem;

    // Inputs
    reg clk;
    reg rst_n;
    reg [1:0]  user_slot_idx;
    reg [2:0]  user_row, user_col;
    reg [15:0] user_data;
    reg        user_we;
    reg [2:0]  user_dim_m, user_dim_n;
    reg        user_dim_we;

    reg [1:0]  alu_rd_slot;
    reg [2:0]  alu_rd_row, alu_rd_col;
    reg [1:0]  alu_wr_slot;
    reg [2:0]  alu_wr_row, alu_wr_col;
    reg [15:0] alu_wr_data;
    reg        alu_wr_we;
    reg [2:0]  alu_res_m, alu_res_n;
    reg        alu_dim_we;

    // Outputs
    wire [15:0] alu_rd_data;
    wire [2:0]  alu_current_m, alu_current_n;

    // UUT Instantiate
    matrix_mem uut (
        .clk(clk), .rst_n(rst_n),
        .user_slot_idx(user_slot_idx), .user_row(user_row), .user_col(user_col), 
        .user_data(user_data), .user_we(user_we), 
        .user_dim_m(user_dim_m), .user_dim_n(user_dim_n), .user_dim_we(user_dim_we),
        .alu_rd_slot(alu_rd_slot), .alu_rd_row(alu_rd_row), .alu_rd_col(alu_rd_col), 
        .alu_rd_data(alu_rd_data), .alu_current_m(alu_current_m), .alu_current_n(alu_current_n),
        .alu_wr_slot(alu_wr_slot), .alu_wr_row(alu_wr_row), .alu_wr_col(alu_wr_col), 
        .alu_wr_data(alu_wr_data), .alu_wr_we(alu_wr_we),
        .alu_res_m(alu_res_m), .alu_res_n(alu_res_n), .alu_dim_we(alu_dim_we)
    );

    // Clock
    always #5 clk = ~clk;

    initial begin
        clk = 0; rst_n = 0;
        user_we = 0; user_dim_we = 0; alu_wr_we = 0; alu_dim_we = 0;
        user_slot_idx = 0; user_row = 0; user_col = 0; user_data = 0;
        alu_rd_slot = 0; alu_rd_row = 0; alu_rd_col = 0;

        #20 rst_n = 1;

        // ==========================================
        // BUG FIX Strategy: 
        // 在 negedge clk 更新数据，确保 posedge 时数据稳定
        // ==========================================

        $display("=== Simulation Start (Fixed) ===");

        // Test 1: Write A (2x2)
        @(negedge clk);
        user_slot_idx = 0; 
        user_dim_m = 2; user_dim_n = 2; user_dim_we = 1;
        @(negedge clk);
        user_dim_we = 0;
        
        // Write (0,0)=1
        user_row = 0; user_col = 0; user_data = 16'd1; user_we = 1;
        @(negedge clk);
        // Write (0,1)=2
        user_row = 0; user_col = 1; user_data = 16'd2;
        @(negedge clk);
        // Write (1,0)=3
        user_row = 1; user_col = 0; user_data = 16'd3;
        @(negedge clk);
        // Write (1,1)=4
        user_row = 1; user_col = 1; user_data = 16'd4;
        @(negedge clk);
        user_we = 0;

        // Test 2: Read Check
        #20;
        alu_rd_slot = 0;
        
        // Check (0,1)
        alu_rd_row = 0; alu_rd_col = 1;
        #1; 
        if (alu_rd_data === 16'd2) $display("PASS: Read (0,1) = 2");
        else $display("FAIL: Read (0,1) = %d (Expected 2)", alu_rd_data);

        // Check (1,0)
        alu_rd_row = 1; alu_rd_col = 0;
        #1;
        if (alu_rd_data === 16'd3) $display("PASS: Read (1,0) = 3");
        else $display("FAIL: Read (1,0) = %d (Expected 3)", alu_rd_data);

        // Test 3: ALU Write C
        @(negedge clk);
        alu_wr_slot = 2;
        alu_res_m = 2; alu_res_n = 2; alu_dim_we = 1;
        @(negedge clk);
        alu_dim_we = 0;
        
        // Write C(0,1) = 99
        alu_wr_row = 0; alu_wr_col = 1; alu_wr_data = 16'd99; alu_wr_we = 1;
        @(negedge clk);
        alu_wr_we = 0;

        // Test 4: Verify C
        #20;
        alu_rd_slot = 2; alu_rd_row = 0; alu_rd_col = 1;
        #1;
        if (alu_rd_data === 16'd99) $display("PASS: Read C(0,1) = 99");
        else $display("FAIL: Read C(0,1) = %d (Expected 99)", alu_rd_data);

        $display("=== Simulation End ===");
        $stop;
    end
endmodule