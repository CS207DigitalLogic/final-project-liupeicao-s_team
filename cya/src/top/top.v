// top.v
// 顶层：通过 UART 接收矩阵参数与数据 -> matrix_mem 存储 -> matrix_alu 运算 -> UART 发送结果

`timescale 1ns/1ps

module top (
    input  wire sys_clk_in,       // 开发板系统时钟 (例如 100 MHz)
    input  wire sys_rst_n,        // 开发板系统复位 (低电平有效)

    input  wire PC_Uart_rxd,      // PC 串口接收引脚
    output wire PC_Uart_txd,      // PC 串口发送引脚

    // --- 开发板 IO 端口 ---
    output wire [15:0] led_pin,    // 16个LED
    input  wire [4:0]  btn_pin,    // 5个按键（这里没用到）
    input  wire [7:0]  sw_pin,     // 8个拨码开关 (sw0-sw7)
    input  wire [7:0]  dip_pin,    // 8个拨码开关 (sw8-sw15)
    output wire [7:0]  seg_cs_pin, // 8个数码管位选
    output wire [7:0]  seg_data_0_pin, // 数码管段选0
    output wire [7:0]  seg_data_1_pin  // 数码管段选1

    // --- 调试端口已移除 ---
    // output wire [4:0]  debug_top_state,
    // output wire [15:0] debug_parser_number_out,
    // output wire        debug_parser_number_valid,
    // output wire [3:0]  debug_alu_state,
    // output wire [2:0]  debug_alu_i,
    // output wire [2:0]  debug_alu_j,
    // output wire [15:0] debug_mem_rd_data_c_val,
    // output wire        debug_mem_read_c_req,
    // output wire        done
);

    // ============================================================
    // 0. 时钟 / 复位 / UART 物理层映射
    // ============================================================
    wire clk  = sys_clk_in;
    wire rst_n = sys_rst_n;

    wire uart_rx_internal = PC_Uart_rxd;
    wire uart_tx_internal;
    assign PC_Uart_txd = uart_tx_internal;

    // ============================================================
    // 1. UART 接收 + 命令解析
    // ============================================================
    wire [7:0] rx_data;
    wire       rx_valid;

    uart_rx #(
        .CLK_FREQ (100_000_000),
        .BAUD_RATE(115200)
    ) u_uart_rx (
        .clk   (clk),
        .rst_n (rst_n),
        .rx    (uart_rx_internal),
        .data  (rx_data),
        .valid (rx_valid)
    );

    wire [15:0] number_out;
    wire        number_valid;

    cmd_parser u_cmd_parser (
        .clk        (clk),
        .rst_n      (rst_n),
        .rx_data    (rx_data),
        .rx_valid   (rx_valid),
        .number_out (number_out),
        .number_valid(number_valid)
    );

    // ============================================================
    // 2. UART 发送
    // ============================================================
    reg  [7:0] tx_data;
    reg        tx_start;
    wire       tx_busy;

    uart_tx #(
        .CLK_FREQ (100_000_000),
        .BAUD_RATE(115200)
    ) u_uart_tx (
        .clk   (clk),
        .rst_n (rst_n),
        .data  (tx_data),
        .start (tx_start),
        .tx    (uart_tx_internal),
        .busy  (tx_busy)
    );

    // ============================================================
    // 3. Matrix Memory
    // ============================================================
    // user 端
    reg  [1:0]  user_slot_idx;
    reg  [2:0]  user_row;
    reg  [2:0]  user_col;
    reg  [15:0] user_data;
    reg         user_we;
    reg  [2:0]  user_dim_m;
    reg  [2:0]  user_dim_n;
    reg         user_dim_we;
    wire [15:0] user_rd_data;

    // alu 端
    wire [1:0]  alu_rd_slot;
    wire [2:0]  alu_rd_row;
    wire [2:0]  alu_rd_col;
    wire [15:0] alu_rd_data;
    wire [2:0]  alu_current_m;
    wire [2:0]  alu_current_n;

    wire [1:0]  alu_wr_slot;
    wire [2:0]  alu_wr_row;
    wire [2:0]  alu_wr_col;
    wire [15:0] alu_wr_data;
    wire        alu_wr_we;
    wire [2:0]  alu_res_m;
    wire [2:0]  alu_res_n;
    wire        alu_dim_we;

    matrix_mem u_matrix_mem (
        .clk         (clk),
        .rst_n       (rst_n),

        // user 端
        .user_slot_idx(user_slot_idx),
        .user_row     (user_row),
        .user_col     (user_col),
        .user_data    (user_data),
        .user_we      (user_we),
        .user_dim_m   (user_dim_m),
        .user_dim_n   (user_dim_n),
        .user_dim_we  (user_dim_we),
        .user_rd_data (user_rd_data),

        // alu 读
        .alu_rd_slot  (alu_rd_slot),
        .alu_rd_row   (alu_rd_row),
        .alu_rd_col   (alu_rd_col),
        .alu_rd_data  (alu_rd_data),
        .alu_current_m(alu_current_m),
        .alu_current_n(alu_current_n),

        // alu 写
        .alu_wr_slot  (alu_wr_slot),
        .alu_wr_row   (alu_wr_row),
        .alu_wr_col   (alu_wr_col),
        .alu_wr_data  (alu_wr_data),
        .alu_wr_we    (alu_wr_we),
        .alu_res_m    (alu_res_m),
        .alu_res_n    (alu_res_n),
        .alu_dim_we   (alu_dim_we)
    );

    // ============================================================
    // 4. Matrix ALU
    // ============================================================
    reg        start;
    reg  [2:0] opcode;
    reg  [15:0] scalar_val;
    wire       alu_done;
    wire       alu_error;

    matrix_alu u_matrix_alu (
        .clk   (clk),
        .rst_n (rst_n),

        .start     (start),
        .opcode    (opcode),
        .scalar_val(scalar_val),
        .done      (alu_done),
        .error     (alu_error),

        .mem_rd_slot (alu_rd_slot),
        .mem_rd_row  (alu_rd_row),
        .mem_rd_col  (alu_rd_col),
        .mem_rd_data (alu_rd_data),
        .mem_current_m(alu_current_m),
        .mem_current_n(alu_current_n),

        .mem_wr_slot (alu_wr_slot),
        .mem_wr_row  (alu_wr_row),
        .mem_wr_col  (alu_wr_col),
        .mem_wr_data (alu_wr_data),
        .mem_wr_we   (alu_wr_we),
        .mem_res_m   (alu_res_m),
        .mem_res_n   (alu_res_n),
        .mem_dim_we  (alu_dim_we)
    );

    // ============================================================
    // 5. 顶层控制状态机定义
    // ============================================================
    localparam SLOT_A = 2'd0;
    localparam SLOT_B = 2'd1;
    localparam SLOT_C = 2'd2;

    localparam OP_ADD = 3'b000;
    localparam OP_SUB = 3'b001;
    localparam OP_MUL = 3'b010;
    localparam OP_SCA = 3'b011;
    localparam OP_TRA = 3'b100;

    localparam ST_IDLE             = 5'd0;
    localparam ST_RECV_A_M         = 5'd1;
    localparam ST_RECV_A_N         = 5'd2;
    localparam ST_RECV_A_DATA      = 5'd3;
    localparam ST_RECV_B_M         = 5'd4;
    localparam ST_RECV_B_N         = 5'd5;
    localparam ST_RECV_B_DATA      = 5'd6;
    localparam ST_RECV_OPCODE      = 5'd7;
    localparam ST_RECV_SCALAR      = 5'd8;
    localparam ST_START_ALU        = 5'd9;
    localparam ST_WAIT_ALU         = 5'd10;
    localparam ST_PREP_READ_MEM    = 5'd11;
    localparam ST_READ_RESULT_MEM  = 5'd12;
    localparam ST_PREP_ASCII       = 5'd13;
    localparam ST_SEND_SIGN        = 5'd14;
    localparam ST_SEND_DIGIT       = 5'd15;
    localparam ST_SEND_DELIMITER   = 5'd16;
    localparam ST_DONE_STATE       = 5'd17;
    localparam ST_LATCH_RESULT     = 5'd18;  // latch user_rd_data
    localparam ST_ASCII_CALC_DIGITS= 5'd19;  // 计算 digit_buf / digit_cnt
    localparam ST_WAIT_SIGN_TX     = 5'd20;  // 等待负号发送完成
    localparam ST_WAIT_DIGIT_TX    = 5'd21;  // 等待数字发送完成
    localparam ST_WAIT_DELIM_TX    = 5'd22;  // 等待空格发送完成

    reg [4:0] state;

    // 矩阵维度与计数
    reg [2:0] a_m, a_n, b_m, b_n;
    reg [7:0] total_a, total_b;
    reg [7:0] elem_count;
    reg [2:0] wr_row, wr_col;
    reg [2:0] res_m, res_n;
    reg [2:0] send_row, send_col;

    // ASCII 转换相关
    reg [3:0] digit_buf[0:4];  // [0]最低位 -> [4]最高位
    reg [2:0] digit_cnt;       // 剩余要发送的数字个数
    reg [2:0] send_digit_idx;  // 当前发送的 digit_buf 下标
    reg [2:0] calc_cnt;        // 新增：BCD转换计数器
    reg [15:0] result_data_buffer;
    reg        is_negative;
    reg signed [15:0] temp_data_signed;

    integer i_int;

    // 调试端口已移除，这里也就不再声明 'done' 信号
    // assign done = (state == ST_DONE_STATE);

    function [7:0] digit_to_ascii;
        input [3:0] digit;
        begin
            digit_to_ascii = digit + 8'h30;
        end
    endfunction

    // ============================================================
    // 6. 主状态机
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= ST_IDLE;

            user_slot_idx <= 2'd0;
            user_row      <= 3'd0;
            user_col      <= 3'd0;
            user_data     <= 16'd0;
            user_we       <= 1'b0;
            user_dim_m    <= 3'd0;
            user_dim_n    <= 3'd0;
            user_dim_we   <= 1'b0;

            a_m <= 3'd0; a_n <= 3'd0;
            b_m <= 3'd0; b_n <= 3'd0;
            total_a <= 8'd0;
            total_b <= 8'd0;
            elem_count <= 8'd0;
            wr_row <= 3'd0;
            wr_col <= 3'd0;
            res_m  <= 3'd0;
            res_n  <= 3'd0;
            send_row <= 3'd0;
            send_col <= 3'd0;

            tx_data  <= 8'd0;
            tx_start <= 1'b0;
            start    <= 1'b0;
            opcode   <= 3'd0;
            scalar_val <= 16'd0;

            result_data_buffer <= 16'd0;
            is_negative        <= 1'b0;
            temp_data_signed   <= 16'sd0;
            digit_cnt          <= 3'd0;
            send_digit_idx     <= 3'd0;
            calc_cnt           <= 3'd0;

            for (i_int = 0; i_int < 5; i_int = i_int + 1)
                digit_buf[i_int] <= 4'd0;

        end else begin
            // ---- 每拍默认清零的一次性信号 ----
            user_we     <= 1'b0;
            user_dim_we <= 1'b0;
            tx_start    <= 1'b0;
            start       <= 1'b0;

            case (state)
                // ------------------------------------------------
                // 接收 A
                // ------------------------------------------------
                ST_IDLE: begin
                    if (number_valid) begin
                        a_m   <= number_out[2:0];
                        state <= ST_RECV_A_N;
                    end
                end

                ST_RECV_A_N: begin
                    if (number_valid) begin
                        a_n     <= number_out[2:0];
                        total_a <= number_out[2:0] * a_m;

                        user_slot_idx <= SLOT_A;
                        user_dim_m    <= a_m;
                        user_dim_n    <= number_out[2:0];
                        user_dim_we   <= 1'b1;

                        wr_row    <= 3'd0;
                        wr_col    <= 3'd0;
                        elem_count<= 8'd0;

                        state     <= ST_RECV_A_DATA;
                    end
                end

                ST_RECV_A_DATA: begin
                    if (number_valid) begin
                        user_slot_idx <= SLOT_A;
                        user_row      <= wr_row;
                        user_col      <= wr_col;
                        user_data     <= number_out;
                        user_we       <= 1'b1;

                        elem_count <= elem_count + 1'b1;

                        if (wr_col == a_n - 1) begin
                            wr_col <= 3'd0;
                            wr_row <= wr_row + 1'b1;
                        end else begin
                            wr_col <= wr_col + 1'b1;
                        end

                        if (elem_count + 1 == total_a) begin
                            state <= ST_RECV_B_M;
                        end
                    end
                end

                // ------------------------------------------------
                // 接收 B
                // ------------------------------------------------
                ST_RECV_B_M: begin
                    if (number_valid) begin
                        b_m   <= number_out[2:0];
                        state <= ST_RECV_B_N;
                    end
                end

                ST_RECV_B_N: begin
                    if (number_valid) begin
                        b_n     <= number_out[2:0];
                        total_b <= number_out[2:0] * b_m;

                        user_slot_idx <= SLOT_B;
                        user_dim_m    <= b_m;
                        user_dim_n    <= number_out[2:0];
                        user_dim_we   <= 1'b1;

                        wr_row    <= 3'd0;
                        wr_col    <= 3'd0;
                        elem_count<= 8'd0;

                        state     <= ST_RECV_B_DATA;
                    end
                end

                ST_RECV_B_DATA: begin
                    if (number_valid) begin
                        user_slot_idx <= SLOT_B;
                        user_row      <= wr_row;
                        user_col      <= wr_col;
                        user_data     <= number_out;
                        user_we       <= 1'b1;

                        elem_count <= elem_count + 1'b1;

                        if (wr_col == b_n - 1) begin
                            wr_col <= 3'd0;
                            wr_row <= wr_row + 1'b1;
                        end else begin
                            wr_col <= wr_col + 1'b1;
                        end

                        if (elem_count + 1 == total_b) begin
                            state <= ST_RECV_OPCODE;
                        end
                    end
                end

                // ------------------------------------------------
                // Opcode / Scalar
                // ------------------------------------------------
                ST_RECV_OPCODE: begin
                    if (number_valid) begin
                        opcode <= number_out[2:0];

                        case (number_out[2:0])
                            OP_ADD,
                            OP_SUB: begin
                                res_m <= a_m;
                                res_n <= a_n;
                                state <= ST_START_ALU;
                            end

                            OP_SCA: begin
                                res_m <= a_m;
                                res_n <= a_n;
                                state <= ST_RECV_SCALAR;
                            end

                            OP_MUL: begin
                                res_m <= a_m;
                                res_n <= b_n;
                                state <= ST_START_ALU;
                            end

                            OP_TRA: begin
                                res_m <= a_n;
                                res_n <= a_m;
                                state <= ST_START_ALU;
                            end

                            default: begin
                                state <= ST_DONE_STATE;
                            end
                        endcase
                    end
                end

                ST_RECV_SCALAR: begin
                    if (number_valid) begin
                        scalar_val <= number_out;
                        state      <= ST_START_ALU;
                    end
                end

                // ------------------------------------------------
                // 启动 ALU / 等待完成
                // ------------------------------------------------
                ST_START_ALU: begin
                    start <= 1'b1;
                    state <= ST_WAIT_ALU;
                end

                ST_WAIT_ALU: begin
                    if (alu_done) begin
                        send_row      <= 3'd0;
                        send_col      <= 3'd0;
                        user_slot_idx <= SLOT_C;
                        user_row      <= 3'd0;
                        user_col      <= 3'd0;
                        state         <= ST_PREP_READ_MEM;
                    end else if (alu_error) begin
                        state <= ST_DONE_STATE;
                    end
                end

                // ------------------------------------------------
                // 读取结果矩阵 C 并发送
                // ------------------------------------------------
                ST_PREP_READ_MEM: begin
                    state <= ST_READ_RESULT_MEM;
                end

                ST_READ_RESULT_MEM: begin
                    state <= ST_LATCH_RESULT;
                end

                ST_LATCH_RESULT: begin
                    result_data_buffer <= user_rd_data;
                    state              <= ST_ASCII_CALC_DIGITS;
                    calc_cnt           <= 3'd0; // 初始化计数器
                    
                    // 预先处理符号位
                    is_negative        <= user_rd_data[15];
                    if (user_rd_data[15])
                         temp_data_signed <= -$signed(user_rd_data);
                    else
                         temp_data_signed <= $signed(user_rd_data);

                `ifdef SIM_DEBUG_TOP
                    $display("[%0t] [TOP_C_READ] C[%0d][%0d] = %0d (0x%h)",
                             $time, send_row, send_col,
                             user_rd_data, user_rd_data);
                `endif
                end

                // ------------------------------------------------
                // 计算 digit_buf / digit_cnt (重构为多周期)
                // ------------------------------------------------
                ST_ASCII_CALC_DIGITS: begin
                    if (calc_cnt < 5) begin
                        // 每个周期计算一位
                        digit_buf[calc_cnt] <= temp_data_signed % 10;
                        temp_data_signed    <= temp_data_signed / 10;
                        calc_cnt            <= calc_cnt + 1'b1;
                    end else begin
                        // 计算完成，确定有效位数
                        if (result_data_buffer == 16'd0) begin
                            digit_cnt      <= 3'd1;
                            send_digit_idx <= 3'd0;
                        end else if (digit_buf[4] != 0) begin
                            digit_cnt      <= 3'd5;
                            send_digit_idx <= 3'd4;
                        end else if (digit_buf[3] != 0) begin
                            digit_cnt      <= 3'd4;
                            send_digit_idx <= 3'd3;
                        end else if (digit_buf[2] != 0) begin
                            digit_cnt      <= 3'd3;
                            send_digit_idx <= 3'd2;
                        end else if (digit_buf[1] != 0) begin
                            digit_cnt      <= 3'd2;
                            send_digit_idx <= 3'd1;
                        end else begin
                            digit_cnt      <= 3'd1;
                            send_digit_idx <= 3'd0;
                        end
                        state <= ST_PREP_ASCII;
                    end

                `ifdef SIM_DEBUG_TOP
                    if (calc_cnt == 5) begin
                        $display("[%0t] [TOP_ASCII_CALC] val=%0d (0x%h), is_neg=%0d, "
                                 "digits[4..0]=%0d %0d %0d %0d %0d, "
                                 "init_digit_cnt=%0d, init_send_idx=%0d",
                                 $time,
                                 $signed(result_data_buffer), result_data_buffer,
                                 is_negative,
                                 digit_buf[4], digit_buf[3], digit_buf[2],
                                 digit_buf[1], digit_buf[0],
                                 digit_cnt, send_digit_idx); // 注意：这里打印的 cnt/idx 还是上一拍的值，实际上在下一拍生效
                    end
                `endif
                end

                // ------------------------------------------------
                // ASCII 发送准备（这里只决定走 sign 还是 digit）
                // ------------------------------------------------
                ST_PREP_ASCII: begin
                `ifdef SIM_DEBUG_TOP
                    $display("[%0t] [TOP_DBG_ASCII] Result %0d (0x%h) -> "
                             "is_negative=%0d. Digits: %0d%0d%0d%0d%0d. digit_cnt=%0d. send_idx_start=%0d.",
                             $time,
                             $signed(result_data_buffer), result_data_buffer,
                             is_negative,
                             digit_buf[4], digit_buf[3], digit_buf[2],
                             digit_buf[1], digit_buf[0],
                             digit_cnt, send_digit_idx);
                `endif
                    if (is_negative)
                        state <= ST_SEND_SIGN;
                    else
                        state <= ST_SEND_DIGIT;
                end

                // ------------------------------------------------
                // 发送负号 + 等待发送完成
                // ------------------------------------------------
                ST_SEND_SIGN: begin
                    if (!tx_busy) begin
                        tx_data  <= 8'h2D; // '-'
                        tx_start <= 1'b1;
                    `ifdef SIM_DEBUG_TOP
                        $display("[%0t] [TOP_ASCII_SEND] Sending sign '-' (ASCII 0x2D), value=%0d",
                                 $time, $signed(result_data_buffer));
                    `endif
                        state   <= ST_WAIT_SIGN_TX;
                    end
                end

                ST_WAIT_SIGN_TX: begin
                    // UART 发送完成后 busy 会回到 0，再进入发数字阶段
                    if (!tx_busy) begin
                        state <= ST_SEND_DIGIT;
                    end
                end

                // ------------------------------------------------
                // 发送数字各位：分成"发起发送"和"等待完成"两阶段
                // ------------------------------------------------
                ST_SEND_DIGIT: begin
                    if (!tx_busy) begin
                        tx_data  <= digit_to_ascii(digit_buf[send_digit_idx]);
                        tx_start <= 1'b1;
                    `ifdef SIM_DEBUG_TOP
                        $display("[%0t] [TOP_ASCII_SEND] Sending digit %0d (ASCII 0x%0h '%c'), idx=%0d, remaining_cnt=%0d, value=%0d",
                                 $time,
                                 digit_buf[send_digit_idx],
                                 digit_to_ascii(digit_buf[send_digit_idx]),
                                 digit_to_ascii(digit_buf[send_digit_idx]),
                                 send_digit_idx, digit_cnt, $signed(result_data_buffer));
                    `endif
                        state   <= ST_WAIT_DIGIT_TX;
                    end
                end

                ST_WAIT_DIGIT_TX: begin
                    if (!tx_busy) begin
                        // 上一位已经完全发送完成
                        if (digit_cnt == 3'd1) begin
                            // 刚刚发的是最后一位
                            state <= ST_SEND_DELIMITER;
                        end else begin
                            // 还有多位要发：更新计数和 index，然后回到 ST_SEND_DIGIT
                            digit_cnt      <= digit_cnt - 1'b1;
                            send_digit_idx <= send_digit_idx - 1'b1;
                            state          <= ST_SEND_DIGIT;
                        end
                    end
                end

                // ------------------------------------------------
                // 发送分隔符 & 等待发送完成 & 准备下一个 C(i,j)
                // ------------------------------------------------
                ST_SEND_DELIMITER: begin
                    if (!tx_busy) begin
                        tx_data  <= 8'h20; // 空格
                        tx_start <= 1'b1;
                        state    <= ST_WAIT_DELIM_TX;
                    end
                end

                ST_WAIT_DELIM_TX: begin
                    if (!tx_busy) begin
                        // 分隔符发完，选择下一个元素
                        if (send_col == res_n - 1) begin
                            if (send_row == res_m - 1) begin
                                // 最后一行最后一列
                                state <= ST_DONE_STATE;
                            end else begin
                                // 下一行第一列
                                send_row      <= send_row + 1'b1;
                                send_col      <= 3'd0;
                                user_slot_idx <= SLOT_C;
                                user_row      <= send_row + 1'b1;
                                user_col      <= 3'd0;
                                state         <= ST_PREP_READ_MEM;
                            end
                        end else begin
                            // 同一行的下一列
                            send_col      <= send_col + 1'b1;
                            user_slot_idx <= SLOT_C;
                            user_row      <= send_row;
                            user_col      <= send_col + 1'b1;
                            state         <= ST_PREP_READ_MEM;
                        end
                    end
                end

                ST_DONE_STATE: begin
                    // 保持完成状态
                end

                default: begin
                    state <= ST_IDLE;
                end

            endcase
        end
    end

    // ============================================================
    // 7. 硬件 IO
    // ============================================================
    // LED 保持功能，但 'done' 和 'alu_error' 不再是顶层端口
    assign led_pin[0]   = (state == ST_DONE_STATE);
    assign led_pin[1]   = alu_error; // alu_error 是内部信号，仍可用于LED
    assign led_pin[15:2]= 14'h0;

    assign seg_cs_pin      = 8'hFF;
    assign seg_data_0_pin  = 8'hFF;
    assign seg_data_1_pin  = 8'hFF;

    // 上板没用到的输入拉个默认
    // （在顶层例化时你已经按 dummy_* 绑了，可以忽略）

    // --- 调试端口已移除，以下赋值也一并删除 ---
    // assign debug_top_state           = state;
    // assign debug_parser_number_out   = number_out;
    // assign debug_parser_number_valid = number_valid;
    // assign debug_alu_state           = u_matrix_alu.state; // u_matrix_alu.state 需要 alu 模块内部暴露
    // assign debug_alu_i               = u_matrix_alu.i;     // u_matrix_alu.i 需要 alu 模块内部暴露
    // assign debug_alu_j               = u_matrix_alu.j;     // u_matrix_alu.j 需要 alu 模块内部暴露
    // assign debug_mem_rd_data_c_val   = user_rd_data;
    // assign debug_mem_read_c_req      = (user_slot_idx == SLOT_C);

endmodule
