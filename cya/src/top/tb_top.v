`timescale 1ns / 1ps

module tb_top;

    // ============================================================
    // 1. 参数定义
    // ============================================================
    parameter CLK_PERIOD = 10;           // 100MHz
    parameter BAUD_RATE  = 115200;
    parameter BIT_PERIOD = 1_000_000_000 / BAUD_RATE; // 8680ns

    // ============================================================
    // 2. 信号定义
    // ============================================================
    reg clk;
    reg rst_n;
    reg PC_Uart_rxd;      // DUT 接收引脚
    wire PC_Uart_txd;     // DUT 发送引脚
    wire done;            // DUT 完成信号

    // --- 调试信号 (连接到 top 模块的调试输出) ---
    wire [4:0]  debug_top_state;
    wire [15:0] debug_parser_number_out;
    wire        debug_parser_number_valid;
    wire [3:0]  debug_alu_state;
    wire [2:0]  debug_alu_i;
    wire [2:0]  debug_alu_j;
    wire [15:0] debug_mem_rd_data_c_val;
    wire        debug_mem_read_c_req;

    // --- DUT 额外 IO 端口 (连接到常量或未连接) ---
    wire [15:0] dummy_led_pin;
    wire [4:0]  dummy_btn_pin;
    wire [7:0]  dummy_sw_pin;
    wire [7:0]  dummy_dip_pin;
    wire [7:0]  dummy_seg_cs_pin;
    wire [7:0]  dummy_seg_data_0_pin;
    wire [7:0]  dummy_seg_data_1_pin;


    // ============================================================
    // 3. 实例化 DUT
    // ============================================================
    top u_top (
        .sys_clk_in (clk),
        .sys_rst_n  (rst_n),
        .PC_Uart_rxd(PC_Uart_rxd),
        .PC_Uart_txd(PC_Uart_txd),
        .done       (done),
        
        // --- 连接开发板 IO 端口 ---
        .led_pin        (dummy_led_pin),
        .btn_pin        (dummy_btn_pin),
        .sw_pin         (dummy_sw_pin),
        .dip_pin        (dummy_dip_pin),
        .seg_cs_pin     (dummy_seg_cs_pin),
        .seg_data_0_pin (dummy_seg_data_0_pin),
        .seg_data_1_pin (dummy_seg_data_1_pin),

        // --- 连接调试输出到 tb_top 的 wire ---
        .debug_top_state         (debug_top_state),
        .debug_parser_number_out (debug_parser_number_out),
        .debug_parser_number_valid (debug_parser_number_valid),
        .debug_alu_state         (debug_alu_state),
        .debug_alu_i             (debug_alu_i),
        .debug_alu_j             (debug_alu_j),
        .debug_mem_rd_data_c_val (debug_mem_rd_data_c_val),
        .debug_mem_read_c_req    (debug_mem_read_c_req)
    );

    // ============================================================
    // 4. 时钟生成
    // ============================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // ============================================================
    // 5. 辅助任务：UART 发送一个字节
    // ============================================================
    task uart_send_byte;
        input [7:0] data;
        integer i; 
        begin
            // Start Bit (Low)
            PC_Uart_rxd = 0; 
            #(BIT_PERIOD);
            
            // Data Bits (LSB First)
            for (i = 0; i < 8; i = i + 1) begin
                PC_Uart_rxd = data[i]; 
                #(BIT_PERIOD);
            end
            
            // Stop Bit (High)
            PC_Uart_rxd = 1; 
            #(BIT_PERIOD);
            
            // 字节间停顿 (给 DUT 留点处理时间)
            #(BIT_PERIOD * 5); 
        end
    endtask

    // ============================================================
    // 6. 辅助任务：发送命令 (发送数字 ASCII + 空格符 ' ')
    // ============================================================
    task send_cmd;
        input integer val; // 允许发送非ASCII字符的数值
        integer digit;
        integer temp_val;
        begin
            $display("[%0t] [TB Send] Sending Number: %0d", $time, val);
            if (val == 0) begin
                uart_send_byte(8'h30); // 发送 '0'
            end else begin
                temp_val = val;
                // 计算位数，从高位开始发送
                if (temp_val >= 10000) begin
                    digit = temp_val / 10000; uart_send_byte(digit + 8'h30); temp_val = temp_val % 10000;
                end
                if (temp_val >= 1000) begin
                    digit = temp_val / 1000; uart_send_byte(digit + 8'h30); temp_val = temp_val % 1000;
                end
                if (temp_val >= 100) begin
                    digit = temp_val / 100; uart_send_byte(digit + 8'h30); temp_val = temp_val % 100;
                end
                if (temp_val >= 10) begin
                    digit = temp_val / 10; uart_send_byte(digit + 8'h30); temp_val = temp_val % 10;
                end
                digit = temp_val; uart_send_byte(digit + 8'h30);
            end
            uart_send_byte(8'h20); // 发送空格分隔符
        end
    endtask

    // ============================================================
    // 7. 主测试流程
    // ============================================================
    initial begin
        rst_n = 0;
        PC_Uart_rxd = 1; 
        #1000;
        rst_n = 1;
        #1000;

        $display("\n=== Simulation Start: Matrix Addition Test ===");
        
        // --- 发送 A (2x2) = [[10,20],[-30,40]] ---
        $display("[%0t] [TB Info] Setting up Matrix A (2x2) = [[10,20],[-30,40]]", $time);
        send_cmd(2);  // A_m = 2
        send_cmd(2);  // A_n = 2
        send_cmd(10); // Data A[0][0] = 10
        send_cmd(20); // Data A[0][1] = 20
        send_cmd(30); // Data A[1][0] = -30 (这里因为 cmd_parser 只能解析正数，ALU 预期接收正数，我们假定输入是绝对值，在ALU内处理符号)
                     // **重要提示：cmd_parser 只能解析正数。如需输入负数，cmd_parser需修改**
        send_cmd(40); // Data A[1][1] = 40

        // --- 发送 B (2x2) = [[1,1],[1,1]] ---
        $display("[%0t] [TB Info] Setting up Matrix B (2x2) = [[1,1],[1,1]]", $time);
        send_cmd(2); // B_m = 2
        send_cmd(2); // B_n = 2
        send_cmd(1); // Data B[0][0] = 1
        send_cmd(1); // Data B[0][1] = 1
        send_cmd(1); // Data B[1][0] = 1
        send_cmd(1); // Data B[1][1] = 1

        // --- 发送 Opcode (0 for ADD) ---
        $display("[%0t] [TB Info] Sending Opcode ADD (0)", $time);
        send_cmd(0); 

        // --- 等待结果 ---
        $display("[%0t] [TB Info] Waiting for DONE...", $time);
        
        fork : wait_block
            begin
                wait(done);
                $display("\n[%0t] [TB Success] DONE signal received!", $time);
                disable wait_block;
            end
            begin
                #500000000; // 增加超时时间到 500ms，以防复杂运算
                $display("\n[%0t] [TB Error] Timeout! State machine stuck or calculation too long.", $time);
                $finish;
            end
        join

        #1000;
        $display("[%0t] Simulation Finished.", $time);
        $finish;
    end

    // ============================================================
    // 8. 深度调试监视器 (Deep Debug Monitor)
    // ============================================================
    
    // [调试层 1] 监视 UART 物理层接收 (u_uart_rx 输出)
    always @(posedge clk) begin
        if (u_top.u_uart_rx.valid) begin // 注意这里直接访问了 u_uart_rx 实例
            $display("[%0t] [DUT Debug] UART RX Valid! Data: Hex %h (Char '%c')", 
                     $time, u_top.u_uart_rx.data, u_top.u_uart_rx.data);
        end
    end

    // [调试层 2] 监视 Parser 解析结果 (u_cmd_parser 输出)
    always @(posedge clk) begin
        if (debug_parser_number_valid) begin
            $display("[%0t] [DUT Debug] Parser Output Valid! Number=%0d, Top State=%0d", 
                     $time, debug_parser_number_out, debug_top_state);
        end
    end

    // [调试层 3] 监视 Top 状态机
    reg [4:0] prev_top_state;
    initial prev_top_state = 5'hF; 
    always @(posedge clk) begin
        if (debug_top_state != prev_top_state) begin
            case (debug_top_state)
                5'd0:  $display("[%0t] [TopState] -> ST_IDLE", $time);
                5'd1:  $display("[%0t] [TopState] -> ST_RECV_A_M", $time);
                5'd2:  $display("[%0t] [TopState] -> ST_RECV_A_N", $time);
                5'd3:  $display("[%0t] [TopState] -> ST_RECV_A_DATA", $time);
                5'd4:  $display("[%0t] [TopState] -> ST_RECV_B_M", $time);
                5'd5:  $display("[%0t] [TopState] -> ST_RECV_B_N", $time);
                5'd6:  $display("[%0t] [TopState] -> ST_RECV_B_DATA", $time);
                5'd7:  $display("[%0t] [TopState] -> ST_RECV_OPCODE", $time);
                5'd8:  $display("[%0t] [TopState] -> ST_RECV_SCALAR", $time);
                5'd9:  $display("[%0t] [TopState] -> ST_START_ALU", $time);
                5'd10: $display("[%0t] [TopState] -> ST_WAIT_ALU", $time);
                5'd11: $display("[%0t] [TopState] -> ST_PREP_READ_MEM", $time);
                5'd12: $display("[%0t] [TopState] -> ST_READ_RESULT_MEM", $time);
                5'd13: $display("[%0t] [TopState] -> ST_PREP_ASCII", $time);     
                5'd14: $display("[%0t] [TopState] -> ST_SEND_SIGN", $time);      
                5'd15: $display("[%0t] [TopState] -> ST_SEND_DIGIT", $time);     
                5'd16: $display("[%0t] [TopState] -> ST_SEND_DELIMITER", $time); 
                5'd17: $display("[%0t] [TopState] -> ST_DONE_STATE", $time);     
                default: $display("[%0t] [TopState] -> %0d (UNKNOWN)", $time, debug_top_state);
            endcase
            prev_top_state = debug_top_state;
        end
    end

    // [调试层 4] 监视 Top 模块读取内存结果 (从 C 槽) - 精简后只在读取到数据时打印
    always @(posedge clk) begin
        if (debug_mem_read_c_req && debug_top_state == u_top.ST_READ_RESULT_MEM) begin 
            $display("[%0t] [TOP_DBG_MEM] Top read C[%0d][%0d] = %0d (0x%h). Buffer=%0d.",
                     $time, u_top.send_row, u_top.send_col, debug_mem_rd_data_c_val, debug_mem_rd_data_c_val, 
                     u_top.result_data_buffer); // u_top.result_data_buffer 会是 user_rd_data 在下一拍的值
        end
    end

    // [调试层 5] 监视 ALU 状态和循环变量
    reg [3:0] prev_alu_state;
    initial prev_alu_state = 4'hF;
    always @(posedge clk) begin
        if (debug_alu_state != prev_alu_state) begin
            $display("[%0t] [ALU_STATE_DBG] ALU State changed to: %0d (i=%0d, j=%0d, k=%0d)", $time, debug_alu_state, debug_alu_i, debug_alu_j, u_top.u_matrix_alu.k);
            prev_alu_state = debug_alu_state;
        end
    end

    // [调试层 6] 监视 Top 模块的 ASCII 转换过程 (新增)
    always @(posedge clk) begin
        if (debug_top_state == u_top.ST_PREP_ASCII) begin
             $display("[%0t] [TOP_DBG_ASCII] Result %0d (0x%h) -> is_negative=%0d. Digits: %0d%0d%0d%0d%0d. digit_cnt=%0d. send_idx_start=%0d.",
                      $time, u_top.result_data_buffer, u_top.result_data_buffer, u_top.is_negative,
                      u_top.digit_buf[4], u_top.digit_buf[3], u_top.digit_buf[2], u_top.digit_buf[1], u_top.digit_buf[0],
                      u_top.digit_cnt, u_top.send_digit_idx);
        end else if (debug_top_state == u_top.ST_SEND_SIGN && u_top.tx_start) begin
             $display("[%0t] [TOP_DBG_ASCII] Sending sign (ASCII: 0x%h / '%c') for value %0d.",
                      $time, u_top.tx_data, u_top.tx_data, u_top.result_data_buffer);
        end else if (debug_top_state == u_top.ST_SEND_DIGIT && u_top.tx_start) begin
             $display("[%0t] [TOP_DBG_ASCII] Sending digit %0d (ASCII: 0x%h / '%c') for value %0d.",
                      $time, u_top.digit_buf[u_top.send_digit_idx], u_top.tx_data, u_top.tx_data, u_top.result_data_buffer);
        end
    end

     // [调试层 7] 监视 UART 发送 (结果回传) - 监控原始码和ASCII转换
    reg [7:0] rx_captured_byte;
    reg [7:0] tx_byte_count; // 用于计数发送的字节
    integer ascii_idx; // 用于构建ASCII字符串

    parameter STRING_MAX_LEN = 128;
    reg [8*STRING_MAX_LEN-1:0] received_ascii_string;
    
    initial begin
        tx_byte_count = 0;
        received_ascii_string = {8*STRING_MAX_LEN{1'b0}}; // 清空"字符串"
        forever begin
            @(negedge PC_Uart_txd); // 检测起始位
            #(BIT_PERIOD + BIT_PERIOD/2); // 采样数据位的中间
            
            rx_captured_byte[0] = PC_Uart_txd; #(BIT_PERIOD);
            rx_captured_byte[1] = PC_Uart_txd; #(BIT_PERIOD);
            rx_captured_byte[2] = PC_Uart_txd; #(BIT_PERIOD);
            rx_captured_byte[3] = PC_Uart_txd; #(BIT_PERIOD);
            rx_captured_byte[4] = PC_Uart_txd; #(BIT_PERIOD);
            rx_captured_byte[5] = PC_Uart_txd; #(BIT_PERIOD);
            rx_captured_byte[6] = PC_Uart_txd; #(BIT_PERIOD);
            rx_captured_byte[7] = PC_Uart_txd; #(BIT_PERIOD);
            
            tx_byte_count = tx_byte_count + 1;
            
            // 尝试将字节附加到ASCII字符串
            if (rx_captured_byte >= 8'h20 && rx_captured_byte <= 8'h7E) begin // 可打印ASCII范围
                received_ascii_string = {received_ascii_string, rx_captured_byte};
            end else begin
                // 如果是非可打印字符，用问号代替
                received_ascii_string = {received_ascii_string, "?"}; 
            end

            $display("[%0t] [UART Output] Byte %0d Recv: Hex %h (Char '%c'). Current ASCII String: \"%s\"", 
                     $time, tx_byte_count, rx_captured_byte, rx_captured_byte, received_ascii_string);
        end
    end


endmodule
