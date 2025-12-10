`timescale 1ns / 1ps

module bonus_conv (
    input wire clk,
    input wire rst_n,
    input wire start_conv,
    
    // Interface to Matrix Memory (Read Only)
    output reg [1:0]  mem_rd_slot,
    output reg [2:0]  mem_rd_row,
    output reg [2:0]  mem_rd_col,
    input  wire [15:0] mem_rd_data,
    
    // Output Interface
    output reg [15:0] conv_res_data,
    output reg        conv_res_valid, // Indicates valid data output
    output reg        conv_done,
    output reg [31:0] total_cycles // Cycle count output
);

    // =================================================================
    // 1. Input Image ROM (Hardcoded)
    // =================================================================
    reg [3:0] rom_x;
    reg [3:0] rom_y;
    wire [3:0] rom_data;
    
    input_image_rom u_rom (
        .clk(clk),
        .x(rom_x),
        .y(rom_y),
        .data_out(rom_data)
    );

    // =================================================================
    // 2. Kernel Storage
    // =================================================================
    reg signed [15:0] kernel [0:2][0:2]; // 3x3 Kernel

    // =================================================================
    // 3. FSM & Counters
    // =================================================================
    localparam S_IDLE        = 0;
    localparam S_LOAD_KERNEL = 1;
    localparam S_CALC_INIT   = 2;
    localparam S_CALC_PRE    = 3;
    localparam S_CALC_MAC    = 4;
    localparam S_CALC_DONE   = 5;
    localparam S_DONE        = 6;

    reg [3:0] state;
    reg [3:0] kr, kc;       // Kernel loop counters (0-2)
    reg [3:0] next_kr, next_kc; // For address lookahead
    reg [3:0] out_r, out_c; // Output loop counters (0-7, 0-9)
    
    reg signed [31:0] accumulator;
    reg [3:0] mac_cnt;      // 0 to 8
    
    reg [31:0] cycle_counter; // Internal counter

    // State Machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            mem_rd_slot <= 0;
            mem_rd_row <= 0;
            mem_rd_col <= 0;
            conv_res_data <= 0;
            conv_res_valid <= 0;
            conv_done <= 0;
            kr <= 0; kc <= 0;
            out_r <= 0; out_c <= 0;
            rom_x <= 0; rom_y <= 0;
            accumulator <= 0;
            mac_cnt <= 0;
            cycle_counter <= 0;
            total_cycles <= 0;
        end else begin
            // Default pulse resets
            conv_res_valid <= 0;
            conv_done <= 0;
            
            // Cycle Counting Logic
            if (state != S_IDLE && state != S_DONE) begin
                cycle_counter <= cycle_counter + 1;
            end else if (state == S_IDLE && start_conv) begin
                cycle_counter <= 0;
            end

            case (state)
                S_IDLE: begin
                    if (start_conv) begin
                        state <= S_LOAD_KERNEL;
                        kr <= 0;
                        kc <= 0;
                        // Prepare read for (0,0)
                        mem_rd_slot <= 0; // Assume Kernel is in Slot A
                        mem_rd_row <= 0;
                        mem_rd_col <= 0;
                    end
                end
                // ... (S_LOAD_KERNEL and others remain same until S_DONE) ...
                S_LOAD_KERNEL: begin
                    kernel[kr][kc] <= mem_rd_data;

                    // Update counters for next read
                    if (kc == 2) begin
                        kc <= 0;
                        if (kr == 2) begin
                            state <= S_CALC_INIT;
                            out_r <= 0;
                            out_c <= 0;
                        end else begin
                            kr <= kr + 1;
                        end
                    end else begin
                        kc <= kc + 1;
                    end
                    
                    // Address Logic for next read
                    if (kc < 2) begin
                        mem_rd_col <= kc + 1;
                        mem_rd_row <= kr;
                    end else if (kr < 2) begin
                        mem_rd_col <= 0;
                        mem_rd_row <= kr + 1;
                    end
                end

                S_CALC_INIT: begin
                    // Start calculation for pixel (out_r, out_c)
                    accumulator <= 0;
                    mac_cnt <= 0;
                    kr <= 0; kc <= 0;
                    
                    // Setup ROM address for first pixel (0,0)
                    rom_x <= out_r;
                    rom_y <= out_c;
                    
                    // Prepare next address counters
                    next_kr <= 0;
                    next_kc <= 1;
                    
                    state <= S_CALC_PRE;
                end
                
                S_CALC_PRE: begin
                    // Pipeline fill: Set address for (0,1)
                    // Data for (0,0) will be ready at end of this cycle
                    rom_x <= out_r;
                    rom_y <= out_c + 1;
                    
                    // Update next counters
                    next_kr <= 0;
                    next_kc <= 2;
                    
                    state <= S_CALC_MAC;
                end

                S_CALC_MAC: begin
                    // MAC Operation: Acc += Data(prev) * Kernel[kr][kc]
                    // Data(prev) is rom_data, valid now.
                    accumulator <= accumulator + $signed({12'b0, rom_data}) * kernel[kr][kc];

                    // Prepare Address for NEXT NEXT (lookahead)
                    // We are currently at mac_cnt. 
                    // We just read Data[mac_cnt].
                    // We need to set address for Data[mac_cnt+2].
                    
                    // Update Loop Logic
                    if (mac_cnt == 8) begin
                        state <= S_CALC_DONE;
                    end else begin
                        mac_cnt <= mac_cnt + 1;
                        
                        // Update kr, kc for next Math
                        if (kc == 2) begin
                            kc <= 0;
                            kr <= kr + 1;
                        end else begin
                            kc <= kc + 1;
                        end
                        
                        // Update Address for lookahead (if not done)
                        // We need to set address for mac_cnt + 2
                        // But wait, in PRE we set address for mac_cnt=1 (Data 1).
                        // Now in MAC step 0 (mac_cnt=0), we need to set address for Data 2.
                        if (mac_cnt < 7) begin // Stop setting address after mac_cnt=6 (Addr 8)
                             rom_x <= out_r + next_kr;
                             rom_y <= out_c + next_kc;
                             
                             // Advance next counters
                             if (next_kc == 2) begin
                                 next_kc <= 0;
                                 next_kr <= next_kr + 1;
                             end else begin
                                 next_kc <= next_kc + 1;
                             end
                        end
                    end
                end

                S_CALC_DONE: begin
                    // Output Result
                    conv_res_data <= accumulator[15:0]; 
                    conv_res_valid <= 1;

                    // Move to next pixel
                    if (out_c == 9) begin
                        out_c <= 0;
                        if (out_r == 7) begin
                            state <= S_DONE;
                        end else begin
                            out_r <= out_r + 1;
                            state <= S_CALC_INIT;
                        end
                    end else begin
                        out_c <= out_c + 1;
                        state <= S_CALC_INIT;
                    end
                end

                S_DONE: begin
                    conv_done <= 1;
                    total_cycles <= cycle_counter; // Latch final count
                    if (!start_conv) state <= S_IDLE;
                end
            endcase
        end
    end

endmodule

// =================================================================
// Internal Module: Input Image ROM
// =================================================================
module input_image_rom(
    input clk,
    input [3:0] x, // Row
    input [3:0] y, // Col
    output reg [3:0] data_out
);
    // ROM storage - 10 rows x 12 cols = 120 elements
    reg [3:0] rom [0:119];

    // Initialize ROM content
    initial begin
        // Row 1: 372905184632
        rom[0]=4'd3; rom[1]=4'd7; rom[2]=4'd2; rom[3]=4'd9; rom[4]=4'd0; rom[5]=4'd5; 
        rom[6]=4'd1; rom[7]=4'd8; rom[8]=4'd4; rom[9]=4'd6; rom[10]=4'd3;rom[11]=4'd2;
        // Row 2: 816473905281
        rom[12]=4'd8;rom[13]=4'd1;rom[14]=4'd6;rom[15]=4'd4; rom[16]=4'd7;rom[17]=4'd3;
        rom[18]=4'd9;rom[19]=4'd0; rom[20]=4'd5;rom[21]=4'd2;rom[22]=4'd8;rom[23]=4'd1;
        // Row 3: 490268357149
        rom[24]=4'd4;rom[25]=4'd9;rom[26]=4'd0;rom[27]=4'd2; rom[28]=4'd6;rom[29]=4'd8;
        rom[30]=4'd3;rom[31]=4'd5;rom[32]=4'd7; rom[33]=4'd1; rom[34]=4'd4; rom[35]=4'd9; 
        // Row 4: 738514920673 
        rom[36]=4'd7; rom[37]=4'd3; rom[38]=4'd8; rom[39]=4'd5; rom[40]=4'd1; rom[41]=4'd4; 
        rom[42]=4'd9; rom[43]=4'd2; rom[44]=4'd0; rom[45]=4'd6; rom[46]=4'd7; rom[47]=4'd3; 
        // Row 5: 264087531924 
        rom[48]=4'd2; rom[49]=4'd6; rom[50]=4'd4; rom[51]=4'd0; rom[52]=4'd8; rom[53]=4'd7; 
        rom[54]=4'd5; rom[55]=4'd3; rom[56]=4'd1; rom[57]=4'd9; rom[58]=4'd2; rom[59]=4'd4; 
        // Row 6: 907352864190 
        rom[60]=4'd9; rom[61]=4'd0; rom[62]=4'd7; rom[63]=4'd3; rom[64]=4'd5; rom[65]=4'd2; 
        rom[66]=4'd8; rom[67]=4'd6; rom[68]=4'd4; rom[69]=4'd1; rom[70]=4'd9; rom[71]=4'd0; 
        // Row 7: 581649273058 
        rom[72]=4'd5; rom[73]=4'd8; rom[74]=4'd1; rom[75]=4'd6; rom[76]=4'd4; rom[77]=4'd9; 
        rom[78]=4'd2; rom[79]=4'd7; rom[80]=4'd3; rom[81]=4'd0; rom[82]=4'd5; rom[83]=4'd8; 
        // Row 8: 149270685314 
        rom[84]=4'd1; rom[85]=4'd4; rom[86]=4'd9; rom[87]=4'd2; rom[88]=4'd7; rom[89]=4'd0; 
        rom[90]=4'd6; rom[91]=4'd8; rom[92]=4'd5; rom[93]=4'd3; rom[94]=4'd1; rom[95]=4'd4; 
        // Row 9: 625831749062 
        rom[96]=4'd6; rom[97]=4'd2; rom[98]=4'd5; rom[99]=4'd8; rom[100]=4'd3; rom[101]=4'd1; 
        rom[102]=4'd7; rom[103]=4'd4; rom[104]=4'd9; rom[105]=4'd0; rom[106]=4'd6; rom[107]=4'd2; 
        // Row 10: 073956418207 
        rom[108]=4'd0; rom[109]=4'd7; rom[110]=4'd3; rom[111]=4'd9; rom[112]=4'd5; rom[113]=4'd6; 
        rom[114]=4'd4; rom[115]=4'd1; rom[116]=4'd8; rom[117]=4'd2; rom[118]=4'd0; rom[119]=4'd7; 
    end 

    // Synchronous Read
    wire [6:0] addr; 
    assign addr = x * 12 + y; 
    always @(posedge clk) begin 
        data_out <= rom[addr]; 
    end 
endmodule
