`timescale 1ns / 1ps

module matrix_mem (
    input wire clk,
    input wire rst_n,

    // Port 1: User Write (Input / Gen / Conv)
    // Used for creating NEW matrices or writing data to them
    input wire [2:0]  user_dim_m,  // Dimension M (1-5)
    input wire [2:0]  user_dim_n,  // Dimension N (1-5)
    input wire        user_dim_we, // Assert to allocate a NEW matrix slot

    input wire [2:0]  user_row,    // Row index for data write
    input wire [2:0]  user_col,    // Col index for data write
    input wire [15:0] user_data,   // Data to write
    input wire        user_we,     // Assert to write data to CURRENT allocated matrix
    
    // Port 1: User Read (Display)
    // User selects Spec (M, N) and ID (1 or 2)
    input wire [2:0]  user_rd_m,
    input wire [2:0]  user_rd_n,
    input wire [1:0]  user_rd_id,  // 1 or 2
    input wire [2:0]  user_rd_row,
    input wire [2:0]  user_rd_col,
    output wire [15:0] user_rd_data,
    output wire [1:0]  user_rd_count, // How many matrices stored for this spec?
    
    // Port 2: ALU Read A
    input wire [2:0]  alu_a_m, alu_a_n,
    input wire [1:0]  alu_a_id,
    input wire [2:0]  alu_a_row, alu_a_col,
    output wire [15:0] alu_a_data,
    
    // Port 2: ALU Read B
    input wire [2:0]  alu_b_m, alu_b_n,
    input wire [1:0]  alu_b_id,
    input wire [2:0]  alu_b_row, alu_b_col,
    output wire [15:0] alu_b_data,
    
    // Port 2: ALU Write (Result)
    // Similar to User Write, allocates a new matrix
    input wire [2:0]  alu_res_m,
    input wire [2:0]  alu_res_n,
    input wire        alu_res_dim_we, // Start new result matrix
    input wire [2:0]  alu_res_row,
    input wire [2:0]  alu_res_col,
    input wire [15:0] alu_res_data,
    input wire        alu_res_we
);

    // Storage: 50 slots * 32 words = 1600 words
    // 25 Specs (1x1 .. 5x5). Each Spec has 2 Slots.
    localparam MEM_DEPTH = 1600;
    reg [15:0] mem [0:MEM_DEPTH-1];

    // Meta-data for 25 specs
    // Map (m, n) -> spec_idx = (m-1)*5 + (n-1)
    // Indices 0..24
    reg [1:0] spec_count [0:24]; // 0, 1, 2
    reg       spec_start [0:24]; // 0 or 1. Points to "Oldest" (ID 1).
    
    // Internal registers to track "Current Write Slot" for User and ALU
    reg [5:0] user_active_phys_slot; // 0..49
    reg [5:0] alu_active_phys_slot;  // 0..49

    integer i;
    
    // Helpers
    function [4:0] get_spec_idx;
        input [2:0] m, n;
        begin
            if (m >= 1 && m <= 5 && n >= 1 && n <= 5)
                get_spec_idx = (m-1)*5 + (n-1);
            else
                get_spec_idx = 0; // Default or Error
        end
    endfunction
    
    // Get Physical Slot from Spec + ID (1 or 2)
    function [5:0] get_phys_slot;
        input [4:0] spec_idx;
        input [1:0] logical_id; // 1 or 2
        input [1:0] count;
        input       start;
        reg [1:0] offset;
        begin
            // ID 1 -> Start
            // ID 2 -> Start + 1 (Mod 2)
            if (logical_id == 1) offset = 0;
            else offset = 1;
            
            // Physical base for spec is spec_idx * 2
            // Logical mapping:
            // If start=0: Phys 0 is ID1, Phys 1 is ID2
            // If start=1: Phys 1 is ID1, Phys 0 is ID2
            // Target Phys Offset = (start + offset) % 2
            
            get_phys_slot = {spec_idx, 1'b0} + ((start + offset) & 1'b1);
        end
    endfunction

    // --------------------------------------------------------
    // Write Logic
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 25; i = i + 1) begin
                spec_count[i] <= 0;
                spec_start[i] <= 0;
            end
            user_active_phys_slot <= 0;
            alu_active_phys_slot <= 0;
        end else begin
            // --- User Allocation ---
            if (user_dim_we) begin : blk_user_alloc
                // Allocating new matrix
                reg [4:0] u_spec;
                u_spec = get_spec_idx(user_dim_m, user_dim_n);
                
                if (spec_count[u_spec] < 2) begin
                    // Fill empty slot
                    // If count=0 -> Slot 0.
                    // If count=1 -> Slot 1.
                    user_active_phys_slot <= {u_spec, 1'b0} + spec_count[u_spec][0];
                    spec_count[u_spec] <= spec_count[u_spec] + 1;
                    // start ptr doesn't change
                end else begin
                    // Full, replace oldest (at start ptr)
                    user_active_phys_slot <= {u_spec, 1'b0} + spec_start[u_spec];
                    spec_start[u_spec] <= ~spec_start[u_spec];
                end
            end
            
            // --- User Data Write ---
            if (user_we) begin
                // Write to active slot
                // Addr = Slot * 32 + Row*5 + Col? 
                // Wait, logic says "row << 2 + row + col" for index
                // 32 words per slot is convenient.
                mem[{user_active_phys_slot, 5'd0} + ((user_row << 2) + user_row) + user_col] <= user_data;
            end
            
            // --- ALU Allocation ---
            if (alu_res_dim_we) begin : blk_alu_alloc
                reg [4:0] a_spec;
                a_spec = get_spec_idx(alu_res_m, alu_res_n);
                
                if (spec_count[a_spec] < 2) begin
                    alu_active_phys_slot <= {a_spec, 1'b0} + spec_count[a_spec][0];
                    spec_count[a_spec] <= spec_count[a_spec] + 1;
                end else begin
                    alu_active_phys_slot <= {a_spec, 1'b0} + spec_start[a_spec];
                    spec_start[a_spec] <= ~spec_start[a_spec];
                end
            end
            
            // --- ALU Data Write ---
            if (alu_res_we) begin
                mem[{alu_active_phys_slot, 5'd0} + ((alu_res_row << 2) + alu_res_row) + alu_res_col] <= alu_res_data;
            end
        end
    end

    // --------------------------------------------------------
    // Read Logic (Asynchronous)
    // --------------------------------------------------------
    
    // User Read
    wire [4:0] rd_spec = get_spec_idx(user_rd_m, user_rd_n);
    wire [5:0] rd_phys = get_phys_slot(rd_spec, user_rd_id, spec_count[rd_spec], spec_start[rd_spec]);
    
    assign user_rd_data = mem[{rd_phys, 5'd0} + ((user_rd_row << 2) + user_rd_row) + user_rd_col];
    assign user_rd_count = spec_count[rd_spec];

    // ALU Read A
    wire [4:0] alu_a_spec = get_spec_idx(alu_a_m, alu_a_n);
    wire [5:0] alu_a_phys = get_phys_slot(alu_a_spec, alu_a_id, spec_count[alu_a_spec], spec_start[alu_a_spec]);
    assign alu_a_data = mem[{alu_a_phys, 5'd0} + ((alu_a_row << 2) + alu_a_row) + alu_a_col];

    // ALU Read B
    wire [4:0] alu_b_spec = get_spec_idx(alu_b_m, alu_b_n);
    wire [5:0] alu_b_phys = get_phys_slot(alu_b_spec, alu_b_id, spec_count[alu_b_spec], spec_start[alu_b_spec]);
    assign alu_b_data = mem[{alu_b_phys, 5'd0} + ((alu_b_row << 2) + alu_b_row) + alu_b_col];

endmodule
