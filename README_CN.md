# FPGA 矩阵计算器模块使用指南

本文档详细介绍了基于FPGA的矩阵计算器系统的各个核心模块的功能、接口定义及使用流程。该系统主要包含矩阵存储、矩阵生成、矩阵运算（ALU）以及卷积加速器四个部分。

---

## 1. 系统架构概览

系统围绕 **矩阵存储模块 (Matrix Memory)** 构建，所有其他模块（生成器、ALU、卷积核）都通过读写接口与存储模块交互。

* **Matrix Memory**: 核心存储，支持多槽位（Slot）管理矩阵数据。
* **Matrix Gen**: 伪随机数矩阵生成器，用于测试输入。
* **Matrix ALU**: 执行矩阵加、减、乘、标量乘、转置等通用运算。
* **Bonus Conv**: 专用的3x3卷积加速器，演示流式处理能力。

---

## 2. 核心模块详解

### 2.1 矩阵存储模块 (matrix_mem.v)

**功能**:
提供双端口访问的共享存储器。支持3个槽位（Slot 0, 1, 2），每个槽位可存储不同维度的矩阵。

**接口说明**:

* **Port 1 (User/Gen/Conv)**: 主要用于外部数据写入（如测试激励、生成器）或卷积模块读取。
  * `user_slot_idx`: 选择操作的槽位 (0-2)。
  * `user_row`, `user_col`: 读写的行列坐标。
  * `user_data`: 写入的数据 (16-bit)。
  * `user_we`: 写使能信号。
  * `user_dim_m`, `user_dim_n`: 写入该槽位矩阵的行数和列数。
  * `user_dim_we`: 维度更新写使能。
  * `user_rd_data`: 读出的数据（异步读取）。
* **Port 2 (ALU)**: 专供ALU使用，支持独立的读写操作。
  * `alu_rd_slot`: ALU读取的槽位。
  * `alu_current_m/n`: 输出当前读取槽位的维度信息。

**使用注意**:

* 在写入新矩阵数据前，建议先通过 `user_dim_we` 更新该槽位的维度信息。
* Port 1 和 Port 2 可以同时工作，但应避免同时写入同一地址（虽然设计上User Port优先级可能不同，但应在系统级避免冲突）。

---

### 2.2 矩阵生成模块 (matrix_gen.v)

**功能**:
使用线性反馈移位寄存器 (LFSR) 生成伪随机数填充指定槽位的矩阵。

**接口说明**:

* `start`: 启动信号（脉冲）。
* `target_m`, `target_n`: 生成矩阵的目标维度。
* `target_slot`: 目标存储槽位。
* `done`: 完成信号。
* **Output to Mem**: 输出 `gen_slot_idx`, `gen_data`, `gen_we` 等信号连接到存储器 Port 1。

**使用流程**:

1. 设置 `target_slot`, `target_m`, `target_n`。
2. 发送 `start` 脉冲。
3. 等待 `done` 信号变高。

---

### 2.3 矩阵运算单元 (matrix_alu.v)

**功能**:
执行核心矩阵运算。支持操作码 (Opcode) 控制。

**支持指令 (Opcode)**:

* `3'b000` (OP_ADD): 矩阵加法 (C = A + B)
* `3'b001` (OP_SUB): 矩阵减法 (C = A - B)
* `3'b010` (OP_MUL): 矩阵乘法 (C = A * B)
* `3'b011` (OP_SCA): 标量乘法 (C = A * scalar)
* `3'b100` (OP_TRA): 矩阵转置 (C = A^T)

**默认槽位约定**:

* **操作数 A**: 总是读取 **Slot 0**。
* **操作数 B**: 总是读取 **Slot 1** (仅双操作数指令)。
* **结果 C**: 总是写入 **Slot 2**。

**接口说明**:

* `start`: 启动信号。
* `opcode`: 操作码。
* `scalar_val`: 标量值 (仅 OP_SCA 使用)。
* `done`: 完成信号。
* `error`: 错误信号（如维度不匹配时拉高）。

**使用流程**:

1. 确保 Slot 0 (和 Slot 1) 中已有有效矩阵数据。
2. 设置 `opcode` 和 `scalar_val`。
3. 发送 `start` 脉冲。
4. 等待 `done` 或 `error`。
5. 结果将出现在 Slot 2。

---

### 2.4 卷积加速模块 (bonus_conv.v)

**功能**:
演示模块。读取 Slot 0 中的 3x3 矩阵作为卷积核 (Kernel)，对内部固化的图像数据进行卷积运算。

**接口说明**:

* `start_conv`: 启动信号。
* **Interface to Mem**: 输出 `mem_rd_row/col` 读取 Slot 0 的 Kernel。
* **Output**:
  * `conv_res_data`: 卷积结果流输出。
  * `conv_res_valid`: 结果有效指示信号。
  * `conv_done`: 全部计算完成信号。

**使用流程**:

1. 在 Slot 0 中写入一个 3x3 的卷积核矩阵。
2. 发送 `start_conv` 脉冲。
3. 在 `conv_res_valid` 为高时捕获输出数据。

---

## 3. 仿真与测试 (Testbench)

提供的 `tb_matrix_system.v` 是一个完整的测试平台，演示了所有功能。

**如何运行仿真**:
使用 Icarus Verilog (iverilog):

```bash
iverilog -g2012 -o simulation.vvp tb_matrix_system.v Matrix_Gen/matrix_gen.v Bonus_Conv/bonus_conv.v Matrix_mem/matrix_mem.v Matrix_alu/matrix_alu.v
vvp simulation.vvp
```

**测试用例包含**:

1. 随机生成矩阵并进行加法测试。
2. 矩阵乘法测试 (2x3 * 3x2)。
3. 标量乘法与转置测试。
4. 维度不匹配的错误检测测试。
5. 卷积功能测试（使用单位矩阵核和全1矩阵核）。
6. 手动写入特定数据进行ALU验证。

---

## 4. 常见问题 (FAQ)

* **Q: ALU 报错 (Error) 是什么原因？**
  * A: 通常是维度不匹配。例如尝试相加两个维度不同的矩阵，或者乘法时 A的列数不等于 B的行数。
* 
