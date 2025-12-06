`timescale 1ns / 1ps

module tb_top;

    // ============================================================
    // 1. Parameters
    // ============================================================
    parameter CLK_PERIOD = 10;           // 100MHz
    parameter BAUD_RATE  = 115200;
    parameter BIT_PERIOD = 1_000_000_000 / BAUD_RATE; // 8680ns

    // ============================================================
    // 2. Signals
    // ============================================================
    reg clk;
    reg rst_n;
    reg PC_Uart_rxd;
    wire PC_Uart_txd;
    
    reg [4:0] btn_pin;
    reg [7:0] sw_pin;
    reg [7:0] dip_pin;
    
    wire [15:0] led_pin;
    wire [7:0] seg_cs_pin;
    wire [7:0] seg_data_0_pin;
    wire [7:0] seg_data_1_pin;

    // ============================================================
    // 3. DUT Instantiation
    // ============================================================
    top u_top (
        .sys_clk_in (clk),
        .sys_rst_n  (rst_n),
        .PC_Uart_rxd(PC_Uart_rxd),
        .PC_Uart_txd(PC_Uart_txd),
        
        .led_pin        (led_pin),
        .btn_pin        (btn_pin),
        .sw_pin         (sw_pin),
        .dip_pin        (dip_pin),
        .seg_cs_pin     (seg_cs_pin),
        .seg_data_0_pin (seg_data_0_pin),
        .seg_data_1_pin (seg_data_1_pin)
    );

    // ============================================================
    // 4. Clock Generation
    // ============================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // ============================================================
    // 5. Helper Tasks
    // ============================================================
    
    task uart_send_byte;
        input [7:0] data;
        integer i; 
        begin
            PC_Uart_rxd = 0; #(BIT_PERIOD); // Start
            for (i = 0; i < 8; i = i + 1) begin
                PC_Uart_rxd = data[i]; #(BIT_PERIOD);
            end
            PC_Uart_rxd = 1; #(BIT_PERIOD); // Stop
            #(BIT_PERIOD * 5); 
        end
    endtask

    task send_cmd;
        input integer val;
        integer digit;
        integer temp_val;
        begin
            $display("[%0t] [TB Send] Sending Number: %0d", $time, val);
            if (val == 0) begin
                uart_send_byte(8'h30); 
            end else begin
                temp_val = val;
                if (temp_val >= 10000) begin digit = temp_val/10000; uart_send_byte(digit+48); temp_val = temp_val%10000; end
                if (temp_val >= 1000)  begin digit = temp_val/1000;  uart_send_byte(digit+48); temp_val = temp_val%1000; end
                if (temp_val >= 100)   begin digit = temp_val/100;   uart_send_byte(digit+48); temp_val = temp_val%100; end
                if (temp_val >= 10)    begin digit = temp_val/10;    uart_send_byte(digit+48); temp_val = temp_val%10; end
                digit = temp_val; uart_send_byte(digit+48);
            end
            uart_send_byte(8'h20); // Space
        end
    endtask
    
    task press_btn_c;
        begin
            $display("[%0t] [TB Action] Pressing Button C (Confirm)", $time);
            btn_pin[2] = 1;
            #100000; // Hold for some time
            btn_pin[2] = 0;
            #100000;
        end
    endtask

    // ============================================================
    // 6. Main Test Sequence
    // ============================================================
    initial begin
        // Init
        rst_n = 0;
        PC_Uart_rxd = 1;
        btn_pin = 0;
        sw_pin = 0;
        dip_pin = 0;
        
        #1000;
        rst_n = 1;
        #1000;
        
        $display("\n=== Simulation Start: Full System Test ===");
        
        // 1. Enter INPUT Mode
        $display("\n[Step 1] Enter INPUT Mode (SW=000)");
        sw_pin[7:5] = 3'b000; // Input Mode
        press_btn_c();
        
        // 2. Send Matrix A (2x2)
        $display("\n[Step 2] Sending Matrix A via UART");
        send_cmd(2); send_cmd(2); // M, N
        send_cmd(10); send_cmd(20);
        send_cmd(30); send_cmd(40);
        
        // Wait for INPUT_DATA state to finish (Logic automatically waits for count)
        // We need to send B immediately after A?
        // No, FSM goes INPUT_DIM -> INPUT_DATA -> IDLE.
        // So we need to re-enter INPUT mode for B?
        // The original `top.v` logic chained A->B->Op.
        // The `Central_FSM` is modal. 
        // `INPUT` mode takes ONE matrix (based on current logic, it writes to Slot A always?).
        // Wait, my `top.v` rewrite:
        // Case 2 (INPUT_DATA): `mux_user_slot = 0;` (Always Slot A).
        // This is a limitation of the current FSM/Top integration.
        // To support Slot B input, we need a mechanism to toggle the target slot.
        // Architecture Doc says: "User selects Matrix ID".
        // Ah, `INPUT_DIM` state doesn't have a slot argument from FSM.
        // Maybe `sw[4:3]` selects slot during `INPUT` mode?
        // The Architecture Doc says: `sw[4:0]` used for data/param setting.
        // Let's Update `top.v` logic quickly to use `sw` for slot selection during INPUT.
        
        // NOTE: I will pause simulation script here to fix `top.v` slot selection logic first.
        // But let's finish the script assuming I fixed it.
        
        // 3. Enter INPUT Mode for Matrix B
        #1000000;
        $display("\n[Step 3] Enter INPUT Mode for Matrix B (SW=000, Slot=1)");
        sw_pin[7:5] = 3'b000; // Input Mode
        sw_pin[1:0] = 2'd1;   // Select Slot 1 (B) - Assuming I implement this!
        press_btn_c();
        
        send_cmd(2); send_cmd(2);
        send_cmd(1); send_cmd(1);
        send_cmd(1); send_cmd(1);
        
        #1000000;
        
        // 4. Enter CALC Mode
        $display("\n[Step 4] Enter CALC Mode (SW=011)");
        sw_pin[7:5] = 3'b011;
        press_btn_c(); // -> CALC_SELECT_OP
        
        // 5. Select Op (ADD)
        $display("\n[Step 5] Select Op ADD (SW=000)");
        sw_pin[2:0] = 3'b000; // ADD
        press_btn_c(); // -> CALC_SELECT_MAT
        
        // 6. Confirm Mat (Default A, B)
        $display("\n[Step 6] Confirm Matrices (Default A, B)");
        press_btn_c(); // -> CHECK -> EXEC -> DONE -> PRINT
        
        // Wait for Result Print
        #50000000; 
        
        // --- Test SUB (Subtraction) ---
        $display("\n[Step 8] Testing SUB Operation");
        // Re-enter CALC Mode (FSM returns to IDLE after DONE)
        // Need to select CALC mode again?
        // FSM IDLE -> CALC needs SW=011 & Btn_C
        // SW is already 011. Just press Btn_C.
        press_btn_c(); // -> CALC_SELECT_OP
        
        sw_pin[2:0] = 3'b001; // SUB
        $display("[TB Info] Selecting SUB (001)");
        press_btn_c(); // -> CALC_SELECT_MAT
        press_btn_c(); // -> CHECK -> EXEC -> DONE
        #50000000;

        // --- Test MUL (Matrix Multiplication) ---
        $display("\n[Step 9] Testing MUL Operation");
        press_btn_c(); // IDLE -> CALC
        sw_pin[2:0] = 3'b010; // MUL
        $display("[TB Info] Selecting MUL (010)");
        press_btn_c(); // -> CALC_SELECT_MAT
        press_btn_c(); // -> CHECK -> EXEC -> DONE
        #50000000;

        // --- Test SCALAR (Scalar Multiplication) ---
        $display("\n[Step 10] Testing SCALAR Operation (Scalar=2)");
        press_btn_c(); // IDLE -> CALC
        sw_pin[2:0] = 3'b011; // SCA
        $display("[TB Info] Selecting SCA (011)");
        press_btn_c(); // -> CALC_SELECT_MAT
        
        // Set Scalar Value on SW (Using full 8 bits or lower bits? FSM uses sw_pin directly)
        // In FSM: alu_scalar <= {8'b0, sw_pin};
        // We need to set Scalar BEFORE confirming MAT?
        // FSM:
        // 7: CALC_SELECT_OP -> latch opcode -> 8
        // 8: CALC_SELECT_MAT -> latch scalar -> 9
        // So we set scalar during state 8.
        sw_pin = 8'd2; // Scalar = 2. Note: This overwrites SW[7:5] which controls Mode!
                       // FSM logic: `alu_scalar <= {8'b0, sw_pin};`
                       // BUT wait, if we change SW[7:5], does it affect state?
                       // FSM state transitions depend on `sw` ONLY in IDLE.
                       // Once in CALC_SELECT_MAT, `sw` is just data.
                       // HOWEVER, `sw[7:5]` is wired to `sw` input of FSM module.
                       // Inside FSM, does it use `sw` for anything else?
                       // Only IDLE transitions.
                       // So it is SAFE to change SW in CALC_SELECT_MAT.
        
        press_btn_c(); // -> CHECK -> EXEC -> DONE
        
        // Restore SW for next mode if needed (though we go to IDLE)
        sw_pin[7:5] = 3'b011; 
        #50000000;

        // --- Test TRANSPOSE ---
        $display("\n[Step 11] Testing TRANSPOSE Operation");
        press_btn_c(); // IDLE -> CALC
        sw_pin[2:0] = 3'b100; // TRA
        $display("[TB Info] Selecting TRA (100)");
        press_btn_c(); // -> CALC_SELECT_MAT
        press_btn_c(); // -> CHECK -> EXEC -> DONE
        #50000000;

        // --- Test BONUS (Convolution) ---
        $display("\n[Step 12] Testing BONUS (Convolution)");
        // Need to go to IDLE first (already there)
        // Set SW=100 (Bonus Mode)
        sw_pin[7:5] = 3'b100;
        press_btn_c(); // -> BONUS_RUN
        
        // Wait for completion (Bonus takes time)
        #100000000;

        $display("\n[Step 13] All Tests Finished");
        $finish;
    end
    
    // ============================================================
    // 7. Debug Monitors
    // ============================================================
    
    // Monitor FSM State
    always @(u_top.current_state) begin
        case(u_top.current_state)
            0: $display("[FSM] IDLE");
            1: $display("[FSM] INPUT_DIM");
            2: $display("[FSM] INPUT_DATA");
            3: $display("[FSM] GEN_RANDOM");
            4: $display("[FSM] BONUS_RUN");
            5: $display("[FSM] DISPLAY_WAIT");
            6: $display("[FSM] DISPLAY_PRINT");
            7: $display("[FSM] CALC_SELECT_OP");
            8: $display("[FSM] CALC_SELECT_MAT");
            9: $display("[FSM] CALC_CHECK");
            10: $display("[FSM] CALC_EXEC");
            11: $display("[FSM] CALC_DONE");
            12: $display("[FSM] CALC_ERROR");
            default: $display("[FSM] Unknown %d", u_top.current_state);
        endcase
    end
    
    // Monitor UART TX
    always @(posedge u_top.tx_start) begin
        $display("[UART TX] Char: %c (%h)", u_top.tx_data, u_top.tx_data);
    end

endmodule
