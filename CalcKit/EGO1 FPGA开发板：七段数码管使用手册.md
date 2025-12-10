

# EGO1 FPGA开发板：七段数码管使用手册

## 1. 概述 (Overview)

EGO1 开发板板载了 **8个** 七段数码管，用于显示数字、字母或符号。这些数码管分为左右两组，每组4个。通过FPGA的I/O引脚控制“段选”（控制显示什么字）和“位选”（控制哪个数码管亮），可以实现动态或静态显示。

## 2. 硬件工作原理 (Working Principle)

### 2.1 显示单元结构

每个数码管由8个发光二极管（LED）组成，分别对应：

* **7个段 (Segment)：** a, b, c, d, e, f, g（用于组成字符）
* **1个小数点 (Decimal Point)：** dp

### 2.2 控制逻辑 (Control Logic)

EGO1 的数码管控制逻辑如下（基于幻灯片信息）：

* **段选信号 (Segment Control):** **高电平有效 (Active High)**。
  * 逻辑 `1`：点亮该段。
  * 逻辑 `0`：熄灭该段。
* **位选信号 (Chip Selection):** **高电平有效 (Active High)**。
  * 逻辑 `1`：选中该数码管（该数码管通电工作）。
  * 逻辑 `0`：未选中（该数码管熄灭）。

> **注意**：这与许多传统教学中常见的“共阳极（低电平点亮）”数码管不同，EGO1在这里设计为高电平点亮。

## 3. 引脚分配 (Pin Assignment)

8个数码管分为两组（Group 0 和 Group 1），每组共享一套段选信号，但拥有独立的位选信号。

### 3.1 组别划分

* **左侧组 (Group 0):** 对应原理图符号后缀 `0` (如 A0, B0... DN0_K1...)
* **右侧组 (Group 1):** 对应原理图符号后缀 `1` (如 A1, B1... DN1_K1...)

### 3.2 详细引脚映射表

在编写约束文件（`.xdc`）时，请参考下表：

#### A. 段选引脚 (控制显示内容)

| 段名称 (Segment) | 左侧组管脚 (Group 0 PIN) | 右侧组管脚 (Group 1 PIN) |
|:------------- |:------------------- |:------------------- |
| **a**         | **B4** (A0)         | **D4** (A1)         |
| **b**         | **A4** (B0)         | **E3** (B1)         |
| **c**         | **A3** (C0)         | **D3** (C1)         |
| **d**         | **B1** (D0)         | **F4** (D1)         |
| **e**         | **A1** (E0)         | **F3** (E1)         |
| **f**         | **B3** (F0)         | **E2** (F1)         |
| **g**         | **B2** (G0)         | **D2** (G1)         |
| **dp** (小数点)  | **D5** (DP0)        | **H2** (DP1)        |

#### B. 位选引脚 (控制哪个数码管亮)

位选信号决定了具体点亮哪一个位置的数码管。

| 显示位置        | 信号名称 (Signal) | FPGA管脚 (FPGA PIN) | 备注      |
|:----------- |:------------- |:----------------- |:------- |
| **左1** (最左) | DN0_K1        | **G2**            | Group 0 |
| **左2**      | DN0_K2        | **C2**            | Group 0 |
| **左3**      | DN0_K3        | **C1**            | Group 0 |
| **左4**      | DN0_K4        | **H1**            | Group 0 |
| **右1**      | DN1_K1        | **G1**            | Group 1 |
| **右2**      | DN1_K2        | **F1**            | Group 1 |
| **右3**      | DN1_K3        | **E1**            | Group 1 |
| **右4** (最右) | DN1_K4        | **G6**            | Group 1 |

---

## 4. 软件设计与编码 (Implementation)

### 4.1 编码格式 (Encoding)

根据幻灯片中的Verilog代码示例，推荐将段选信号定义为一个8位的向量 `tub_control[7:0]`，其位序对应关系如下：

* **MSB (最高位) $\rightarrow$ LSB (最低位):**
* `[7:0]` 对应 `a, b, c, d, e, f, g, dp`

**十六进制真值表 (Common Anode / Active High):**
此表基于 `tub_control = {a,b,c,d,e,f,g,dp}` 排列：

| 显示字符          | 二进制值 (a-dp) | 十六进制值 (Hex) |
|:-------------:|:----------- |:----------- |
| **0**         | `1111 1100` | `0xFC`      |
| **1**         | `0110 0000` | `0x60`      |
| **2**         | `1101 1010` | `0xDA`      |
| **3**         | `1111 0010` | `0xF2`      |
| **4**         | `0110 0110` | `0x66`      |
| **5**         | `1011 0110` | `0xB6`      |
| **6**         | `1011 1110` | `0xBE`      |
| **7**         | `1110 0000` | `0xE0`      |
| **8**         | `1111 1110` | `0xFE`      |
| **9**         | `1111 0110` | `0xF6`      |
| **E** (Error) | `1001 1110` | `0x9E`      |

