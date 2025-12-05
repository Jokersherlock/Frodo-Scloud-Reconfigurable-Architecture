# Memory子系统接口说明

本文档说明功能模块如何访问memory文件夹下的两个数据区域：**Bank RAM** 和 **Accumulator**。

---

## 目录结构

```
memory/
├── bank_ram/          # Bank RAM子系统
│   ├── bank_ram_subsystem.sv    # 顶层子系统模块
│   ├── bank_ram_if.sv           # 接口定义
│   └── ...
├── accumulator/       # 累加器子系统
│   ├── accum_subsystem.sv       # 顶层子系统模块
│   ├── accumulator_if.sv        # 接口定义
│   └── ...
└── README.md         # 本文档
```

---

## 一、Bank RAM区域访问

### 1.1 接口要求

功能模块需要提供 **Master** 接口来访问 Bank RAM 子系统：

```systemverilog
// 命令接口
Bank_Cmd_If.Master cmd_if;

// 数据接口
Bank_Data_If.Master data_if;
```

### 1.2 接口信号定义

#### Bank_Cmd_If（命令接口）

| 信号 | 方向 | 位宽 | 说明 |
|------|------|------|------|
| `valid` | 输出 | 1 | 请求有效信号 |
| `ready` | 输入 | 1 | 子系统准备好接收请求 |
| `rw` | 输出 | 1 | 操作类型：0=读，1=写 |
| `mask` | 输出 | NUM_BANKS | Bank掩码，指定访问哪些Bank（默认NUM_BANKS=5） |
| `addr` | 输出 | ADDR_WIDTH | 地址（默认ADDR_WIDTH=9） |

#### Bank_Data_If（数据接口）

**写数据通道：**
| 信号 | 方向 | 位宽 | 说明 |
|------|------|------|------|
| `wvalid` | 输出 | 1 | 写数据有效 |
| `wready` | 输入 | 1 | 子系统准备好接收写数据 |
| `wdata` | 输出 | NUM_BANKS × DATA_WIDTH | 写数据（默认DATA_WIDTH=32） |

**读数据通道：**
| 信号 | 方向 | 位宽 | 说明 |
|------|------|------|------|
| `rvalid` | 输入 | 1 | 读数据有效 |
| `rdata` | 输入 | NUM_BANKS × DATA_WIDTH | 读数据 |

### 1.3 连接示例

```systemverilog
module my_functional_module (
    input logic clk,
    input logic rstn,
    // 连接到Bank RAM子系统
    Bank_Cmd_If.Master  bank_cmd_if,
    Bank_Data_If.Master bank_data_if
);

    // 实例化接口（在顶层模块中）
    Bank_Cmd_If  bank_cmd (clk, rstn);
    Bank_Data_If bank_data (clk, rstn);
    
    // 连接
    assign bank_cmd_if = bank_cmd.Master;
    assign bank_data_if = bank_data.Master;
    
    // 在顶层实例化子系统
    bank_ram_subsystem #(
        .NUM_SLOTS(4),      // 支持4个Master
        .FIFO_DEPTH(4),
        .NUM_BANKS(5),
        .ADDR_WIDTH(9),
        .DATA_WIDTH(32),
        .RAM_LATENCY(2)
    ) u_bank_ram (
        .clk(clk),
        .rstn(rstn),
        .cmd_slots({bank_cmd.Slave, ...}),  // 连接到多个Master
        .data_slots({bank_data.Slave, ...})
    );
endmodule
```

### 1.4 访问协议

#### 写操作流程：
1. 驱动 `cmd_if.valid = 1`，设置 `rw = 1`，`mask`，`addr`
2. 等待 `cmd_if.ready = 1`（握手完成）
3. 驱动 `data_if.wvalid = 1`，提供 `wdata`
4. 等待 `data_if.wready = 1`（数据写入完成）

#### 读操作流程：
1. 驱动 `cmd_if.valid = 1`，设置 `rw = 0`，`mask`，`addr`
2. 等待 `cmd_if.ready = 1`（握手完成）
3. 等待 `data_if.rvalid = 1`（读数据有效）
4. 读取 `data_if.rdata`

