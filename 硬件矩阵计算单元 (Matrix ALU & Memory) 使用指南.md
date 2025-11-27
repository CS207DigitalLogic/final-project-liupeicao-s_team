# 硬件矩阵计算单元 (Matrix ALU & Memory) 使用指南



本指南旨在帮助开发者理解并集成 `matrix_alu`（运算核心）与 `matrix_mem`（专用存储）模块。该系统支持矩阵加法、减法、乘法、标量乘法及转置操作。



## 1. 模块概述



- **matrix_mem**: 一个多端口存储器，包含三个特定的存储槽（Slot A, Slot B, Slot C）。
  - **Slot A & B**: 通常作为操作数（输入矩阵）。
  - **Slot C**: 通常作为结果存储区。
  - **特性**: 支持用户读写（用于初始化数据）和 ALU 读写（用于内部计算）。
- **matrix_alu**: 计算核心。
  - **功能**: 从 Memory 读取 Slot A/B 的数据，执行运算，并将结果写回 Slot C。
  - **机制**: 采用状态机控制，串行处理矩阵元素。

------



## 2. 矩阵存储模块 (`matrix_mem`)



该模块负责存储矩阵数据及其维度信息。



### 2.1 端口详解



| 端口名                   | 方向   | 位宽 | 描述                                            |
| ------------------------ | ------ | ---- | ----------------------------------------------- |
| **基础控制**             |        |      |                                                 |
| `clk`                    | Input  | 1    | 系统时钟                                        |
| `rst_n`                  | Input  | 1    | 异步复位（低电平有效）                          |
| **用户接口 (User Port)** |        |      | **用于外部 MCU/Testbench 初始化数据或读取结果** |
| `user_slot_idx`          | Input  | 2    | 选择操作的槽位 (0=A, 1=B, 2=C)                  |
| `user_row`               | Input  | 3    | 行地址                                          |
| `user_col`               | Input  | 3    | 列地址                                          |
| `user_data`              | Input  | 16   | 写入的数据                                      |
| `user_we`                | Input  | 1    | 写使能 (1=写入数据)                             |
| `user_dim_m`             | Input  | 3    | 矩阵行数 (高度)                                 |
| `user_dim_n`             | Input  | 3    | 矩阵列数 (宽度)                                 |
| `user_dim_we`            | Input  | 1    | 维度写使能 (1=更新当前槽位的维度)               |
| `user_rd_data`           | Output | 16   | 读出的数据 (当前地址对应的数据)                 |
| **ALU 接口 (ALU Port)**  |        |      | **必须连接到 `matrix_alu` 模块**                |
| `alu_rd_slot`            | Input  | 2    | ALU 请求读取的槽位                              |
| `alu_rd_row/col`         | Input  | 3    | ALU 请求读取的行列                              |
| `alu_rd_data`            | Output | 16   | 发送给 ALU 的数据                               |
| `alu_current_m/n`        | Output | 3    | 发送给 ALU 的当前槽位维度信息                   |
| `alu_wr_slot`            | Input  | 2    | ALU 请求写入的槽位                              |
| `alu_wr_row/col`         | Input  | 3    | ALU 请求写入的行列                              |
| `alu_wr_data`            | Input  | 16   | ALU 计算出的结果数据                            |
| `alu_wr_we`              | Input  | 1    | ALU 写数据使能                                  |
| `alu_res_m/n`            | Input  | 3    | ALU 计算出的结果维度                            |
| `alu_dim_we`             | Input  | 1    | ALU 写维度使能                                  |

导出到 Google 表格



### 2.2 内存寻址与限制



内部通过公式计算物理地址：`Address = (Slot * 32) + (Row * 5) + Col`。

- **最大矩阵尺寸**: 建议最大为 **5x5** 或 **6x5**。
- **原因**: 每个 Slot 只有 32 个字的偏移空间，且行跨度固定为 5 (`Row * 5`)。如果列数超过 5 或行数过多，地址可能会溢出到下一个 Slot。

