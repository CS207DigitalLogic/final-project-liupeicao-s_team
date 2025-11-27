`timescale 1ns / 1ps

module tb_matrix_alu;

    // ============================================================
    // 1. 信号定义
    // ============================================================
    reg clk;
    reg rst_n;

    // --- User Interface (用于写入测试数据) ---
    reg [1:0]  user_slot_idx;
    reg [2:0]  user_row, user_col;
    reg [15:0] user_data;
    reg        user_we;
    reg [2:0]  user_dim_m, user_dim_n;
    reg        user_dim_we;

    // --- ALU Control Interface ---
    reg        start;
    reg [2:0]  opcode;
    reg [15:0] scalar_val;
    wire       done;
    wire       error;

    // --- Memory <-> ALU 互联信号 ---
    // ALU 输出的读地址信号
    wire [1:0]  alu_rd_slot_out;
    wire [2:0]  alu_rd_row_out, alu_rd_col_out;
    
    // ALU 输出的写信号
    wire [1:0]  alu_wr_slot_out;
    wire [2:0]  alu_wr_row_out, alu_wr_col_out;
    wire [15:0] alu_wr_data_out;
    wire        alu_wr_we_out;
    wire [2:0]  alu_res_m_out, alu_res_n_out;
    wire        alu_dim_we_out;

    // Mem 输出给 ALU 的数据
    wire [15:0] mem_rd_data_out;
    wire [2:0]  mem_current_m_out, mem_current_n_out;

    // --- TB Monitor Interface (用于 TB 读取打印矩阵) ---
    reg        tb_monitor_mode; // 1: TB 控制读端口, 0: ALU 控制
    reg [1:0]  tb_rd_slot;
    reg [2:0]  tb_rd_row, tb_rd_col;

    // ============================================================
    // 2. 读端口复用器 (Multiplexer)
    //    决定谁来控制 Memory 的读地址端口 (TB 还是 ALU)
    // ============================================================
    wire [1:0] mux_rd_slot = tb_monitor_mode ? tb_rd_slot : alu_rd_slot_out;
    wire [2:0] mux_rd_row  = tb_monitor_mode ? tb_rd_row  : alu_rd_row_out;
    wire [2:0] mux_rd_col  = tb_monitor_mode ? tb_rd_col  : alu_rd_col_out;

    // ============================================================
    // 3. 模块实例化
    // ============================================================
    
    // 实例化存储器
    matrix_mem u_mem (
        .clk(clk), .rst_n(rst_n),
        // User Port (Write Only)
        .user_slot_idx(user_slot_idx), .user_row(user_row), .user_col(user_col),
        .user_data(user_data), .user_we(user_we),
        .user_dim_m(user_dim_m), .user_dim_n(user_dim_n), .user_dim_we(user_dim_we),
        
        // Read Port (Muxed)
        .alu_rd_slot(mux_rd_slot), .alu_rd_row(mux_rd_row), .alu_rd_col(mux_rd_col),
        .alu_rd_data(mem_rd_data_out),
        .alu_current_m(mem_current_m_out), .alu_current_n(mem_current_n_out),
        
        // Write Port (Driven by ALU)
        .alu_wr_slot(alu_wr_slot_out), .alu_wr_row(alu_wr_row_out), .alu_wr_col(alu_wr_col_out),
        .alu_wr_data(alu_wr_data_out), .alu_wr_we(alu_wr_we_out),
        .alu_res_m(alu_res_m_out), .alu_res_n(alu_res_n_out), .alu_dim_we(alu_dim_we_out)
    );

    // 实例化 ALU
    matrix_alu u_alu (
        .clk(clk), .rst_n(rst_n),
        .start(start), .opcode(opcode), .scalar_val(scalar_val),
        .done(done), .error(error),
        
        // Read Request
        .mem_rd_slot(alu_rd_slot_out), .mem_rd_row(alu_rd_row_out), .mem_rd_col(alu_rd_col_out),
        .mem_rd_data(mem_rd_data_out),
        .mem_current_m(mem_current_m_out), .mem_current_n(mem_current_n_out),
        
        // Write Request
        .mem_wr_slot(alu_wr_slot_out), .mem_wr_row(alu_wr_row_out), .mem_wr_col(alu_wr_col_out),
        .mem_wr_data(alu_wr_data_out), .mem_wr_we(alu_wr_we_out),
        .mem_res_m(alu_res_m_out), .mem_res_n(alu_res_n_out), .mem_dim_we(alu_dim_we_out)
    );

    // ============================================================
    // 4. 辅助任务 (Helper Tasks)
    // ============================================================
    
    // 任务: 写入一个矩阵
    // 参数: slot (0/1), m, n, start_val(起始值), incr(增量, 0为全同)
    task write_matrix;
        input [1:0] t_slot;
        input [2:0] t_m, t_n;
        input [15:0] t_val;
        input [15:0] t_incr;
        integer r, c;
        reg [15:0] curr_val;
        begin
            curr_val = t_val;
            // 1. 写维度
            @(negedge clk);
            user_slot_idx = t_slot;
            user_dim_m = t_m; user_dim_n = t_n; user_dim_we = 1;
            @(negedge clk);
            user_dim_we = 0;
            
            // 2. 写数据
            for (r = 0; r < t_m; r = r + 1) begin
                for (c = 0; c < t_n; c = c + 1) begin
                    user_row = r; user_col = c;
                    user_data = curr_val;
                    user_we = 1;
                    @(negedge clk);
                    curr_val = curr_val + t_incr;
                end
            end
            user_we = 0;
            $display("[TB] Wrote Matrix Slot %0d (%0dx%0d)", t_slot, t_m, t_n);
        end
    endtask

    // 任务: 打印矩阵内容到控制台
    task print_matrix;
        input [1:0] t_slot;
        input [8*10:1] t_name; // 字符串名字
        integer r, c;
        reg [2:0] max_m, max_n;
        begin
            tb_monitor_mode = 1; // 夺取总线控制权
            tb_rd_slot = t_slot;
            #1; // 等待组合逻辑读取维度
            max_m = mem_current_m_out;
            max_n = mem_current_n_out;
            
            $display("--------------------------------------------------");
            $display(" Matrix %s (Slot %0d, Size %0dx%0d):", t_name, t_slot, max_m, max_n);
            
            for (r = 0; r < max_m; r = r + 1) begin
                $write(" |");
                for (c = 0; c < max_n; c = c + 1) begin
                    tb_rd_row = r; tb_rd_col = c;
                    #1; // 等待数据
                    $write("%5d", $signed(mem_rd_data_out)); // 打印有符号数
                end
                $write(" |\n");
            end
            $display("--------------------------------------------------");
            tb_monitor_mode = 0; // 释放总线
        end
    endtask

    // ============================================================
    // 5. 测试流程 (Test Sequence)
    // ============================================================
    
    // 时钟生成
    always #5 clk = ~clk;

    initial begin
        // 初始化
        clk = 0; rst_n = 0;
        start = 0; opcode = 0; scalar_val = 0;
        user_we = 0; user_dim_we = 0;
        tb_monitor_mode = 0;
        
        #20 rst_n = 1;
        $display("\n=== FPGA Matrix ALU Testbench Started ===\n");

        // ------------------------------------------------------------
        // Test Case 1: 矩阵加法 (Matrix Addition)
        // A(3x3) + B(3x3)
        // ------------------------------------------------------------
        $display(">>> TEST CASE 1: Matrix Addition (3x3) <<<");
        // A = 1, 2, 3...
        write_matrix(0, 3, 3, 1, 1); 
        // B = 10, 10, 10...
        write_matrix(1, 3, 3, 10, 0);
        
        print_matrix(0, "A (Input)");
        print_matrix(1, "B (Input)");

        @(negedge clk);
        opcode = 3'b000; // ADD
        start = 1;
        @(negedge clk);
        start = 0;

        wait(done);
        #20;
        print_matrix(2, "C (Result A+B)");


        // ------------------------------------------------------------
        // Test Case 2: 矩阵减法 (Matrix Subtraction)
        // A(3x3) - B(3x3) = (1-10), (2-10)...
        // ------------------------------------------------------------
        $display("\n>>> TEST CASE 2: Matrix Subtraction (3x3) <<<");
        @(negedge clk);
        opcode = 3'b001; // SUB
        start = 1;
        @(negedge clk);
        start = 0;

        wait(done);
        #20;
        print_matrix(2, "C (Result A-B)");


        // ------------------------------------------------------------
        // Test Case 3: 标量乘法 (Scalar Multiplication)
        // A(3x3) * 3
        // ------------------------------------------------------------
        $display("\n>>> TEST CASE 3: Scalar Multiplication (A * 3) <<<");
        @(negedge clk);
        opcode = 3'b011; // SCALAR
        scalar_val = 3;
        start = 1;
        @(negedge clk);
        start = 0;

        wait(done);
        #20;
        print_matrix(2, "C (Result A*3)");


        // ------------------------------------------------------------
        // Test Case 4: 矩阵转置 (Transpose)
        // Input A (2x4) -> Output C (4x2)
        // ------------------------------------------------------------
        $display("\n>>> TEST CASE 4: Matrix Transpose (2x4 -> 4x2) <<<");
        // 重写 A 为 2x4 矩阵
        // 1 2 3 4
        // 5 6 7 8
        write_matrix(0, 2, 4, 1, 1);
        print_matrix(0, "A (Input)");

        @(negedge clk);
        opcode = 3'b100; // TRA
        start = 1;
        @(negedge clk);
        start = 0;

        wait(done);
        #20;
        print_matrix(2, "C (Result A^T)");


        // ------------------------------------------------------------
        // Test Case 5: 矩阵乘法 (Matrix Multiplication)
        // A(2x3) * B(3x2) -> C(2x2)
        // ------------------------------------------------------------
        $display("\n>>> TEST CASE 5: Matrix Multiplication (2x3 * 3x2) <<<");
        // A = 2x3
        // [1 2 3]
        // [4 5 6]
        write_matrix(0, 2, 3, 1, 1);
        
        // B = 3x2
        // [1 4]
        // [2 5]
        // [3 6]
        write_matrix(1, 3, 2, 1, 1); // 这里的初始化逻辑稍微简单了点，手动覆盖一下让它好算点
        
        // 为了验证准确性，我们手动写 B 让它简单点: 单位矩阵变体
        // B = 
        // [1 0]
        // [0 1]
        // [1 1]
        // 手动写B:
        @(negedge clk);
        user_slot_idx = 1; user_dim_m = 3; user_dim_n = 2; user_dim_we = 1; @(negedge clk); user_dim_we = 0;
        user_row=0; user_col=0; user_data=1; user_we=1; @(negedge clk);
        user_row=0; user_col=1; user_data=0; @(negedge clk);
        user_row=1; user_col=0; user_data=0; @(negedge clk);
        user_row=1; user_col=1; user_data=1; @(negedge clk);
        user_row=2; user_col=0; user_data=1; @(negedge clk);
        user_row=2; user_col=1; user_data=1; @(negedge clk);
        user_we = 0;

        print_matrix(0, "A (2x3)");
        print_matrix(1, "B (3x2)");

        // 预期结果:
        // C[0][0] = 1*1 + 2*0 + 3*1 = 4
        // C[0][1] = 1*0 + 2*1 + 3*1 = 5
        // C[1][0] = 4*1 + 5*0 + 6*1 = 10
        // C[1][1] = 4*0 + 5*1 + 6*1 = 11

        @(negedge clk);
        opcode = 3'b010; // MUL
        start = 1;
        @(negedge clk);
        start = 0;

        wait(done);
        #20;
        print_matrix(2, "C (Result A*B)");


        // ------------------------------------------------------------
        // Test Case 6: 错误检测 (Dimension Mismatch Error)
        // Try Adding A(2x3) + B(3x2) -> Should Error
        // ------------------------------------------------------------
        $display("\n>>> TEST CASE 6: Error Handling (Mismatch Dim) <<<");
        $display("Attempting to ADD A(2x3) and B(3x2)...");

        @(negedge clk);
        opcode = 3'b000; // ADD
        start = 1;
        @(negedge clk);
        start = 0;

        // 等待几个周期检查 error
        #50;
        if (error) 
            $display("[PASS] Error Flag Asserted correctly!");
        else 
            $display("[FAIL] Error Flag NOT asserted!");

        
        $display("\n=== All Tests Completed ===");
        $stop;
    end

endmodule