### 1.5 注意事项

- **优先级仲裁**：多个Master同时访问时，Slot 0优先级最高，依次递减
- **写数据延迟**：写数据可以在命令握手后延迟提供（通过FIFO缓冲）
- **旁路优化**：当FIFO为空且数据同步到达时，支持0延迟旁路写入

---

## 二、Accumulator区域访问

### 2.1 接口要求

功能模块需要提供 **Master** 接口来访问 Accumulator 子系统。Accumulator支持两种访问模式：

#### 模式1：路由访问（Routed Access）
通过 `zone_id` 路由到不同的Zone，适合需要动态选择Zone的场景。

#### 模式2：直连访问（Direct Access）
直接连接到特定Zone，适合固定Zone访问的场景。

### 2.2 接口信号定义

#### Accum_Cmd_If（命令接口）

**写命令通道：**
| 信号 | 方向 | 位宽 | 说明 |
|------|------|------|------|
| `wr_valid` | 输出 | 1 | 写命令有效 |
| `wr_ready` | 输入 | 1 | 子系统准备好接收写命令 |
| `wr_zone_id` | 输出 | ZONE_WIDTH | Zone ID（路由模式必需，默认ZONE_WIDTH=2，支持4个Zone） |
| `accum_en` | 输出 | 1 | 累加使能：0=覆盖写，1=累加写 |
| `wr_mask` | 输出 | NUM_BANKS | Bank掩码（默认NUM_BANKS=4） |
| `wr_addr` | 输出 | ADDR_WIDTH | 写地址（默认ADDR_WIDTH=9） |

**读命令通道：**
| 信号 | 方向 | 位宽 | 说明 |
|------|------|------|------|
| `rd_valid` | 输出 | 1 | 读命令有效 |
| `rd_ready` | 输入 | 1 | 子系统准备好接收读命令 |
| `rd_zone_id` | 输出 | ZONE_WIDTH | Zone ID（路由模式必需） |
| `rd_mask` | 输出 | NUM_BANKS | Bank掩码 |
| `rd_addr` | 输出 | ADDR_WIDTH | 读地址 |

#### Accum_Data_If（数据接口）

**写数据通道：**
| 信号 | 方向 | 位宽 | 说明 |
|------|------|------|------|
| `wvalid` | 输出 | 1 | 写数据有效 |
| `wready` | 输入 | 1 | 子系统准备好接收写数据 |
| `wdata` | 输出 | NUM_BANKS × DATA_WIDTH | 写数据（默认DATA_WIDTH=64） |

**读数据通道：**
| 信号 | 方向 | 位宽 | 说明 |
|------|------|------|------|
| `rvalid` | 输入 | 1 | 读数据有效 |
| `rdata` | 输入 | NUM_BANKS × DATA_WIDTH | 读数据 |

### 2.3 连接示例

#### 路由访问模式：

```systemverilog
module my_functional_module (
    input logic clk,
    input logic rstn,
    // 路由访问接口
    Accum_Cmd_If.Master  accum_cmd_if,
    Accum_Data_If.Master accum_data_if
);

    // 实例化接口
    Accum_Cmd_If #(
        .NUM_BANKS(4),
        .ADDR_WIDTH(9),
        .ZONE_WIDTH(2)
    ) accum_cmd (clk, rstn);
    
    Accum_Data_If #(
        .NUM_BANKS(4),
        .DATA_WIDTH(64)
    ) accum_data (clk, rstn);
    
    // 连接
    assign accum_cmd_if = accum_cmd.Master;
    assign accum_data_if = accum_data.Master;
    
    // 在顶层实例化子系统
    Accum_Subsystem #(
        .FIFO_DEPTH(4),
        .NUM_BANKS(4),
        .ADDR_WIDTH(9),
        .DATA_WIDTH(64),
        .ZONE_WIDTH(2),
        .NUM_ROUTED_MASTERS(1)  // 路由Master数量
    ) u_accum (
        .clk(clk),
        .rstn(rstn),
        .routed_cmd_ports({accum_cmd}),   // 路由接口
        .routed_data_ports({accum_data}),
        .direct_cmd_ports({...}),          // 直连接口（可选）
        .direct_data_ports({...})
    );
endmodule
```

