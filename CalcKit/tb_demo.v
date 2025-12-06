`timescale 1ns / 1ps

module tb_demo;

    // ============================================================
    // 1. Parameters & Signals
    // ============================================================
    parameter CLK_PERIOD = 10;           // 100MHz
    parameter BAUD_RATE  = 115200;
    parameter BIT_PERIOD = 1_000_000_000 / BAUD_RATE; 

    reg clk;
    reg rst_n;
    reg PC_Uart_rxd;
    wire PC_Uart_txd;
    
    reg [4:0] btn_pin; // btn[2] is Confirm
    reg [7:0] sw_pin;  // [7:5] Mode, [4:2] Op, [1:0] Slot
    reg [7:0] dip_pin;
    
    wire [15:0] led_pin;
    wire [7:0] seg_cs_pin;
    wire [7:0] seg_data_0_pin;
    wire [7:0] seg_data_1_pin;

    // ============================================================
    // 2. DUT
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
    // 3. Helpers
    // ============================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

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

    task send_num;
        input integer val;
        integer digit;
        integer temp_val;
        begin
            //$display("   > User types: %0d", val);
            if (val == 0) begin
                uart_send_byte(8'h30); 
            end else begin
                temp_val = val;
                // Handle simple 1-2 digit nums for demo
                if (temp_val >= 10) begin 
                    uart_send_byte((temp_val/10)+48); 
                    temp_val = temp_val%10; 
                end
                uart_send_byte(temp_val+48);
            end
            uart_send_byte(8'h20); // Space delimiter
        end
    endtask
    
    task press_confirm;
        begin
            //$display("   > User presses CONFIRM (Btn_C)");
            btn_pin[2] = 1;
            #200000; // 20ms
            btn_pin[2] = 0;
            #200000;
        end
    endtask

    // ============================================================
    // 4. Demo Scenario
    // ============================================================
    initial begin
        // Setup
        rst_n = 0; PC_Uart_rxd = 1; btn_pin = 0; sw_pin = 0; dip_pin = 0;
        #1000 rst_n = 1; #1000;

        $display("\n=================================================================");
        $display("   CS207 FPGA Matrix Calculator - Verification Demo");
        $display("=================================================================");

        // ------------------------------------------------------------
        // Part 1: Input Matrix A (2x3)
        // ------------------------------------------------------------
        $display("\n[老师/TA]: 请演示矩阵输入功能。输入一个 2x3 的矩阵 A。");
        $display("[学生]: 好的。");
        $display("[操作]: 1. 拨码 SW[7:5]=000 (Input Mode), SW[1:0]=00 (Slot A)");
        sw_pin[7:5] = 3'b000; sw_pin[1:0] = 2'b00;
        $display("[操作]: 2. 按下确认键进入输入状态");
        press_confirm();
        
        $display("[操作]: 3. 通过串口发送维度 2, 3");
        send_num(2); send_num(3);
        
        $display("[状态]: 数码管应显示 'InPut'，且正在等待数据...");
        
        $display("[操作]: 4. 发送数据: 1 2 3 4 5 6");
        send_num(1); send_num(2); send_num(3);
        send_num(4); send_num(5); send_num(6);
        
        #1000000;
        $display("[反馈]: 矩阵 A 输入完成。系统自动返回 IDLE。");

        // ------------------------------------------------------------
        // Part 2: Input Matrix B (2x3)
        // ------------------------------------------------------------
        $display("\n[老师/TA]: 很好。现在输入第二个矩阵 B，也是 2x3，全为 1。");
        $display("[学生]: 没问题。注意我要切换存储位置到 Slot B。");
        $display("[操作]: 1. 拨码 SW[1:0]=01 (Slot B)");
        sw_pin[1:0] = 2'b01;
        $display("[操作]: 2. 按下确认键");
        press_confirm();
        
        $display("[操作]: 3. 发送维度 2, 3");
        send_num(2); send_num(3);
        $display("[操作]: 4. 发送数据: 1 1 1 1 1 1");
        send_num(1); send_num(1); send_num(1);
        send_num(1); send_num(1); send_num(1);
        
        #1000000;
        $display("[反馈]: 矩阵 B 输入完成。");

        // ------------------------------------------------------------
        // Part 3: Matrix Display
        // ------------------------------------------------------------
        $display("\n[老师/TA]: 请展示刚才输入的矩阵 A，确认存储无误。");
        $display("[学生]: 好的，切换到展示模式。");
        $display("[操作]: 1. 拨码 SW[7:5]=010 (Display Mode)");
        sw_pin[7:5] = 3'b010;
        $display("[操作]: 2. 拨码 SW[1:0]=00 (Slot A)");
        sw_pin[1:0] = 2'b00;
        $display("[操作]: 3. 按下确认键触发打印");
        press_confirm();
        
        $display("[状态]: 正在通过串口打印矩阵 A...");
        #20000000; // Wait for print
        
        // ------------------------------------------------------------
        // Part 4: Matrix Calc (A + B)
        // ------------------------------------------------------------
        $display("\n[老师/TA]: 现在演示矩阵加法 A + B。");
        $display("[学生]: 进入计算模式。");
        $display("[操作]: 1. 拨码 SW[7:5]=011 (Calc Mode)");
        sw_pin[7:5] = 3'b011;
        $display("[操作]: 2. 按下确认键进入运算选择");
        press_confirm();
        
        $display("[操作]: 3. 拨码 SW[4:2]=000 (Add)");
        sw_pin[4:2] = 3'b000;
        $display("[状态]: 数码管应显示 'A' (Add)");
        
        $display("[操作]: 4. 按下确认键确认运算类型");
        press_confirm();
        
        $display("[操作]: 5. 按下确认键确认运算数 (默认 Slot A, B)");
        press_confirm();
        
        $display("[状态]: 系统正在计算并打印结果...");
        #30000000; // Wait for calc and print
        
        // ------------------------------------------------------------
        // Part 5: Error Handling
        // ------------------------------------------------------------
        $display("\n[老师/TA]: 如果运算数维度不匹配会怎样？比如 A(2x3) + 某个不匹配的矩阵。");
        $display("[学生]: 我来演示错误处理。我先输入一个 2x2 的矩阵 C 到 Slot C (ID 2)。");
        
        // Input C (2x2)
        sw_pin[7:5] = 3'b000; // Input
        sw_pin[1:0] = 2'b10;  // Slot C
        press_confirm();
        send_num(2); send_num(2); // 2x2
        send_num(9); send_num(9); send_num(9); send_num(9);
        #1000000;
        
        $display("[学生]: 现在尝试计算 A(2x3) + C(2x2)。这应该报错。");
        sw_pin[7:5] = 3'b011; // Calc
        press_confirm(); // Select Op
        sw_pin[4:2] = 3'b000; // Add
        press_confirm(); // Confirm Op
        
        // Hack: How to select A and C?
        // The current logic hardcodes Rd_Slot_A = 0, Rd_Slot_B = 1 in matrix_alu.v state machine?
        // Wait, matrix_alu.v logic:
        // S_READ_OP1: mem_rd_slot = SLOT_A;
        // S_READ_OP2: mem_rd_slot = SLOT_B;
        // It seems HARDCODED to Slot 0 and Slot 1.
        // So I cannot calculate A + C unless I move C to Slot B.
        // Let's simulate user overwriting Slot B with the 2x2 matrix.
        
        $display("[学生]: (注：当前系统默认计算 Slot A 和 Slot B，所以我覆盖 Slot B 为 2x2 矩阵)");
        sw_pin[7:5] = 3'b000; // Input
        sw_pin[1:0] = 2'b01;  // Slot B
        press_confirm();
        send_num(2); send_num(2); // 2x2
        send_num(8); send_num(8); send_num(8); send_num(8);
        #1000000;
        
        $display("[学生]: 现在 Slot A 是 2x3, Slot B 是 2x2。再次执行加法。");
        sw_pin[7:5] = 3'b011; // Calc
        press_confirm(); 
        sw_pin[4:2] = 3'b000; // Add
        press_confirm(); 
        press_confirm(); // Check
        
        $display("[状态]: 检测到维度不匹配！LED 应该亮起，数码管显示 'Err 10' 并倒数。");
        #50000000; // Wait 5s (Simulation time)
        
        $display("[老师/TA]: 好的，看到倒计时了。如果我在倒计时内修正了矩阵呢？");
        $display("[学生]: 我现在快速重新输入正确的 Slot B (2x3)，然后按确认。");
        
        // User "Quickly" inputs correct B
        sw_pin[7:5] = 3'b000; // Input
        sw_pin[1:0] = 2'b01;  // Slot B
        press_confirm();
        send_num(2); send_num(3); 
        send_num(1); send_num(1); send_num(1); send_num(1); send_num(1); send_num(1);
        #1000000;
        
        // Go back to Calc and Confirm (Retry)
        // Note: In real HW, user switches SW, inputs data, then switches back to Calc and presses Confirm.
        // My "Early Retry" logic in top.v/FSM detects 'calc_mat_conf' (Btn_C in Calc Mode).
        // So I need to switch SW back to Calc Mode and press Btn_C.
        sw_pin[7:5] = 3'b011; // Calc
        $display("[操作]: 修正完成后，按下确认键 (Early Retry)");
        press_confirm(); 
        
        $display("[状态]: 系统应重新检查并进入计算...");
        #30000000;

        // ------------------------------------------------------------
        // Part 6: Bonus Conv
        // ------------------------------------------------------------
        $display("\n[老师/TA]: 最后看下卷积功能。");
        $display("[学生]: 切换到 Bonus 模式。");
        sw_pin[7:5] = 3'b100; // Bonus
        $display("[操作]: 按下确认键");
        press_confirm();
        
        $display("[状态]: 数码管显示 'bonUS J'，串口输出卷积结果...");
        #50000000;
        
        $display("\n[学生]: 演示结束，谢谢老师！");
        $finish;
    end

    // Monitor UART to show "Screen"
    always @(posedge u_top.tx_start) begin
        //$display("   [UART OUTPUT]: %c", u_top.tx_data);
        $write("%c", u_top.tx_data);
    end

endmodule
