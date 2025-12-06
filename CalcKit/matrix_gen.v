`timescale 1ns / 1ps

module matrix_gen (
    input wire clk,
    input wire rst_n,
    
    input wire        start,
    input wire [2:0]  target_m,
    input wire [2:0]  target_n,
    input wire [1:0]  target_slot,
    output reg        done,
    
    output reg [1:0]  gen_slot_idx,
    output reg [2:0]  gen_row,
    output reg [2:0]  gen_col,
    output reg [15:0] gen_data,
    output reg        gen_we,
    output reg [2:0]  gen_dim_m,
    output reg [2:0]  gen_dim_n,
    output reg        gen_dim_we
);

    reg [15:0] lfsr_reg;
    
    localparam S_IDLE      = 0;
    localparam S_WRITE_DIM = 1;
    localparam S_GEN_LOOP  = 2;
    localparam S_DONE      = 3;
    
    reg [2:0] state;
    reg [2:0] i, j;
    reg [2:0] latched_m, latched_n;
    reg [1:0] latched_slot;

    wire feedback;
    assign feedback = lfsr_reg[15] ^ lfsr_reg[13] ^ lfsr_reg[12] ^ lfsr_reg[10];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            lfsr_reg <= 16'hACE1;
            done <= 0;
            gen_we <= 0;
            gen_dim_we <= 0;
            gen_slot_idx <= 0; gen_row <= 0; gen_col <= 0; gen_data <= 0;
            gen_dim_m <= 0; gen_dim_n <= 0;
            i <= 0; j <= 0;
            latched_m <= 0; latched_n <= 0; latched_slot <= 0;
        end else begin
            gen_we <= 0;
            gen_dim_we <= 0;
            done <= 0;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        latched_m <= target_m;
                        latched_n <= target_n;
                        latched_slot <= target_slot;
                        state <= S_WRITE_DIM;
                        $display("MatrixGen: Start received. Target: %d x %d", target_m, target_n);
                    end
                end
                
                S_WRITE_DIM: begin
                    gen_slot_idx <= latched_slot;
                    gen_dim_m <= latched_m;
                    gen_dim_n <= latched_n;
                    gen_dim_we <= 1;
                    
                    i <= 0;
                    j <= 0;
                    state <= S_GEN_LOOP;
                    $display("MatrixGen: Dimensions written. Entering Loop.");
                end
                
                S_GEN_LOOP: begin
                    lfsr_reg <= {lfsr_reg[14:0], feedback};
                    
                    gen_slot_idx <= latched_slot;
                    gen_row <= i;
                    gen_col <= j;
                    gen_data <= {12'b0, lfsr_reg[3:0]}; 
                    gen_we <= 1;
                    
                    //$display("MatrixGen: Writing (%d, %d) = %h", i, j, lfsr_reg[3:0]);

                    if (j == latched_n - 1) begin
                        j <= 0;
                        if (i == latched_m - 1) begin
                            state <= S_DONE;
                            $display("MatrixGen: Loop Done.");
                        end else begin
                            i <= i + 1;
                        end
                    end else begin
                        j <= j + 1;
                    end
                end
                
                S_DONE: begin
                    done <= 1;
                    if (!start) state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
