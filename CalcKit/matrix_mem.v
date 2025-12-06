`timescale 1ns / 1ps

module matrix_mem (
    input wire clk,
    input wire rst_n,

    // Port 1: User Interface
    input wire [1:0]  user_slot_idx,
    input wire [2:0]  user_row,
    input wire [2:0]  user_col,
    input wire [15:0] user_data,
    input wire        user_we,
    input wire [2:0]  user_dim_m,
    input wire [2:0]  user_dim_n,
    input wire        user_dim_we,

    // Port 2: ALU Interface
    input wire [1:0]  alu_rd_slot,
    input wire [2:0]  alu_rd_row,
    input wire [2:0]  alu_rd_col,
    output wire [15:0] user_rd_data,
    output wire [15:0] alu_rd_data,
    output wire [2:0] alu_current_m,
    output wire [2:0] alu_current_n,
    // New: User Dims Output
    output wire [2:0] user_current_m,
    output wire [2:0] user_current_n,

    input wire [1:0]  alu_wr_slot,
    input wire [2:0]  alu_wr_row,
    input wire [2:0]  alu_wr_col,
    input wire [15:0] alu_wr_data,
    input wire        alu_wr_we,
    input wire [2:0]  alu_res_m,
    input wire [2:0]  alu_res_n,
    input wire        alu_dim_we
);

    localparam MEM_DEPTH = 96; 
    reg [15:0] mem [0:MEM_DEPTH-1];
    reg [2:0] dims_m [0:2]; 
    reg [2:0] dims_n [0:2];

    wire [6:0] addr_user;
    wire [6:0] addr_alu_rd;
    wire [6:0] addr_alu_wr;

    // =========================================================================
    // BUG FIX: 显式扩展位宽，防止 (row << 2) 发生3位截断
    // {3'd0, user_row} 将其转换为 6位数字，然后再移位和相加
    // =========================================================================
    wire [5:0] u_row_ext = {3'd0, user_row};
    wire [5:0] r_row_ext = {3'd0, alu_rd_row};
    wire [5:0] w_row_ext = {3'd0, alu_wr_row};

    assign addr_user   = {user_slot_idx, 5'd0} + ((u_row_ext << 2) + u_row_ext) + user_col;
    assign addr_alu_rd = {alu_rd_slot,   5'd0} + ((r_row_ext << 2) + r_row_ext) + alu_rd_col;
    assign addr_alu_wr = {alu_wr_slot,   5'd0} + ((w_row_ext << 2) + w_row_ext) + alu_wr_col;

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 3; i = i + 1) begin
                dims_m[i] <= 3'd0;
                dims_n[i] <= 3'd0;
            end
        end else begin
            // User Write
            if (user_we) mem[addr_user] <= user_data;
            if (user_dim_we) begin
                dims_m[user_slot_idx] <= user_dim_m;
                dims_n[user_slot_idx] <= user_dim_n;
            end

            // ALU Write
            if (alu_wr_we) mem[addr_alu_wr] <= alu_wr_data;
            if (alu_dim_we) begin
                dims_m[alu_wr_slot] <= alu_res_m;
                dims_n[alu_wr_slot] <= alu_res_n;
            end
        end
    end

    // Asynchronous Read
    assign alu_rd_data = mem[addr_alu_rd];
    assign alu_current_m = dims_m[alu_rd_slot];
    assign alu_current_n = dims_n[alu_rd_slot];
    
    // User Dims
    assign user_current_m = dims_m[user_slot_idx];
    assign user_current_n = dims_n[user_slot_idx];

    // 【新增】Asynchronous Read for User
    // 当 user_we 为 0 时，user_rd_data 输出当前地址的数据
    assign user_rd_data = mem[addr_user];

endmodule