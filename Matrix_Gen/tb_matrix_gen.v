`timescale 1ns / 1ps

module tb_matrix_gen;

    reg clk;
    reg rst_n;
    reg start;
    reg [2:0] target_m;
    reg [2:0] target_n;
    reg [1:0] target_slot;
    wire done;

    // Generator Outputs
    wire [1:0]  gen_slot_idx;
    wire [2:0]  gen_row;
    wire [2:0]  gen_col;
    wire [15:0] gen_data;
    wire        gen_we;
    wire [2:0]  gen_dim_m;
    wire [2:0]  gen_dim_n;
    wire        gen_dim_we;

    // Mem Outputs
    wire [15:0] user_rd_data;
    
    // Instantiate Matrix Gen
    matrix_gen u_gen (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .target_m(target_m),
        .target_n(target_n),
        .target_slot(target_slot),
        .done(done),
        .gen_slot_idx(gen_slot_idx),
        .gen_row(gen_row),
        .gen_col(gen_col),
        .gen_data(gen_data),
        .gen_we(gen_we),
        .gen_dim_m(gen_dim_m),
        .gen_dim_n(gen_dim_n),
        .gen_dim_we(gen_dim_we)
    );

    // TB Mux Logic
    reg tb_read_mode;
    reg [2:0] tb_read_row;
    reg [2:0] tb_read_col;
    reg [1:0] tb_read_slot;

    wire [1:0]  mux_slot_idx;
    wire [2:0]  mux_row;
    wire [2:0]  mux_col;
    wire [15:0] mux_data;
    wire        mux_we;
    wire [2:0]  mux_dim_m;
    wire [2:0]  mux_dim_n;
    wire        mux_dim_we;
    
    assign mux_slot_idx = tb_read_mode ? tb_read_slot : gen_slot_idx;
    assign mux_row      = tb_read_mode ? tb_read_row  : gen_row;
    assign mux_col      = tb_read_mode ? tb_read_col  : gen_col;
    assign mux_data     = tb_read_mode ? 16'b0        : gen_data;
    assign mux_we       = tb_read_mode ? 1'b0         : gen_we;
    assign mux_dim_m    = tb_read_mode ? 3'b0         : gen_dim_m;
    assign mux_dim_n    = tb_read_mode ? 3'b0         : gen_dim_n;
    assign mux_dim_we   = tb_read_mode ? 1'b0         : gen_dim_we;

    // Instantiate Matrix Mem
    matrix_mem u_mem (
        .clk(clk),
        .rst_n(rst_n),
        .user_slot_idx(mux_slot_idx),
        .user_row(mux_row),
        .user_col(mux_col),
        .user_data(mux_data),
        .user_we(mux_we),
        .user_dim_m(mux_dim_m),
        .user_dim_n(mux_dim_n),
        .user_dim_we(mux_dim_we),
        .user_rd_data(user_rd_data),
        
        .alu_rd_slot(2'b0),
        .alu_rd_row(3'b0),
        .alu_rd_col(3'b0),
        .alu_rd_data(),
        .alu_current_m(),
        .alu_current_n(),
        .alu_wr_slot(2'b0),
        .alu_wr_row(3'b0),
        .alu_wr_col(3'b0),
        .alu_wr_data(16'b0),
        .alu_wr_we(1'b0),
        .alu_res_m(3'b0),
        .alu_res_n(3'b0),
        .alu_dim_we(1'b0)
    );
    
    initial begin
        $monitor("Time=%t rst_n=%b start=%b done=%b state=%d", $time, rst_n, start, done, u_gen.state);
    end
    
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    integer r, c;

    initial begin
        rst_n = 0;
        start = 0;
        tb_read_mode = 0;
        target_m = 4;
        target_n = 4;
        target_slot = 0; // Slot A

        #20 rst_n = 1;
        #20;
        
        $display("Starting Matrix Generation (4x4)...");
        @(negedge clk);
        start = 1;
        @(negedge clk);
        start = 0;
        
        // Timeout logic (Simple)
        // We cannot use fork..join_any easily in standard Verilog testbenches without proper flag support
        // So we just use a loop with timeout check
        
        // Wait for done
        wait(done);
        
        $display("Generation Done.");
        #50;
        
        // Read back and print
        $display("\n=== Generated Matrix (Slot A, 4x4) ===");
        tb_read_mode = 1;
        tb_read_slot = 0;
        
        for(r=0; r<4; r=r+1) begin
            for(c=0; c<4; c=c+1) begin
                tb_read_row = r;
                tb_read_col = c;
                #1; // Wait for async read
                $write("%4d ", user_rd_data);
            end
            $write("\n");
        end
        
        $finish;
    end
    
    // Safety timeout in separate block
    initial begin
        #10000;
        $display("TIMEOUT: Simulation took too long.");
        $finish;
    end

endmodule