### 4.2 示例设计：BCD转十进制显示 (Verilog)

以下代码展示了如何使用下方的拨码开关（Switch）控制最左侧的一个数码管显示数字。

**Verilog 代码逻辑:**

```verilog
module lab5_demo1(
    input [3:0] in_b4,          // 输入：4位拨码开关 (BCD码)
    output tub_sel,             // 输出：位选信号 (控制哪个数码管亮)
    output reg [7:0] tub_control // 输出：段选信号 (控制显示什么内容)
);

    // 1. 激活位选：始终输出高电平，选中连接到该引脚的数码管
    assign tub_sel = 1'b1;

    // 2. 译码逻辑：根据输入BCD码设置段选
    // 映射顺序：tub_control[7:0] = {a, b, c, d, e, f, g, dp}
    always @(*) begin
        case(in_b4)
            4'b0000: tub_control = 8'b1111_1100; // 显示 0
            4'b0001: tub_control = 8'b0110_0000; // 显示 1
            4'b0010: tub_control = 8'b1101_1010; // 显示 2
            4'b0011: tub_control = 8'b1111_0010; // 显示 3
            4'b0100: tub_control = 8'b0110_0110; // 显示 4
            4'b0101: tub_control = 8'b1011_0110; // 显示 5
            4'b0110: tub_control = 8'b1011_1110; // 显示 6
            4'b0111: tub_control = 8'b1110_0000; // 显示 7
            4'b1000: tub_control = 8'b1111_1110; // 显示 8
            4'b1001: tub_control = 8'b1111_0110; // 显示 9
            default: tub_control = 8'b1001_1110; // 非BCD码显示 "E"
        endcase
    end
endmodule
```

### 4.3 约束文件配置 (.xdc)

为了让上述代码在EGO1上运行，需要将端口绑定到正确的物理引脚。

```tcl
# --- 位选信号 (选中最左侧数码管 DN0_K1 -> G2) ---
set_property PACKAGE_PIN G2 [get_ports tub_sel]
set_property IOSTANDARD LVCMOS33 [get_ports tub_sel]

# --- 段选信号 (Group 0 对应引脚) ---
# 对应顺序 {a, b, c, d, e, f, g, dp}
set_property PACKAGE_PIN B4 [get_ports {tub_control[7]}] ;# Segment A
set_property PACKAGE_PIN A4 [get_ports {tub_control[6]}] ;# Segment B
set_property PACKAGE_PIN A3 [get_ports {tub_control[5]}] ;# Segment C
set_property PACKAGE_PIN B1 [get_ports {tub_control[4]}] ;# Segment D
set_property PACKAGE_PIN A1 [get_ports {tub_control[3]}] ;# Segment E
set_property PACKAGE_PIN B3 [get_ports {tub_control[2]}] ;# Segment F
set_property PACKAGE_PIN B2 [get_ports {tub_control[1]}] ;# Segment G
set_property PACKAGE_PIN D5 [get_ports {tub_control[0]}] ;# Segment DP

# 设置电平标准 (通常为 LVCMOS33)
set_property IOSTANDARD LVCMOS33 [get_ports {tub_control[*]}]

# --- 输入开关配置 (假设使用左下角开关) ---
set_property PACKAGE_PIN P5 [get_ports {in_b4[3]}]
set_property PACKAGE_PIN P4 [get_ports {in_b4[2]}]
set_property PACKAGE_PIN P3 [get_ports {in_b4[1]}]
set_property PACKAGE_PIN P2 [get_ports {in_b4[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {in_b4[*]}]
```

---

## 5. 总结 (Summary)

1. **确定显示位置：** 查阅“位选引脚表”，将代码中的位选输出绑定到对应的FPGA引脚（如想用左侧第一个，就绑定到 `G2`），并置为高电平。
2. **确定显示内容：** 查阅“段选引脚表”，将段选总线绑定到对应的FPGA引脚组（如左侧组对应 `B4` 等）。
3. **编写逻辑：** 使用查找表（Case语句）将数字转换为对应的段选码（高电平点亮）。
4. **注意：** 如果需要同时让多个数码管显示**不同**的数字，需要使用**动态扫描**技术（快速轮流切换位选信号和段选数据），利用人眼的视觉暂留效应实现。以上示例仅为静态显示（单个数码管工作）。