#### 直连访问模式：

```systemverilog
    // 直连访问：直接连接到Zone 0
    Accum_Cmd_If #(...) direct_cmd_zone0 (clk, rstn);
    Accum_Data_If #(...) direct_data_zone0 (clk, rstn);
    
    // 在顶层连接
    Accum_Subsystem u_accum (
        ...
        .direct_cmd_ports({direct_cmd_zone0, ...}),  // Zone 0, 1, 2, 3
        .direct_data_ports({direct_data_zone0, ...})
    );
```

### 2.4 访问协议

#### 写操作流程（覆盖模式）：
1. 驱动 `cmd_if.wr_valid = 1`，设置 `wr_zone_id`（路由模式），`accum_en = 0`，`wr_mask`，`wr_addr`
2. 等待 `cmd_if.wr_ready = 1`（握手完成）
3. 驱动 `data_if.wvalid = 1`，提供 `wdata`
4. 等待 `data_if.wready = 1`（数据写入完成）

#### 写操作流程（累加模式）：
1. 驱动 `cmd_if.wr_valid = 1`，设置 `wr_zone_id`，`accum_en = 1`，`wr_mask`，`wr_addr`
2. 等待 `cmd_if.wr_ready = 1`
3. 驱动 `data_if.wvalid = 1`，提供 `wdata`（将与现有数据累加）
4. 等待 `data_if.wready = 1`

#### 读操作流程：
1. 驱动 `cmd_if.rd_valid = 1`，设置 `rd_zone_id`（路由模式），`rd_mask`，`rd_addr`
2. 等待 `cmd_if.rd_ready = 1`（握手完成）
3. 等待 `data_if.rvalid = 1`（读数据有效）
4. 读取 `data_if.rdata`

### 2.5 注意事项

- **Zone路由**：路由模式下，`zone_id` 决定访问哪个Zone（0到2^ZONE_WIDTH-1）
- **累加功能**：`accum_en = 1` 时，写入的数据会与现有数据累加（而非覆盖）
- **双端口访问**：支持同时进行读写操作（通过Port A写，Port B读）
- **优先级仲裁**：每个Zone内部，Direct Master（Slot 0）优先级高于Routed Master（Slot 1+）
- **写数据延迟**：写数据可以在命令握手后延迟提供（通过FIFO缓冲）

---

## 三、同时访问两个区域

### 3.1 接口要求

功能模块需要同时提供两套Master接口：

```systemverilog
module my_functional_module (
    input logic clk,
    input logic rstn,
    // Bank RAM接口
    Bank_Cmd_If.Master  bank_cmd_if,
    Bank_Data_If.Master bank_data_if,
    // Accumulator接口（路由模式）
    Accum_Cmd_If.Master  accum_cmd_if,
    Accum_Data_If.Master accum_data_if
);
```

### 3.2 参数配置

两个子系统的参数可能不同，需要根据实际需求配置：

| 参数 | Bank RAM | Accumulator | 说明 |
|------|----------|-------------|------|
| NUM_BANKS | 5 | 4 | Bank数量 |
| DATA_WIDTH | 32 | 64 | 数据位宽 |
| ADDR_WIDTH | 9 | 9 | 地址位宽 |
| NUM_SLOTS | 4 | - | Master插槽数 |
| ZONE_WIDTH | - | 2 | Zone ID位宽 |

### 3.3 完整连接示例

