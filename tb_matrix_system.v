`timescale 1ns / 1ps

// Define paths for inclusion if your compiler supports it, otherwise compile all files together.
// For this testbench, we assume we will compile all .v files together.

module tb_matrix_system;

    // =================================================================
    // 1. Signals & Constants
    // =================================================================
    reg clk;
    reg rst_n;
    
    // Testbench Control Signals
    integer mode; 
    localparam MODE_TB   = 0;
    localparam MODE_GEN  = 1;
    localparam MODE_CONV = 2;

    // =================================================================
    // 2. Component Instances
    // =================================================================

    // -----------------------
    // Matrix Memory Signals
    // -----------------------
    // Port 1: User/Gen/Conv Interface (Muxed)
    wire [1:0]  mem_u_slot;
    wire [2:0]  mem_u_row;
    wire [2:0]  mem_u_col;
    wire [15:0] mem_u_wdata;
    wire        mem_u_we;
    wire [2:0]  mem_u_dim_m;
    wire [2:0]  mem_u_dim_n;
    wire        mem_u_dim_we;
    wire [15:0] mem_u_rdata;

    // Port 2: ALU Interface (Direct)
    wire [15:0] mem_alu_rdata;
    wire [2:0]  mem_alu_cur_m;
    wire [2:0]  mem_alu_cur_n;
    
    // TB Driver Signals (for Port 1)
    reg [1:0]  tb_slot;
    reg [2:0]  tb_row;
    reg [2:0]  tb_col;
    reg [15:0] tb_data;
    reg        tb_we;
    reg [2:0]  tb_dim_m;
    reg [2:0]  tb_dim_n;
    reg        tb_dim_we;

    matrix_mem u_mem (
        .clk(clk),
        .rst_n(rst_n),
        
        // Port 1 (Muxed)
        .user_slot_idx(mem_u_slot),
        .user_row(mem_u_row),
        .user_col(mem_u_col),
        .user_data(mem_u_wdata),
        .user_we(mem_u_we),
        .user_dim_m(mem_u_dim_m),
        .user_dim_n(mem_u_dim_n),
        .user_dim_we(mem_u_dim_we),
        
        // Port 2 (ALU)
        .alu_rd_slot(alu_rd_slot),
        .alu_rd_row(alu_rd_row),
        .alu_rd_col(alu_rd_col),
        .user_rd_data(mem_u_rdata), // Output from Port 1 read
        .alu_rd_data(mem_alu_rdata),
        .alu_current_m(mem_alu_cur_m),
        .alu_current_n(mem_alu_cur_n),
        
        .alu_wr_slot(alu_wr_slot),
        .alu_wr_row(alu_wr_row),
        .alu_wr_col(alu_wr_col),
        .alu_wr_data(alu_wr_data),
        .alu_wr_we(alu_wr_we),
        .alu_res_m(alu_res_m),
        .alu_res_n(alu_res_n),
        .alu_dim_we(alu_dim_we)
    );

    // -----------------------
    // Matrix Gen Signals
    // -----------------------
    reg        gen_start;
    reg [2:0]  gen_target_m;
    reg [2:0]  gen_target_n;
    reg [1:0]  gen_target_slot;
    wire       gen_done;
    
    wire [1:0]  gen_out_slot;
    wire [2:0]  gen_out_row;
    wire [2:0]  gen_out_col;
    wire [15:0] gen_out_data;
    wire        gen_out_we;
    wire [2:0]  gen_out_dim_m;
    wire [2:0]  gen_out_dim_n;
    wire        gen_out_dim_we;

    matrix_gen u_gen (
        .clk(clk),
        .rst_n(rst_n),
        .start(gen_start),
        .target_m(gen_target_m),
        .target_n(gen_target_n),
        .target_slot(gen_target_slot),
        .done(gen_done),
        
        .gen_slot_idx(gen_out_slot),
        .gen_row(gen_out_row),
        .gen_col(gen_out_col),
        .gen_data(gen_out_data),
        .gen_we(gen_out_we),
        .gen_dim_m(gen_out_dim_m),
        .gen_dim_n(gen_out_dim_n),
        .gen_dim_we(gen_out_dim_we)
    );

    // -----------------------
    // Matrix ALU Signals
    // -----------------------
    reg        alu_start;
    reg [2:0]  alu_opcode;
    reg [15:0] alu_scalar;
    wire       alu_done;
    wire       alu_error;
    
    wire [1:0]  alu_rd_slot;
    wire [2:0]  alu_rd_row;
    wire [2:0]  alu_rd_col;
    // alu_rd_data comes from mem_alu_rdata
    
    wire [1:0]  alu_wr_slot;
    wire [2:0]  alu_wr_row;
    wire [2:0]  alu_wr_col;
    wire [15:0] alu_wr_data;
    wire        alu_wr_we;
    wire [2:0]  alu_res_m;
    wire [2:0]  alu_res_n;
    wire        alu_dim_we;

    matrix_alu u_alu (
        .clk(clk),
        .rst_n(rst_n),
        .start(alu_start),
        .opcode(alu_opcode),
        .scalar_val(alu_scalar),
        .done(alu_done),
        .error(alu_error),
        
        .mem_rd_slot(alu_rd_slot),
        .mem_rd_row(alu_rd_row),
        .mem_rd_col(alu_rd_col),
        .mem_rd_data(mem_alu_rdata),
        .mem_current_m(mem_alu_cur_m),
        .mem_current_n(mem_alu_cur_n),
        
        .mem_wr_slot(alu_wr_slot),
        .mem_wr_row(alu_wr_row),
        .mem_wr_col(alu_wr_col),
        .mem_wr_data(alu_wr_data),
        .mem_wr_we(alu_wr_we),
        .mem_res_m(alu_res_m),
        .mem_res_n(alu_res_n),
        .mem_dim_we(alu_dim_we)
    );

    // -----------------------
    // Bonus Conv Signals
    // -----------------------
    reg        conv_start;
    wire [15:0] conv_res_data;
    wire       conv_res_valid;
    wire       conv_done;
    
    wire [1:0]  conv_rd_slot;
    wire [2:0]  conv_rd_row;
    wire [2:0]  conv_rd_col;
    // conv reads from mem_u_rdata

    bonus_conv u_conv (
        .clk(clk),
        .rst_n(rst_n),
        .start_conv(conv_start),
        
        .mem_rd_slot(conv_rd_slot),
        .mem_rd_row(conv_rd_row),
        .mem_rd_col(conv_rd_col),
        .mem_rd_data(mem_u_rdata), // Shares Port 1 Read
        
        .conv_res_data(conv_res_data),
        .conv_res_valid(conv_res_valid),
        .conv_done(conv_done)
    );

    // =================================================================
    // 3. Multiplexing Logic for Memory Port 1
    // =================================================================
    assign mem_u_slot = (mode == MODE_GEN)  ? gen_out_slot :
                        (mode == MODE_CONV) ? conv_rd_slot : tb_slot;
                        
    assign mem_u_row  = (mode == MODE_GEN)  ? gen_out_row :
                        (mode == MODE_CONV) ? conv_rd_row : tb_row;
                        
    assign mem_u_col  = (mode == MODE_GEN)  ? gen_out_col :
                        (mode == MODE_CONV) ? conv_rd_col : tb_col;
                        
    assign mem_u_wdata = (mode == MODE_GEN) ? gen_out_data : tb_data;
    assign mem_u_we    = (mode == MODE_GEN) ? gen_out_we   : tb_we;
    
    assign mem_u_dim_m = (mode == MODE_GEN) ? gen_out_dim_m : tb_dim_m;
    assign mem_u_dim_n = (mode == MODE_GEN) ? gen_out_dim_n : tb_dim_n;
    assign mem_u_dim_we= (mode == MODE_GEN) ? gen_out_dim_we: tb_dim_we;


    // =================================================================
    // 4. Tasks
    // =================================================================

    // --- Task: Reset ---
    task sys_reset;
    begin
        rst_n = 0;
        gen_start = 0;
        alu_start = 0;
        conv_start = 0;
        mode = MODE_TB;
        tb_we = 0; tb_dim_we = 0;
        #20;
        rst_n = 1;
        #20;
    end
    endtask

    // --- Task: Generate Matrix ---
    task generate_matrix;
        input [1:0] slot;
        input [2:0] m;
        input [2:0] n;
        integer timeout;
    begin
        $display("[TB] Generating Matrix %0d x %0d in Slot %0d...", m, n, slot);
        mode = MODE_GEN;
        gen_target_slot = slot;
        gen_target_m = m;
        gen_target_n = n;
        
        @(posedge clk);
        gen_start <= 1;
        @(posedge clk);
        gen_start <= 0;
        
        // Wait with timeout
        timeout = 0;
        while (!gen_done && timeout < 1000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        
        if (timeout >= 1000) begin
            $display("[TB] ERROR: Timeout waiting for Matrix Gen!");
            $finish;
        end
        
        #10;
        mode = MODE_TB;
        $display("[TB] Generation Done.");
    end
    endtask

    // --- Task: ALU Operation ---
    task run_alu;
        input [2:0] op;
        input [15:0] sc;
        input [1:0] expected_slot_c; // Usually 2
    begin
        $display("[TB] Starting ALU Opcode %b, Scalar %d...", op, sc);
        alu_opcode = op;
        alu_scalar = sc;
        
        @(posedge clk);
        alu_start <= 1;
        @(posedge clk);
        alu_start <= 0;
        
        // Wait for done or error
        fork
            wait(alu_done);
            wait(alu_error);
        join_any
        
        if (alu_error) $display("[TB] ALU reported ERROR!");
        else $display("[TB] ALU Operation Done.");
        
        #10;
    end
    endtask

    // --- Task: Run Convolution ---
    task run_convolution;
        integer timeout;
    begin
        $display("[TB] Starting Bonus Convolution...");
        mode = MODE_CONV; // Switch mux to Conv
        conv_col_cnt = 0; // Reset column counter for printing
        
        @(posedge clk);
        conv_start <= 1;
        @(posedge clk);
        conv_start <= 0;
        
        timeout = 0;
        while (!conv_done && timeout < 2000) begin
             @(posedge clk);
             timeout = timeout + 1;
        end

        if (timeout >= 2000) begin
             $display("[TB] ERROR: Timeout waiting for Convolution!");
             $finish;
        end

        #10;
        mode = MODE_TB;
        $display("[TB] Convolution Done.");
    end
    endtask

    // --- Task: Print Matrix ---
    // Uses TB mode to read from memory
    task print_matrix;
        input [1:0] slot;
        integer r, c;
        reg [2:0] dim_m, dim_n;
    begin
        // 1. Read Dimensions
        // Since we don't have direct access to the 'dims' array in mem (it's internal),
        // we have to rely on knowing them or reading them if they were exposed.
        // Wait, matrix_mem exposes 'alu_current_m' for Port 2.
        // We can snoop Port 2 signals if we set alu_rd_slot.
        // But let's just use the 'alu_current_m' by forcing alu_rd_slot on Port 2? 
        // No, let's keep it simple. We will assume we know the dimensions or 
        // we can cheat and peek into the instance.
        // For a clean TB, let's use the 'alu_rd_slot' (Port 2) to query dimensions
        // while using Port 1 to read data.
        
        // BUT: alu_rd_slot is driven by ALU instance. We can't drive it from TB unless we mux it too.
        // Current TB only muxes Port 1. Port 2 is hardwired to ALU.
        
        // Workaround: Peek internal signals for dimensions
        dim_m = u_mem.dims_m[slot];
        dim_n = u_mem.dims_n[slot];
        
        $display("--- Matrix in Slot %0d (%0d x %0d) ---", slot, dim_m, dim_n);
        
        mode = MODE_TB;
        tb_slot = slot;
        
        for (r = 0; r < dim_m; r = r + 1) begin
            $write("Row %0d: ", r);
            for (c = 0; c < dim_n; c = c + 1) begin
                tb_row = r;
                tb_col = c;
                #1; // Wait for async read
                $write("%6d ", $signed(mem_u_rdata));
            end
            $write("\n");
        end
        $display("-------------------------------------");
    end
    endtask
    
    // --- Task: Write Kernel for Conv ---
    // Conv needs a 3x3 kernel in Slot 0
    task write_kernel;
    begin
        $display("[TB] Writing 3x3 Kernel to Slot 0 for Convolution...");
        mode = MODE_TB;
        tb_slot = 0;
        tb_dim_m = 3;
        tb_dim_n = 3;
        
        @(posedge clk);
        tb_dim_we <= 1;
        @(posedge clk);
        tb_dim_we <= 0;
        
        // Write identity kernel or something simple
        // Row 0: 1 0 0
        write_cell(0, 0, 0, 1); write_cell(0, 0, 1, 0); write_cell(0, 0, 2, 0);
        // Row 1: 0 1 0
        write_cell(0, 1, 0, 0); write_cell(0, 1, 1, 1); write_cell(0, 1, 2, 0);
        // Row 2: 0 0 1
        write_cell(0, 2, 0, 0); write_cell(0, 2, 1, 0); write_cell(0, 2, 2, 1);
        
        $display("[TB] Kernel Written.");
    end
    endtask
    
    task write_cell;
        input [1:0] s;
        input [2:0] r;
        input [2:0] c;
        input [15:0] d;
    begin
        tb_slot = s; tb_row = r; tb_col = c; tb_data = d;
        
        @(posedge clk);
        tb_we <= 1;
        @(posedge clk);
        tb_we <= 0;
    end
    endtask

    // --- Task: Write Linear Matrix ---
    task write_matrix_linear;
        input [1:0] slot;
        input [2:0] m;
        input [2:0] n;
        input [15:0] start_val;
        integer r, c;
        reg [15:0] val;
    begin
        $display("[TB] Writing Linear Matrix to Slot %0d...", slot);
        val = start_val;
        
        // Write Dims
        mode = MODE_TB;
        tb_slot = slot;
        tb_dim_m = m;
        tb_dim_n = n;
        @(posedge clk);
        tb_dim_we <= 1;
        @(posedge clk);
        tb_dim_we <= 0;

        // Write Data
        for (r = 0; r < m; r = r + 1) begin
            for (c = 0; c < n; c = c + 1) begin
                write_cell(slot, r, c, val);
                val = val + 1;
            end
        end
    end
    endtask

    // =================================================================
    // 5. Main Test Sequence
    // =================================================================
    initial begin
        $dumpfile("tb_matrix.vcd");
        $dumpvars(0, tb_matrix_system);
        
        // Clock Generation
        clk = 0;
        
        // 1. Reset
        sys_reset();
        
        // 2. Scenario: Matrix Addition
        $display("\n=== TEST 1: Matrix Addition (A + B -> C) ===");
        generate_matrix(0, 3, 3); // Slot A: 3x3
        generate_matrix(1, 3, 3); // Slot B: 3x3
        
        print_matrix(0);
        print_matrix(1);
        
        run_alu(3'b000, 0, 2); // ADD
        print_matrix(2); // Result in C
        
        // 3. Scenario: Matrix Multiplication
        $display("\n=== TEST 2: Matrix Multiplication (A * B -> C) ===");
        generate_matrix(0, 2, 3); // Slot A: 2x3
        generate_matrix(1, 3, 2); // Slot B: 3x2
        
        print_matrix(0);
        print_matrix(1);
        
        run_alu(3'b010, 0, 2); // MUL
        print_matrix(2); // Result should be 2x2
        
        // 4. Scenario: Scalar Multiplication
        $display("\n=== TEST 3: Scalar Multiplication (A * 2 -> C) ===");
        // Reuse Slot A (2x3)
        run_alu(3'b011, 2, 2); // SCA, scalar=2
        print_matrix(2);
        
        // 5. Scenario: Transpose
        $display("\n=== TEST 4: Transpose (A^T -> C) ===");
        // A is 2x3
        run_alu(3'b100, 0, 2); // TRA
        print_matrix(2); // Should be 3x2
        
        // 6. Scenario: Error Check (Dimension Mismatch)
        $display("\n=== TEST 5: Error Check (Add 2x3 and 3x2) ===");
        // A is 2x3 (Slot 0), B is 3x2 (Slot 1)
        run_alu(3'b000, 0, 2); // ADD
        // Should see Error message
        
        // 7. Scenario: Bonus Convolution (Identity)
        $display("\n=== TEST 6: Bonus Convolution (Identity Kernel) ===");
        // Prepare Kernel in Slot 0
        write_kernel();
        print_matrix(0); // Verify Kernel
        
        run_convolution();
        
        // 8. Scenario: Bonus Convolution (All Ones)
        $display("\n=== TEST 7: Bonus Convolution (All Ones Kernel) ===");
        // Overwrite Slot 0 with All Ones
        // 3x3 Matrix with start value 1, but incrementing...
        // Wait, write_matrix_linear increments.
        // Let's just write manually or use linear with same value?
        // write_matrix_linear increments. I'll just use it and see what happens.
        // Or I can create a loop here to write all 1s.
        
        $display("[TB] Writing All-Ones Kernel...");
        mode = MODE_TB;
        tb_slot = 0;
        tb_dim_m = 3; tb_dim_n = 3;
        @(posedge clk); tb_dim_we <= 1; @(posedge clk); tb_dim_we <= 0;
        
        // Write 1s
        write_cell(0,0,0,1); write_cell(0,0,1,1); write_cell(0,0,2,1);
        write_cell(0,1,0,1); write_cell(0,1,1,1); write_cell(0,1,2,1);
        write_cell(0,2,0,1); write_cell(0,2,1,1); write_cell(0,2,2,1);
        
        print_matrix(0);
        run_convolution();

        // 9. Scenario: Manual Matrix Input & ALU
        $display("\n=== TEST 8: Manual Input ALU Test ===");
        // Write Linear Matrix A (2x2) starting at 1: [1, 2; 3, 4]
        write_matrix_linear(0, 2, 2, 1);
        // Write Linear Matrix B (2x2) starting at 10: [10, 11; 12, 13]
        write_matrix_linear(1, 2, 2, 10);
        
        print_matrix(0);
        print_matrix(1);
        
        run_alu(3'b000, 0, 2); // ADD
        print_matrix(2); // Expect [11, 13; 15, 17]
        
        $display("\nAll Tests Completed.");
        $finish;
    end
    
    always #5 clk = ~clk;
    
    // Monitor Conv Results
    integer conv_col_cnt;
    
    always @(posedge clk) begin
        if (conv_res_valid) begin
            $write("%6d ", $signed(conv_res_data));
            conv_col_cnt = conv_col_cnt + 1;
            if (conv_col_cnt == 10) begin
                $write("\n");
                conv_col_cnt = 0;
            end
        end
    end
    
    // DEBUG: Monitor Gen State
    always @(posedge clk) begin
        if (mode == MODE_GEN) begin
             $display("DEBUG: Gen State: %d, Start: %b, Done: %b, rst_n: %b", u_gen.state, gen_start, gen_done, rst_n);
        end
    end

endmodule