------



## 3. 矩阵运算模块 (`matrix_alu`)



该模块是计算的大脑，控制数据的读取、计算和回写。



### 3.1 端口详解



| 端口名              | 方向   | 位宽 | 描述                                      |
| ------------------- | ------ | ---- | ----------------------------------------- |
| **控制接口**        |        |      |                                           |
| `start`             | Input  | 1    | 启动信号，产生一个脉冲以开始计算          |
| `opcode`            | Input  | 3    | 操作码 (见下文)                           |
| `scalar_val`        | Input  | 16   | 标量值 (仅在标量乘法模式下使用)           |
| `done`              | Output | 1    | 计算完成标志 (高电平脉冲或保持)           |
| `error`             | Output | 1    | 错误标志 (如维度不匹配)                   |
| **Memory 读取接口** |        |      | **连接到 `matrix_mem` 的 ALU Read Port**  |
| `mem_rd_slot`       | Output | 2    | 告诉 Memory 要读哪个 Slot                 |
| `mem_rd_row/col`    | Output | 3    | 告诉 Memory 要读哪一行列                  |
| `mem_rd_data`       | Input  | 16   | 从 Memory 读回的数据                      |
| `mem_current_m/n`   | Input  | 3    | 从 Memory 读回的维度                      |
| **Memory 写入接口** |        |      | **连接到 `matrix_mem` 的 ALU Write Port** |
| `mem_wr_slot`       | Output | 2    | **固定为 Slot C (2)**                     |
| `mem_wr_row/col`    | Output | 3    | 写回地址                                  |
| `mem_wr_data`       | Output | 16   | 写回数据                                  |
| `mem_wr_we`         | Output | 1    | 写数据使能                                |
| `mem_res_m/n`       | Output | 3    | 结果矩阵的新维度                          |
| `mem_dim_we`        | Output | 1    | 写维度使能                                |

导出到 Google 表格



### 3.2 操作码 (OpCodes)



| OpCode (Binary) | 名称    | 描述     | 数学表达           |
| --------------- | ------- | -------- | ------------------ |
| `3'b000`        | **ADD** | 矩阵加法 | C = A + B          |
| `3'b001`        | **SUB** | 矩阵减法 | C = A - B          |
| `3'b010`        | **MUL** | 矩阵乘法 | C = A × B          |
| `3'b011`        | **SCA** | 标量乘法 | C = A × scalar_val |
| `3'b100`        | **TRA** | 矩阵转置 | C = Aᵀ             |

## 4. 系统集成与使用流程





### 4.1 模块实例化连接



你需要创建一个顶层模块 (Top Module) 将两者连接起来。连接规则非常直观：**ALU 的输出连 Mem 的输入，Mem 的输出连 ALU 的输入**。

Verilog

```
// 伪代码连接示例
wire [15:0] alu_rd_data_wire;
wire [2:0]  alu_current_m_wire, alu_current_n_wire;
// ... 其他连接线 ...

matrix_mem u_mem (
    .clk(clk), .rst_n(rst_n),
    // 用户接口由 Testbench 或 外部控制器 驱动
    .user_slot_idx(tb_slot), .user_data(tb_data), .user_we(tb_we), ...
    
    // ALU 接口连接到 ALU 模块
    .alu_rd_slot(alu_rd_slot_wire),
    .alu_rd_data(alu_rd_data_wire), // Output from Mem -> Input to ALU
    .alu_wr_data(alu_wr_data_wire), // Output from ALU -> Input to Mem
    ...
);

matrix_alu u_alu (
    .clk(clk), .rst_n(rst_n),
    // 控制接口
    .start(start_pulse), .opcode(current_op), .done(done_flag), ...
    
    // Mem 接口
    .mem_rd_slot(alu_rd_slot_wire),
    .mem_rd_data(alu_rd_data_wire), // Input from Mem
    .mem_wr_data(alu_wr_data_wire), // Output to Mem
    ...
);
```