```systemverilog
module top_module (
    input logic clk,
    input logic rstn
);

    // ============================================
    // 1. 接口实例化
    // ============================================
    
    // Bank RAM接口
    Bank_Cmd_If  bank_cmd [4] (clk, rstn);
    Bank_Data_If bank_data [4] (clk, rstn);
    
    // Accumulator接口（路由模式）
    Accum_Cmd_If #(.NUM_BANKS(4), .ADDR_WIDTH(9), .ZONE_WIDTH(2))
        accum_routed_cmd [1] (clk, rstn);
    Accum_Data_If #(.NUM_BANKS(4), .DATA_WIDTH(64))
        accum_routed_data [1] (clk, rstn);
    
    // Accumulator接口（直连模式）
    Accum_Cmd_If #(.NUM_BANKS(4), .ADDR_WIDTH(9), .ZONE_WIDTH(2))
        accum_direct_cmd [4] (clk, rstn);
    Accum_Data_If #(.NUM_BANKS(4), .DATA_WIDTH(64))
        accum_direct_data [4] (clk, rstn);
    
    // ============================================
    // 2. 功能模块实例化
    // ============================================
    my_functional_module u_func (
        .clk(clk),
        .rstn(rstn),
        .bank_cmd_if(bank_cmd[0].Master),
        .bank_data_if(bank_data[0].Master),
        .accum_cmd_if(accum_routed_cmd[0].Master),
        .accum_data_if(accum_routed_data[0].Master)
    );
    
    // ============================================
    // 3. 子系统实例化
    // ============================================
    
    // Bank RAM子系统
    bank_ram_subsystem #(
        .NUM_SLOTS(4),
        .FIFO_DEPTH(4),
        .NUM_BANKS(5),
        .ADDR_WIDTH(9),
        .DATA_WIDTH(32),
        .RAM_LATENCY(2)
    ) u_bank_ram (
        .clk(clk),
        .rstn(rstn),
        .cmd_slots({bank_cmd[0].Slave, bank_cmd[1].Slave, 
                    bank_cmd[2].Slave, bank_cmd[3].Slave}),
        .data_slots({bank_data[0].Slave, bank_data[1].Slave,
                     bank_data[2].Slave, bank_data[3].Slave})
    );
    
    // Accumulator子系统
    Accum_Subsystem #(
        .FIFO_DEPTH(4),
        .NUM_BANKS(4),
        .ADDR_WIDTH(9),
        .DATA_WIDTH(64),
        .ZONE_WIDTH(2),
        .NUM_ROUTED_MASTERS(1)
    ) u_accum (
        .clk(clk),
        .rstn(rstn),
        .routed_cmd_ports(accum_routed_cmd),
        .routed_data_ports(accum_routed_data),
        .direct_cmd_ports(accum_direct_cmd),
        .direct_data_ports(accum_direct_data)
    );

endmodule
```

### 3.4 访问时序

两个区域可以**独立并行访问**，互不影响：

- Bank RAM和Accumulator的访问完全独立
- 可以在同一时钟周期内同时发起对两个区域的访问
- 每个区域内部有独立的仲裁和FIFO管理

---

## 四、接口文件位置

| 接口文件 | 路径 | 说明 |
|----------|------|------|
| `Bank_Cmd_If` | `bank_ram/bank_ram_if.sv` | Bank RAM命令接口 |
| `Bank_Data_If` | `bank_ram/bank_ram_if.sv` | Bank RAM数据接口 |
| `Accum_Cmd_If` | `accumulator/accumulator_if.sv` | Accumulator命令接口 |
| `Accum_Data_If` | `accumulator/accumulator_if.sv` | Accumulator数据接口 |
| `ram_if` | `ram_if.sv` | 底层RAM接口（内部使用） |

---

## 五、总结

### 访问Bank RAM区域：
1. 提供 `Bank_Cmd_If.Master` 和 `Bank_Data_If.Master` 接口
2. 通过 `valid/ready` 握手协议进行命令和数据传输
3. 使用 `mask` 指定访问的Bank，`rw` 指定读写操作

### 访问Accumulator区域：
1. 提供 `Accum_Cmd_If.Master` 和 `Accum_Data_If.Master` 接口
2. 选择路由模式（通过`zone_id`）或直连模式（固定Zone）
3. 通过 `accum_en` 选择覆盖写或累加写
4. 支持双端口同时读写

### 同时访问两个区域：
- 需要两套独立的Master接口
- 两个区域可以并行访问，互不干扰
- 根据实际需求配置各自的参数

---

## 六、参考示例

更多使用示例请参考：
- `src/sim/tb_bank_ram_subsystem.sv` - Bank RAM测试平台
- `src/sim/tb_accum_subsystem.sv` - Accumulator测试平台
