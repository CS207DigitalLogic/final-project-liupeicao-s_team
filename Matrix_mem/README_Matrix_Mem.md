# Matrix Memory Module Design

## 1. 模块概述 (Overview)

`matrix_mem` 是矩阵计算器的核心存储单元。它不仅仅是一个简单的 RAM，还实现了针对 $5 \times 5$ 小矩阵优化的多槽位管理和维度记录功能。

该模块采用 **“固定槽位 (Fixed Slot)”** 架构，将内部存储划分为三个逻辑区域，分别对应输入矩阵 A、输入矩阵 B 和结果矩阵 C。

## 2. 存储架构 (Architecture)

为了简化硬件寻址逻辑，采用 32 深度作为每个槽位的偏移量 (Offset)，尽管实际只需 25 ($5 \times 5$) 个字。

```text
|-------------------| <--- Addr 0
|    Slot 0 (A)     |      存 User Input A
|  (Size: 5x5 max)  |
|-------------------| <--- Addr 32 (1 << 5)
|    Slot 1 (B)     |      存 User Input B
|  (Size: 5x5 max)  |
|-------------------| <--- Addr 64 (2 << 5)
|    Slot 2 (C)     |      存 ALU Result
|  (Size: 5x5 max)  |
|-------------------| <--- Addr 95
地址映射公式
A
d
d
r
e
s
s
=
(
S
l
o
t
_
I
D
×
32
)
+
(
R
o
w
×
5
)
+
C
o
l
Address=(Slot_ID×32)+(Row×5)+Col
注：在 Verilog 内部实现中，Row * 5 被优化为 (Row << 2) + Row，且 Slot_ID * 32 仅需简单的位拼接 {slot, 5'b0}。
3. 实现细节 (Implementation Strategy)
A. 存储介质
使用 Verilog 寄存器数组 (reg [15:0] mem [...]) 而非 FPGA Block RAM IP。
原因 1: 矩阵很小 (总共 < 100个字)，使用 LUT 资源即可，不浪费宝贵的 BRAM。
原因 2 (关键): 寄存器数组支持 组合逻辑异步读取 (Asynchronous Read)。这意味着 ALU 发出地址的瞬间就能得到数据，无需等待下一个时钟上升沿。这极大简化了 ALU 状态机的设计（不需要 Wait State）。
B. 接口设计
模块为 双端口 (Dual Port) 逻辑：
User Port: 主要用于 UART 模块接收数据后写入，或者随机生成模块写入。
ALU Port:
读: 允许 ALU 读取任意槽位 (A/B/C) 的数据和维度。
写: 允许 ALU 将计算结果写回槽位 C。
C. 维度管理
除了存数据，模块内部维护了 dims_m (行数) 和 dims_n (列数) 寄存器组。ALU 在计算前会读取这些值来检查运算合法性 (例如：A的列数是否等于B的行数)。
4. 端口说明 (Port List)
端口名    方向    位宽    描述
clk, rst_n    Input    1    系统时钟与低电平复位
用户接口            
user_slot_idx    In    2    0=A, 1=B, 2=C
user_row/col    In    3    0~4
user_data    In    16    输入数据 (有符号)
user_we    In    1    写使能
user_dim_m/n    In    3    维度信息 (1~5)
user_dim_we    In    1    维度更新使能
ALU 接口            
alu_rd_slot    In    2    ALU 读地址槽位
alu_rd_row/col    In    3    ALU 读地址行列
alu_rd_data    Out    16    组合逻辑输出，无延迟
alu_current_m/n    Out    3    当前读槽位的维度
alu_wr_slot    In    2    ALU 写目标 (通常为 2)
alu_wr_row/col    In    3    ALU 写地址
alu_wr_data    In    16    ALU 写数据
alu_wr_we    In    1    ALU 写使能
5. 仿真指南
使用提供的 tb_matrix_mem.v 进行仿真。
观察 addr_user 信号，确认地址计算是否正确。
观察 alu_rd_data 是否在 alu_rd_row 变化的同一个周期内立即变化（体现异步读特性）。