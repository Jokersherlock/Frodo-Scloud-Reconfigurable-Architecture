# RTL代码说明

本文档说明RTL代码的配置和使用方法。

---

## 一、配置文件

### 1.1 配置文件位置

配置文件位于 `config/global_define.sv`，用于设置全局宏定义。

### 1.2 可配置的宏

#### `USE_IP`

**功能**：控制是否使用IP核实现RAM。

- **定义方式**：在 `config/global_define.sv` 中取消注释或添加 `define USE_IP`
- **作用**：
  - 当定义 `USE_IP` 时，系统会例化IP核（如 `bank_ram_ip`、`dual_ram` 等）
  - 当未定义 `USE_IP` 时，系统使用RTL实现的RAM（如 `single_port_ram`、`pseudo_dpsram` 等）

**使用位置**：
- `memory/bank_ram/bank_ram.sv` - Bank RAM的IP核/RTL选择
- `memory/accumulator/accumulator.sv` - Accumulator的IP核/RTL选择

**示例**：
```systemverilog
// config/global_define.sv
`define USE_IP  // 使用IP核
// 或注释掉：// `define USE_IP  // 使用RTL实现
```

---

#### `PRINT_RAM`

**功能**：控制RTL实现的RAM是否进行内存内容打印。

- **定义方式**：在 `config/global_define.sv` 中取消注释 `define PRINT_RAM`
- **作用**：
  - 当定义 `PRINT_RAM` 时，RTL实现的RAM会在触发信号有效时打印内存内容到文件
  - 当未定义 `PRINT_RAM` 时，不进行内存打印

**使用位置**：
- `memory/bank_ram/single_port_ram.sv` - 单端口RAM的内存打印功能

**示例**：
```systemverilog
// config/global_define.sv
`define PRINT_RAM  // 启用内存打印
// 或注释掉：// `define PRINT_RAM  // 禁用内存打印
```

---

## 二、PRINT_RAM使用说明

### 2.1 启用PRINT_RAM

1. 在 `config/global_define.sv` 中取消注释 `define PRINT_RAM`
2. 确保使用RTL实现的RAM（即未定义 `USE_IP`）

### 2.2 修改wait语句

在 `memory/bank_ram/single_port_ram.sv` 中，找到以下代码：

```systemverilog
`ifdef PRINT_RAM
    initial begin
        int fd;
        string filename;
        forever begin
            // 1. 等待全局触发信号变为特定值 (比如 1)
            // $root 允许你访问仿真顶层
            wait($root.tb_bank_ram_subsystem.dump_trigger == 1);  // <-- 需要修改这一行
            ...
            wait($root.tb_bank_ram_subsystem.dump_trigger == 0);  // <-- 需要修改这一行
        end
    end
`endif
```

**重要**：需要将 `wait` 语句中的模块名修改为**仿真的顶层模块名**。

例如，如果仿真的顶层模块是 `tb_my_test`，则应修改为：
```systemverilog
wait($root.tb_my_test.dump_trigger == 1);
...
wait($root.tb_my_test.dump_trigger == 0);
```

### 2.3 测试平台要求

在测试平台（testbench）中，**必须定义 `dump_trigger` 信号**，用于触发内存打印。

**示例**：
```systemverilog
module tb_my_test;
    // 定义触发信号
    logic dump_trigger;
    
    initial begin
        dump_trigger = 0;
        
        // ... 测试代码 ...
        
        // 在需要打印内存时，拉高触发信号
        dump_trigger = 1;
        #10;  // 等待一段时间，确保打印完成
        dump_trigger = 0;
        
        // ... 继续测试 ...
    end
    
    // ... 其他代码 ...
endmodule
```

### 2.4 打印文件位置

内存内容会被打印到以下位置：
```
temp/ram_data/<模块层级名>.txt
```

文件名使用 `%m` 自动生成，确保每个RAM实例都有唯一的文件名。

---

## 三、配置示例

### 3.1 使用IP核，不打印内存

```systemverilog
// config/global_define.sv
`timescale 1ns / 1ns

`define USE_IP
// `define PRINT_RAM  // 注释掉，不打印内存
```

### 3.2 使用RTL实现，不打印内存

```systemverilog
// config/global_define.sv
`timescale 1ns / 1ns

// `define USE_IP  // 注释掉，使用RTL实现
// `define PRINT_RAM  // 注释掉，不打印内存
```

### 3.3 使用RTL实现，启用内存打印

```systemverilog
// config/global_define.sv
`timescale 1ns / 1ns

// `define USE_IP  // 注释掉，使用RTL实现
`define PRINT_RAM  // 启用内存打印
```

**注意**：启用 `PRINT_RAM` 时，必须：
1. 未定义 `USE_IP`（使用RTL实现）
2. 修改 `single_port_ram.sv` 中的 `wait` 语句，指向正确的顶层模块
3. 在测试平台中定义 `dump_trigger` 信号

---

## 四、注意事项

1. **USE_IP 和 PRINT_RAM 的关系**：
   - `PRINT_RAM` 只对RTL实现的RAM有效
   - 如果定义了 `USE_IP`，即使定义了 `PRINT_RAM` 也不会生效（因为使用的是IP核）

2. **顶层模块名**：
   - 使用 `PRINT_RAM` 时，必须确保 `wait` 语句中的顶层模块名与实际仿真顶层模块名一致
   - 使用 `$root.<顶层模块名>.dump_trigger` 访问触发信号

3. **触发信号**：
   - 测试平台必须定义 `dump_trigger` 信号
   - 拉高 `dump_trigger` 触发打印，拉低后可以再次拉高进行多次打印

4. **文件路径**：
   - 打印文件保存在 `temp/ram_data/` 目录下
   - 确保该目录存在，否则打印会失败

---

## 五、文件结构

```
rtl/
├── config/
│   └── global_define.sv      # 全局宏定义配置文件
├── memory/
│   ├── bank_ram/
│   │   └── single_port_ram.sv  # 使用PRINT_RAM的RTL RAM实现
│   └── ...
├── common/
│   └── ...
└── README.md                   # 本文档
```
