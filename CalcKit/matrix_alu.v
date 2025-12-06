`timescale 1ns / 1ps

module matrix_alu (
    input wire clk,
    input wire rst_n,
    
    // Control Interface
    input wire        start,
    input wire [2:0]  opcode,      
    input wire [15:0] scalar_val,  
    output reg        done,        
    output reg        error,       

    // Mem Read Port
    output reg [1:0]  mem_rd_slot, 
    output reg [2:0]  mem_rd_row,
    output reg [2:0]  mem_rd_col,
    input  wire [15:0] mem_rd_data, 
    input wire [2:0]  mem_current_m, 
    input wire [2:0]  mem_current_n,

    // Mem Write Port
    output wire [1:0]  mem_wr_slot, 
    output reg [2:0]  mem_wr_row,
    output reg [2:0]  mem_wr_col,
    output reg [15:0] mem_wr_data,
    output reg        mem_wr_we,
    output reg [2:0]  mem_res_m,   
    output reg [2:0]  mem_res_n,
    output reg        mem_dim_we   
);

    // OpCodes
    localparam OP_ADD = 3'b000;
    localparam OP_SUB = 3'b001;
    localparam OP_MUL = 3'b010;
    localparam OP_SCA = 3'b011;
    localparam OP_TRA = 3'b100;

    localparam SLOT_A = 2'd0;
    localparam SLOT_B = 2'd1;
    localparam SLOT_C = 2'd2;

    // States
    localparam S_IDLE        = 0;
    localparam S_GET_DIM_A   = 1;
    localparam S_GET_DIM_B   = 2;
    localparam S_CHECK       = 3;
    localparam S_INIT_CALC   = 4;
    localparam S_READ_OP1    = 5; 
    localparam S_READ_OP2    = 6; 
    localparam S_MAT_MUL_ACC = 7; 
    localparam S_WRITE       = 8; 
    localparam S_DONE        = 9;
    localparam S_ERROR       = 10;

    reg [3:0] state;
    
    // Registers
    reg [2:0] dim_ma, dim_na, dim_mb, dim_nb;
    reg [2:0] i, j, k;
    
    // Operand Registers
    reg signed [15:0] reg_op_a;
    reg signed [15:0] reg_op_b;
    reg signed [31:0] accumulator; 

    assign mem_wr_slot = SLOT_C;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            done <= 0; error <= 0;
            mem_wr_we <= 0; mem_dim_we <= 0;
            i <= 0; j <= 0; k <= 0;
            mem_res_m <= 0; mem_res_n <= 0;
            dim_ma <=0; dim_na<=0; dim_mb<=0; dim_nb<=0;
            reg_op_a <= 0; reg_op_b <= 0; accumulator <= 0;
        end else begin
            // Pulse Clears
            mem_wr_we <= 0;
            mem_dim_we <= 0;
            done <= 0;
            if (start) error <= 0;

            case (state)
                S_IDLE: if (start) state <= S_GET_DIM_A;

                // --- 1. Fetch Dimension A ---
                // 在状态结束时，mem_rd_slot 还是 A (由组合逻辑控制)
                // 所以此时 mem_current_m 是 A 的维度。正确锁存！
                S_GET_DIM_A: begin
                    dim_ma <= mem_current_m; 
                    dim_na <= mem_current_n;
                    state <= S_GET_DIM_B;
                end
                
                // --- 2. Fetch Dimension B ---
                // 同理，此时 mem_rd_slot 是 B。
                S_GET_DIM_B: begin
                    dim_mb <= mem_current_m;
                    dim_nb <= mem_current_n;
                    state <= S_CHECK; 
                end

                // --- 3. Validity Check ---
                S_CHECK: begin
                    case (opcode)
                        OP_ADD, OP_SUB: begin
                            if (dim_ma == dim_mb && dim_na == dim_nb) begin
                                mem_res_m <= dim_ma; mem_res_n <= dim_na;
                                state <= S_INIT_CALC;
                            end else state <= S_ERROR;
                        end
                        OP_MUL: begin
                            if (dim_na == dim_mb) begin // col_A == row_B
                                mem_res_m <= dim_ma; mem_res_n <= dim_nb;
                                state <= S_INIT_CALC;
                            end else state <= S_ERROR;
                        end
                        OP_TRA: begin
                            mem_res_m <= dim_na; mem_res_n <= dim_ma; 
                            state <= S_INIT_CALC;
                        end
                        OP_SCA: begin
                            mem_res_m <= dim_ma; mem_res_n <= dim_na;
                            state <= S_INIT_CALC;
                        end
                        default: state <= S_ERROR;
                    endcase
                end

                // --- 4. Init Calculation ---
                S_INIT_CALC: begin
                    mem_dim_we <= 1; // Pulse write dim
                    i <= 0; j <= 0; k <= 0;
                    accumulator <= 0;
                    state <= S_READ_OP1;
                end

                // --- 5. Read Operand A ---
                S_READ_OP1: begin
                    reg_op_a <= mem_rd_data; // Latch A
                    if (opcode == OP_TRA || opcode == OP_SCA) begin
                        state <= S_WRITE; 
                    end else if (opcode == OP_MUL) begin
                        state <= S_MAT_MUL_ACC; 
                    end else begin
                        state <= S_READ_OP2; 
                    end
                end

                // --- 6. Read Operand B ---
                S_READ_OP2: begin
                    reg_op_b <= mem_rd_data; // Latch B
                    state <= S_WRITE;
                end

                // --- 7. Matrix Mult Accumulation ---
                S_MAT_MUL_ACC: begin
                    // reg_op_a holds A[i][k]
                    // mem_rd_data holds B[k][j] (Address set by comb logic below)
                    accumulator <= accumulator + $signed(reg_op_a) * $signed(mem_rd_data);
                    
                    if (k == dim_na - 1) begin
                        state <= S_WRITE;
                    end else begin
                        k <= k + 1;
                        state <= S_READ_OP1; // Next k
                    end
                end

                // --- 8. Write Result ---
                S_WRITE: begin
                    mem_wr_we <= 1;
                    mem_wr_row <= i;
                    mem_wr_col <= j;

                    case (opcode)
                        OP_ADD: mem_wr_data <= $signed(reg_op_a) + $signed(reg_op_b);
                        OP_SUB: mem_wr_data <= $signed(reg_op_a) - $signed(reg_op_b);
                        OP_SCA: mem_wr_data <= $signed(reg_op_a) * $signed(scalar_val);
                        OP_TRA: mem_wr_data <= reg_op_a;
                        OP_MUL: mem_wr_data <= accumulator[15:0];
                    endcase

                    // Update Loop Counters
                    if (j == mem_res_n - 1) begin
                        j <= 0;
                        if (i == mem_res_m - 1) begin
                            state <= S_DONE;
                        end else begin
                            i <= i + 1;
                            k <= 0; accumulator <= 0;
                            state <= S_READ_OP1;
                        end
                    end else begin
                        j <= j + 1;
                        k <= 0; accumulator <= 0;
                        state <= S_READ_OP1;
                    end
                end

                S_DONE: begin
                    done <= 1;
                    if (!start) state <= S_IDLE;
                end
                S_ERROR: begin
                    error <= 1;
                    if (!start) state <= S_IDLE;
                end
            endcase
        end
    end

    // ============================================================
    // Combinational Logic: Read Address Control
    // ============================================================
    always @(*) begin
        mem_rd_slot = SLOT_A;
        mem_rd_row = 0;
        mem_rd_col = 0;

        case (state)
            S_IDLE:      mem_rd_slot = SLOT_A;
            S_GET_DIM_A: mem_rd_slot = SLOT_A; // Keep pointing to A
            S_GET_DIM_B: mem_rd_slot = SLOT_B; // Point to B

            S_READ_OP1: begin
                mem_rd_slot = SLOT_A;
                if (opcode == OP_TRA) begin
                    mem_rd_row = j; // Transpose: read A[j][i]
                    mem_rd_col = i;
                end else if (opcode == OP_MUL) begin
                    mem_rd_row = i; // Mul: read A[i][k]
                    mem_rd_col = k;
                end else begin
                    mem_rd_row = i; // Add/Sub: read A[i][j]
                    mem_rd_col = j;
                end
            end

            S_READ_OP2: begin
                mem_rd_slot = SLOT_B;
                mem_rd_row = i; 
                mem_rd_col = j;
            end

            S_MAT_MUL_ACC: begin
                mem_rd_slot = SLOT_B;
                mem_rd_row = k; // Mul: read B[k][j]
                mem_rd_col = j;
            end
        endcase
    end

endmodule