`timescale 1ns / 1ps

module tb_input_storage;

    reg clk;
    reg rst_n;
    reg rx;
    wire tx;
    
    wire [15:0] led;
    reg [4:0] btn;
    reg [7:0] sw;
    
    top uut (
        .sys_clk_in(clk),
        .sys_rst_n(rst_n),
        .PC_Uart_rxd(rx),
        .PC_Uart_txd(tx),
        .led_pin(led),
        .btn_pin(btn),
        .sw_pin(sw),
        .dip_pin(8'b0),
        .seg_cs_pin(),
        .seg_data_0_pin(),
        .seg_data_1_pin()
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz
    end
    
    // UART Helper
    task send_byte;
        input [7:0] data;
        integer i;
        begin
            rx = 0; // Start bit
            #8680; // 115200 baud -> ~8680ns bit period
            for (i=0; i<8; i=i+1) begin
                rx = data[i];
                #8680;
            end
            rx = 1; // Stop bit
            #8680;
            #10000; // Inter-byte delay
        end
    endtask
    
    task send_str;
        input [127:0] str; // Max 16 chars
        input integer len;
        integer k;
        reg [7:0] char;
        begin
            // Strings are right-aligned in Verilog, so we need to be careful
            // Or just send manually in tests.
        end
    endtask
    
    task send_num_str;
        input [7:0] d1;
        begin
            send_byte(d1);
            send_byte(" "); // Delimiter
        end
    endtask

    initial begin
        // Init
        rst_n = 0;
        rx = 1;
        btn = 0;
        sw = 0; // Input Mode
        #100;
        rst_n = 1;
        #100;
        
        // 1. Enter Input Mode
        $display("--- Test 1: Enter Input Mode ---");
        btn[2] = 1; // Confirm
        #20 btn[2] = 0;
        #100;
        
        // 2. Send Dimensions 2 3
        $display("--- Test 2: Send Dims 2x3 ---");
        send_byte("2");
        send_byte(" ");
        #1000;
        send_byte("3");
        send_byte(" "); // Trigger N processing
        
        // Wait for clear mem (approx 25 cycles)
        #1000;
        
        // 3. Send Data 1 2 3 4 5 6
        $display("--- Test 3: Send Data ---");
        send_byte("1"); send_byte(" ");
        send_byte("2"); send_byte(" ");
        send_byte("3"); send_byte(" ");
        send_byte("4"); send_byte(" ");
        send_byte("5"); send_byte(" ");
        send_byte("6"); send_byte(" ");
        
        #5000;
        
        // Verify Memory Content (Backdoor)
        // Spec 2x3 -> Idx (2-1)*5 + (3-1) = 5+2 = 7.
        // First matrix -> Spec 7, Count 0 -> Slot 0.
        // Phys Slot = 7*2 + 0 = 14.
        // Addr = 14*32 = 448.
        if (uut.u_mem.mem[448] === 1) $display("PASS: Mem[0] = 1");
        else $display("FAIL: Mem[0] = %d", uut.u_mem.mem[448]);
        
        // 4. Send Second Matrix 2x3 (Should go to slot 1)
        $display("--- Test 4: Second Matrix 2x3 ---");
        // Re-enter Input Mode (FSM returns to IDLE after finish)
        // Need to check if FSM is IDLE.
        // Assuming it is.
        btn[2] = 1;
        #20 btn[2] = 0;
        #100;
        
        send_byte("2"); send_byte(" ");
        send_byte("3"); send_byte(" ");
        #1000;
        
        send_byte("9"); send_byte(" ");
        send_byte("9"); send_byte(" ");
        send_byte("9"); send_byte(" ");
        send_byte("9"); send_byte(" ");
        send_byte("9"); send_byte(" ");
        send_byte("9"); send_byte(" ");
        
        #2000;
        // Verify Second Slot
        // Phys Slot = 7*2 + 1 = 15.
        // Addr = 15*32 = 480.
        if (uut.u_mem.mem[480] === 9) $display("PASS: Mem[Slot2] = 9");
        else $display("FAIL: Mem[Slot2] = %d", uut.u_mem.mem[480]);
        
        // 5. Send Third Matrix 2x3 (Should replace Slot 0, ID 1 becomes Slot 1)
        $display("--- Test 5: FIFO Replace ---");
        btn[2] = 1; #20 btn[2] = 0; #100;
        
        send_byte("2"); send_byte(" ");
        send_byte("3"); send_byte(" ");
        #1000;
        
        send_byte("8"); send_byte(" ");
        send_byte("8"); send_byte(" ");
        send_byte("8"); send_byte(" ");
        send_byte("8"); send_byte(" ");
        send_byte("8"); send_byte(" ");
        send_byte("8"); send_byte(" ");
        
        #2000;
        // Old ID 1 was at Slot 14. ID 2 was at Slot 15.
        // New ID 1 should be Slot 15. New ID 2 should be Slot 14 (Overwritten).
        // Check Slot 14 (Phys 448) -> Should be 8.
        if (uut.u_mem.mem[448] === 8) $display("PASS: FIFO Replace Slot 0 -> 8");
        else $display("FAIL: Mem[448] = %d", uut.u_mem.mem[448]);
        
        // Check Slot 15 (Phys 480) -> Should still be 9.
        if (uut.u_mem.mem[480] === 9) $display("PASS: FIFO Keep Slot 1 -> 9");
        else $display("FAIL: Mem[480] = %d", uut.u_mem.mem[480]);
        
        // 6. Test Padding (2x2, Input "1 2", stop)
        $display("--- Test 6: Padding ---");
        btn[2] = 1; #20 btn[2] = 0; #100;
        
        send_byte("2"); send_byte(" ");
        send_byte("2"); send_byte(" "); // 2x2 -> Spec (1)*5+1 = 6. Phys 12.
        #1000;
        
        send_byte("7"); send_byte(" ");
        send_byte("7"); send_byte(" ");
        // Stop sending. Force finish via Btn C.
        #5000;
        btn[2] = 1; #20 btn[2] = 0;
        #100;
        
        // Check Phys Slot 12 (12*32 = 384)
        if (uut.u_mem.mem[384] === 7) $display("PASS: Val 1 = 7");
        if (uut.u_mem.mem[384+1] === 7) $display("PASS: Val 2 = 7");
        if (uut.u_mem.mem[384+2] === 0) $display("PASS: Val 3 = 0 (Padded)");
        else $display("FAIL: Val 3 = %d", uut.u_mem.mem[384+2]);
        
        $finish;
    end

endmodule
