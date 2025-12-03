`timescale 1ns / 1ps

module matrix_alu (
    input  wire        clk,
    input  wire        rst_n,
    
    // 控制接口
    input  wire        start,
    input  wire [2:0]  opcode,
    input  wire [15:0] scalar_val,

    output reg         done,
    output reg         error,

    // 读端口（从 matrix_mem）
    output reg  [1:0]  mem_rd_slot,
    output reg  [2:0]  mem_rd_row,
    output reg  [2:0]  mem_rd_col,
    input  wire [15:0] mem_rd_data, // 从 memory_controller 读取的数据
    input  wire [2:0]  mem_current_m, // memory_controller 提供当前槽位的行数
    input  wire [2:0]  mem_current_n, // memory_controller 提供当前槽位的列数

    // 写端口（写回 matrix_mem）
    output wire [1:0]  mem_wr_slot,
    output reg  [2:0]  mem_wr_row,
    output reg  [2:0]  mem_wr_col,
    output reg  [15:0] mem_wr_data,
    output reg         mem_wr_we,
    output reg  [2:0]  mem_res_m, // 结果矩阵的行数
    output reg  [2:0]  mem_res_n, // 结果矩阵的列数
    output reg         mem_dim_we // 结果维度写入使能
);

    // ------------------------------
    // 槽位定义
    // ------------------------------
    localparam SLOT_A = 2'd0;
    localparam SLOT_B = 2'd1;
    localparam SLOT_C = 2'd2;

    assign mem_wr_slot = SLOT_C;  // 结果固定写到 C 槽

    // ------------------------------
    // 操作码定义
    // ------------------------------
    localparam OP_ADD = 3'b000;
    localparam OP_SUB = 3'b001;
    localparam OP_MUL = 3'b010;
    localparam OP_SCA = 3'b011;
    localparam OP_TRA = 3'b100;

    // ------------------------------
    // 状态机定义 (已更新编号)
    // ------------------------------
    localparam S_IDLE           = 4'd0;
    localparam S_GET_DIM_A      = 4'd1;
    localparam S_GET_DIM_B      = 4'd2;
    localparam S_CHECK          = 4'd3;
    localparam S_INIT_CALC      = 4'd4;
    localparam S_READ_OP1       = 4'd5;
    localparam S_READ_OP2       = 4'd6;
    localparam S_WAIT_OP2_READY = 4'd7;  // <-- 新增状态
    localparam S_MAT_MUL_ACC    = 4'd8;  // 编号后移
    localparam S_WRITE          = 4'd9;  // 编号后移
    localparam S_DONE           = 4'd10; // 编号后移
    localparam S_ERROR          = 4'd11; // 编号后移

    reg [3:0] state;

    // 矩阵维度寄存
    reg [2:0] dim_ma, dim_na; // A 矩阵维度
    reg [2:0] dim_mb, dim_nb; // B 矩阵维度

    // 循环变量
    reg [2:0] i, j, k; // i: 行, j: 列, k: 内积索引

    // 操作数寄存器
    reg signed [15:0] reg_op_a; // 存储 A 矩阵当前读取元素
    reg signed [15:0] reg_op_b; // 存储 B 矩阵当前读取元素
    reg signed [31:0] accumulator; // 矩阵乘法累加器 (32位防止溢出)

    // ------------------------------
    // 主状态机逻辑
    // ------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            done        <= 1'b0;
            error       <= 1'b0;
            mem_wr_we   <= 1'b0;
            mem_dim_we  <= 1'b0;

            i <= 3'd0;
            j <= 3'd0;
            k <= 3'd0;

            dim_ma <= 3'd0; dim_na <= 3'd0;
            dim_mb <= 3'd0; dim_nb <= 3'd0;
            accumulator <= 32'd0;

            mem_res_m  <= 3'd0;
            mem_res_n  <= 3'd0;
            mem_wr_row <= 3'd0;
            mem_wr_col <= 3'd0;
            mem_wr_data <= 16'd0;
        end else begin
            // 单拍信号清零
            mem_wr_we  <= 1'b0;
            mem_dim_we <= 1'b0;
            done      <= 1'b0;

            // 新一轮 start 时清 error
            if (start && state == S_IDLE)
                error <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        $display("[%0t] ALU_State: S_IDLE -> S_GET_DIM_A", $time);
                        state <= S_GET_DIM_A;
                    end
                end

                S_GET_DIM_A: begin
                    dim_ma <= mem_current_m;
                    dim_na <= mem_current_n;
                    $display("[%0t] ALU_State: S_GET_DIM_A. A_dim=%d x %d -> S_GET_DIM_B", $time, mem_current_m, mem_current_n);
                    state  <= S_GET_DIM_B;
                end

                S_GET_DIM_B: begin
                    dim_mb <= mem_current_m;
                    dim_nb <= mem_current_n;
                    $display("[%0t] ALU_State: S_GET_DIM_B. B_dim=%d x %d -> S_CHECK", $time, mem_current_m, mem_current_n);
                    state  <= S_CHECK;
                end

                S_CHECK: begin
                    case (opcode)
                        OP_ADD, OP_SUB: begin
                            if (dim_ma == dim_mb && dim_na == dim_nb) begin
                                mem_res_m <= dim_ma; mem_res_n <= dim_na;
                                $display("[%0t] ALU_State: S_CHECK. ADD/SUB dims OK. Res=%d x %d -> S_INIT_CALC", $time, dim_ma, dim_na);
                                state     <= S_INIT_CALC;
                            end else begin
                                error <= 1'b1; $display("[%0t] ALU_State: S_CHECK. ERROR: ADD/SUB dim mismatch. -> S_ERROR", $time); state <= S_ERROR;
                            end
                        end
                        OP_MUL: begin
                            if (dim_na == dim_mb) begin
                                mem_res_m <= dim_ma; mem_res_n <= dim_nb;
                                $display("[%0t] ALU_State: S_CHECK. MUL dims OK. Res=%d x %d -> S_INIT_CALC", $time, dim_ma, dim_nb);
                                state     <= S_INIT_CALC;
                            end else begin
                                error <= 1'b1; $display("[%0t] ALU_State: S_CHECK. ERROR: MUL dim mismatch. -> S_ERROR", $time); state <= S_ERROR;
                            end
                        end
                        OP_SCA: begin
                            mem_res_m <= dim_ma; mem_res_n <= dim_na;
                            $display("[%0t] ALU_State: S_CHECK. SCA dims OK. Res=%d x %d -> S_INIT_CALC", $time, dim_ma, dim_na);
                            state     <= S_INIT_CALC;
                        end
                        OP_TRA: begin
                            mem_res_m <= dim_na; mem_res_n <= dim_ma;
                            $display("[%0t] ALU_State: S_CHECK. TRA dims OK. Res=%d x %d -> S_INIT_CALC", $time, dim_na, dim_ma);
                            state     <= S_INIT_CALC;
                        end
                        default: begin
                            error <= 1'b1; $display("[%0t] ALU_State: S_CHECK. ERROR: Invalid opcode %d. -> S_ERROR", $time, opcode); state <= S_ERROR;
                        end
                    endcase
                end

                S_INIT_CALC: begin
                    mem_dim_we  <= 1'b1;
                    i           <= 3'd0; j <= 3'd0; k <= 3'd0; accumulator <= 32'd0;
                    $display("[%0t] ALU_State: S_INIT_CALC. Res_dim=%d x %d. Init i,j,k. -> S_READ_OP1", $time, mem_res_m, mem_res_n);
                    state       <= S_READ_OP1;
                end

                S_READ_OP1: begin
                    reg_op_a <= mem_rd_data;
                    $display("[%0t] ALU_State: S_READ_OP1 (i=%d,j=%d,k=%d). Read A[%d][%d]=%d. (Opcode=%d)", $time, i, j, k, mem_rd_row, mem_rd_col, mem_rd_data, opcode);
                    
                    if (opcode == OP_TRA || opcode == OP_SCA) begin
                        state <= S_WRITE;
                    end else if (opcode == OP_MUL) begin
                        accumulator <= 32'd0; // For new C[i][j] element, reset accumulator
                        state <= S_MAT_MUL_ACC;
                    end else begin // OP_ADD, OP_SUB
                        state <= S_READ_OP2;
                    end
                end

                S_READ_OP2: begin
                    reg_op_b <= mem_rd_data;
                    $display("[%0t] ALU_State: S_READ_OP2 (i=%d,j=%d). Read B[%d][%d]=%d. (reg_op_a=%d)", $time, i, j, mem_rd_row, mem_rd_col, mem_rd_data, reg_op_a);
                    state    <= S_WAIT_OP2_READY; // <-- 转移到等待状态
                end

                S_WAIT_OP2_READY: begin // <-- 新增状态：等待 reg_op_b 更新
                    $display("[%0t] ALU_State: S_WAIT_OP2_READY (i=%d,j=%d). reg_op_a=%d, reg_op_b=%d. -> S_WRITE", $time, i, j, reg_op_a, reg_op_b);
                    state <= S_WRITE;
                end

                S_MAT_MUL_ACC: begin
                    accumulator <= accumulator + $signed(reg_op_a) * $signed(mem_rd_data);
                    $display("[%0t] ALU_State: S_MAT_MUL_ACC (i=%d,j=%d,k=%d). Accu += %d * %d -> %d. (CurrentAccu: %d)", $time, i, j, k, reg_op_a, mem_rd_data, $signed(reg_op_a) * $signed(mem_rd_data), accumulator);
                    
                    if (k == dim_na - 1) begin
                        state <= S_WRITE;
                    end else begin
                        k     <= k + 1;
                        state <= S_READ_OP1; 
                    end
                end

                S_WRITE: begin
                    mem_wr_we   <= 1'b1;
                    mem_wr_row  <= i;
                    mem_wr_col  <= j;
                    
                    case (opcode)
                        OP_ADD: mem_wr_data <= $signed(reg_op_a) + $signed(reg_op_b);
                        OP_SUB: mem_wr_data <= $signed(reg_op_a) - $signed(reg_op_b);
                        OP_SCA: mem_wr_data <= $signed(reg_op_a) * $signed(scalar_val);
                        OP_TRA: mem_wr_data <= reg_op_a;
                        OP_MUL: mem_wr_data <= accumulator[15:0];
                        default: mem_wr_data <= 16'd0;
                    endcase
                    $display("[%0t] ALU_State: S_WRITE (i=%d,j=%d). C[%d][%d] = %d (0x%h). A=%d, B=%d. -> Next", $time, i, j, i, j, mem_wr_data, mem_wr_data, reg_op_a, reg_op_b);
                    
                    if (j == mem_res_n - 1) begin
                        j <= 3'd0;
                        if (i == mem_res_m - 1) begin
                            state <= S_DONE;
                        end else begin
                            i <= i + 1;
                            k <= 3'd0;
                            state <= S_READ_OP1; 
                        end
                    end else begin
                        j <= j + 1;
                        k <= 3'd0;
                        state <= S_READ_OP1;
                    end
                end

                S_DONE: begin
                    done <= 1'b1;
                    if (!start) begin
                        state <= S_IDLE;
                        $display("[%0t] ALU_State: S_DONE. Start deasserted. -> S_IDLE", $time);
                    end
                end

                S_ERROR: begin
                    error <= 1'b1;
                    if (!start) begin
                        state <= S_IDLE;
                        $display("[%0t] ALU_State: S_ERROR. Start deasserted. -> S_IDLE", $time);
                    end
                end

                default: begin
                    $display("[%0t] ALU_State: WARNING: Unknown state %d. -> S_IDLE", $time, state);
                    state <= S_IDLE;
                end
            endcase
        end
    end

    // 读地址生成逻辑 (保持不变)
    always @(*) begin
        // 默认值
        mem_rd_slot = SLOT_A;
        mem_rd_row  = 3'd0;
        mem_rd_col  = 3'd0;

        case (state)
            S_IDLE: begin
                mem_rd_slot = SLOT_A;
            end

            S_GET_DIM_A: begin
                mem_rd_slot = SLOT_A;
            end
            S_GET_DIM_B: begin
                mem_rd_slot = SLOT_B;
            end

            S_READ_OP1: begin
                mem_rd_slot = SLOT_A;
                if (opcode == OP_TRA) begin
                    mem_rd_row = j;
                    mem_rd_col = i;
                end else if (opcode == OP_MUL) begin
                    mem_rd_row = i;
                    mem_rd_col = k;
                end else begin // OP_ADD, OP_SUB, OP_SCA
                    mem_rd_row = i;
                    mem_rd_col = j;
                end
            end

            S_READ_OP2: begin
                mem_rd_slot = SLOT_B;
                mem_rd_row  = i;
                mem_rd_col  = j;
            end
            // S_WAIT_OP2_READY 状态保持上一个状态的 mem_rd_slot/row/col

            S_MAT_MUL_ACC: begin
                mem_rd_slot = SLOT_B;
                mem_rd_row  = k;
                mem_rd_col  = j;
            end

            default: begin
                mem_rd_slot = SLOT_A; // 任意默认值
                mem_rd_row  = i;
                mem_rd_col  = j;
            end
        endcase
    end

endmodule
