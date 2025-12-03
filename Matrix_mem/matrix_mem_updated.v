module matrix_mem (
    input  wire clk,
    input  wire rst_n,

    // User Port
    input  wire [1:0]  user_slot_idx,
    input  wire [2:0]  user_row,
    input  wire [2:0]  user_col,
    input  wire [15:0] user_data,
    input  wire        user_we,
    input  wire [2:0]  user_dim_m,
    input  wire [2:0]  user_dim_n,
    input  wire        user_dim_we,

    // ALU Read Port
    input  wire [1:0]  alu_rd_slot,
    input  wire [2:0]  alu_rd_row,
    input  wire [2:0]  alu_rd_col,
    output wire [15:0] user_rd_data,
    output wire [15:0] alu_rd_data,
    output wire [2:0]  alu_current_m,
    output wire [2:0]  alu_current_n,

    // ALU Write Port
    input  wire [1:0]  alu_wr_slot,
    input  wire [2:0]  alu_wr_row,
    input  wire [2:0]  alu_wr_col,
    input  wire [15:0] alu_wr_data,
    input  wire        alu_wr_we,
    input  wire [2:0]  alu_res_m,
    input  wire [2:0]  alu_res_n,
    input  wire        alu_dim_we
);

    localparam MEM_DEPTH = 96; // 3 * 32 (Max 8x8 matrix needs 64 elements, 3 matrices -> 3*64 = 192, here 96 is enough for 5x5)

    reg [15:0] mem [0:MEM_DEPTH-1]; // Three 5x5 matrices, 2'd5 * 2'd5 = 25 elements. 25 * 3 = 75. 96 is safe.

    reg [2:0] dims_m [0:2]; // dims_m[0] for SLOT_A, dims_m[1] for SLOT_B, dims_m[2] for SLOT_C
    reg [2:0] dims_n [0:2]; // dims_n[0] for SLOT_A, dims_n[1] for SLOT_B, dims_n[2] for SLOT_C

    integer i;

    // 计算内存地址
    // 假设矩阵最大为 5x5，所以每行最大 5 个元素。一个槽位最多需要 5 * 5 = 25 个地址
    // 为简单起见，这里假设每个槽位从 0, 32, 64 开始
    wire [6:0] base_addr_user   = user_slot_idx * 5 * 5; // Start of each slot
    wire [6:0] addr_user        = base_addr_user + user_row * 5 + user_col;

    wire [6:0] base_addr_alu_rd = alu_rd_slot * 5 * 5;
    wire [6:0] addr_alu_rd      = base_addr_alu_rd + alu_rd_row * 5 + alu_rd_col;

    wire [6:0] base_addr_alu_wr = alu_wr_slot * 5 * 5;
    wire [6:0] addr_alu_wr      = base_addr_alu_wr + alu_wr_row * 5 + alu_wr_col;


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 3; i = i + 1) begin
                dims_m[i] <= 3'd0;
                dims_n[i] <= 3'd0;
            end
            // 内存复位是可选的，大型RAM通常不复位
            // for (i = 0; i < MEM_DEPTH; i = i + 1) begin
            //     mem[i] <= 16'd0;
            // end
        end else begin
            if (user_we) begin
                mem[addr_user] <= user_data;
            end

            if (user_dim_we) begin
                dims_m[user_slot_idx] <= user_dim_m;
                dims_n[user_slot_idx] <= user_dim_n;
            end

            if (alu_wr_we) begin
                mem[addr_alu_wr] <= alu_wr_data;
            end

            if (alu_dim_we) begin
                // ALU 写结果维度固定到 SLOT_C (index 2)
                dims_m[2] <= alu_res_m; // 对应 SLOT_C
                dims_n[2] <= alu_res_n; // 对应 SLOT_C
            end
        end
    end

    // 组合逻辑读取
    assign alu_rd_data   = mem[addr_alu_rd];
    assign alu_current_m = dims_m[alu_rd_slot];
    assign alu_current_n = dims_n[alu_rd_slot];
    assign user_rd_data  = mem[addr_user];

endmodule