### 4.2 操作步骤 (Step-by-Step)





#### 步骤 1: 系统复位



拉低 `rst_n` 至少一个时钟周期，确保状态机归零，所有信号复位。



#### 步骤 2: 初始化数据 (User Write)



通过 `matrix_mem` 的 **User Port** 写入矩阵 A 和 B。

1. **设置 Slot A**:
   - `user_slot_idx` = 0 (Slot A)
   - 设置 `user_dim_m`, `user_dim_n` 并给一个脉冲 `user_dim_we`。
   - 遍历矩阵元素：设置 `user_row`, `user_col`, `user_data` 并给脉冲 `user_we`。
2. **设置 Slot B** (如果是双操作数运算):
   - `user_slot_idx` = 1 (Slot B)
   - 重复上述写入维度和数据的过程。



#### 步骤 3: 启动计算



操作 `matrix_alu` 的控制接口：

1. 设置 `opcode` (例如 `3'b010` 用于乘法)。
2. 如果是标量乘法，设置 `scalar_val`。
3. 拉高 `start` 信号一个时钟周期。



#### 步骤 4: 等待完成



监控 ALU 的 `done` 或 `error` 信号。

- **Waiting**: ALU 会自动读取 A 和 B 的维度，检查合法性，计算，并将结果写入 Slot C。
- **Done**: 当 `done` 变高，表示 Slot C 数据已准备好。
- **Error**: 如果 `error` 变高，通常意味着矩阵维度不匹配（例如加法时 A、B 尺寸不同，或乘法时 A列 != B行）。



#### 步骤 5: 读取结果 (User Read)



通过 `matrix_mem` 的 **User Port** 读取 Slot C。

1. `user_slot_idx` = 2 (Slot C)。
2. 遍历 `user_row` 和 `user_col`。
3. 在 `user_rd_data` 端口读取数据（组合逻辑输出，地址变化后数据即变化）。

------



## 5. 设计注意事项与限制



1. **结果存储位置**: ALU **强制**将结果写入 **Slot C (Index 2)**。如果在 Slot C 中预存了重要数据，计算后将被覆盖。
2. **数据类型**: 内部运算使用 `signed` (有符号数)。输入 `16'hFFFF` 代表 `-1`。确保你的测试数据符合补码格式。
3. **矩阵大小限制**:
   - 虽然地址位宽支持到 7 (`3'b111`)，但由于内存映射逻辑是 `Slot*32 + Row*5 + Col`，请务必保证 `Row*5 + Col < 32`。
   - **安全范围**: 最大 **5行 x 5列**。
4. **乘法溢出**:
   - 乘法累加器 (`accumulator`) 是 32 位的，但写入内存时截断为 16 位 (`mem_wr_data <= accumulator[15:0]`)。
   - **风险**: 如果矩阵乘法的结果数值过大，会导致高位丢失（溢出）。请控制输入数值的大小。
5. **时序**: 这是一个多周期计算器。矩阵越大，计算所需时钟周期越多 (尤其是矩阵乘法，复杂度为 O(M*N*K))。不要在 `done` 信号到来前读取结果。

------



## 6. 快速查错 (Troubleshooting)



- **Error 信号亮起**:
  - 检查 `S_CHECK` 状态的逻辑。
  - 做加法/减法时，A 和 B 的长宽必须完全相等。
  - 做乘法时，A 的列数 (`dim_na`) 必须等于 B 的行数 (`dim_mb`)。
- **结果全是 0**:
  - 检查是否正确写入了输入矩阵的**维度** (`user_dim_we`)？如果维度是 0，ALU 循环不会执行。
  - 检查复位信号 `rst_n` 是否正确释放。
- **结果混乱**:
  - 检查是否超出了 5x5 的大小限制，导致内存地址覆盖。
  - 检查是否有乘法溢出。