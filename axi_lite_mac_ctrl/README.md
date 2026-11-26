# AXI4-Lite 管理接口读写控制模块（VHDL）

依据《MAC IP 核中的 AXI LITE 控制接口》（Xilinx TEMAC Management Interface 章节）提供的
信号定义、读写时序与寄存器地址映射，结合 AMBA AXI4-Lite 协议通用规则，实现了一个可综合的
**AXI4-Lite 从机读写控制模块**，并附带一个 **MAC MDIO 管理寄存器块**与**自检式 testbench**。

仿真工具：GHDL 4.1（VHDL-2008），已实际跑通 **38 项检查全部通过**。

---

## 1. 目录结构

```
axi_lite_mac_ctrl/
├── rtl/
│   ├── axi_lite_slave.vhd        # AXI4-Lite 协议从机：握手、地址译码、响应生成
│   ├── mac_mgmt_regs.vhd         # MAC 管理寄存器块（0x0500~0x050C，MDIO）
│   └── axi_lite_mac_ctrl.vhd     # 顶层：从机 + 寄存器块
├── tb/
│   └── tb_axi_lite_mac_ctrl.vhd  # 自检 testbench（读写/选通/响应/启动脉冲）
├── sim/
│   ├── run_ghdl.sh               # 一键仿真脚本（分析→精化→运行→VCD）
│   ├── plot_wave.py              # 从 VCD 生成握手时序图
│   ├── wave.vcd                  # 仿真波形（GTKWave 可打开）
│   ├── waveform.png              # 仿真时序截图
│   └── sim_log.txt               # 仿真日志
└── README.md
```

---

## 2. 从文档中提取的接口要点

### 2.1 信号（Table 12，AXI4-Lite 从机侧）

| 信号 | 方向 | 说明 |
|---|---|---|
| `s_axi_aclk` / `s_axi_aresetn` | in | AXI 时钟 / 复位（低有效） |
| `s_axi_awaddr[16:0]` | in | 写地址（AWB 端点；本设计 17 位） |
| `s_axi_awvalid` / `s_axi_awready` | in / out | 写地址握手 |
| `s_axi_wdata[31:0]` / `s_axi_wstrb[3:0]` | in | 写数据 / 字节选通 |
| `s_axi_wvalid` / `s_axi_wready` | in / out | 写数据握手 |
| `s_axi_bresp[1:0]` / `s_axi_bvalid` / `s_axi_bready` | out / out / in | 写响应 |
| `s_axi_araddr[16:0]` / `s_axi_arvalid` / `s_axi_arready` | in / in / out | 读地址 |
| `s_axi_rdata[31:0]` / `s_axi_rresp[1:0]` / `s_axi_rvalid` / `s_axi_rready` | out / out / out / in | 读数据与响应 |

### 2.2 时序（Figure 61 / 62）

* 写：AW 与 W 通道**相互独立**，可同时或先后到达；两者都握手后给出 `bvalid`，`bresp = OKAY(00)`。
* 读：`arvalid/arready` 握手后一拍给出 `rdata` 与 `rvalid`，`rresp = OKAY(00)`。
* `valid` 一旦拉高必须保持到对应 `ready` 为高（本设计满足）。

### 2.3 地址映射（Table 76 摘录）

| 地址范围 | 功能 | 本设计 |
|---|---|---|
| 0x0000–0x01FC | Reserved | 返回 SLVERR |
| 0x0200–0x03FC | Statistics | — |
| 0x0400–0x04FC | MAC Configuration | — |
| **0x0500–0x05FC** | **MDIO Interface** | **实现 0x0500–0x050C** |
| 0x0600–0x06FC | Interrupt Controller | — |
| 0x0700–0x07FC | Frame Filter | — |
| 0x10000–0x10FFC / 0x11000–0x117FC | RX/TX Packet Buffer | — |
| 0x12000–0x127FC | AXI Configuration | — |

> 说明：文档中 MDIO 区共 0x0500–0x05FC，本设计只实现 Table 40–43 明确定义的 4 个寄存器，
> 窗口大小由 `C_REG_IDX_WIDTH` 决定（默认 2 → 16 字节，即 0x0500–0x050F），窗口外返回 SLVERR。

---

## 3. 设计架构

```
                    ┌──────────────────────────── axi_lite_mac_ctrl ───────────────────────────┐
  AXI4-Lite 主机     │                                                                          │
  awaddr/awvalid ───▶│  ┌──────────────────┐   reg_wr_en/addr/data/strb   ┌──────────────────┐  │
  wdata/wstrb    ───▶│  │  axi_lite_slave  │ ───────────────────────────▶ │  mac_mgmt_regs   │  │──▶ o_mdio_en
  wvalid         ───▶│  │  · AW/W 独立握手 │                              │  · 0x0500 Setup  │  │──▶ o_mdio_clk_div
  bresp/bvalid   ◀───│  │  · 字节选通写     │   reg_rd_addr               │  · 0x0504 Control│  │──▶ o_mdio_start
  araddr/arvalid ───▶│  │  · OKAY/SLVERR   │ ◀─────────────────────────── │  · 0x0508 WData  │  │──▶ o_mdio_phyad/regad/op
  rdata/rresp    ◀───│  │  · 读数据寄存     │   reg_rd_data               │  · 0x050C RData  │  │──▶ o_mdio_wdata
  rvalid         ◀───│  └──────────────────┘                              └──────────────────┘  │◀── i_mdio_ready
                    │                                                                          │◀── i_mdio_rdata
                    └──────────────────────────────────────────────────────────────────────────┘
```

| 模块 | 职责 |
|---|---|
| `axi_lite_slave` | AXI4-Lite 协议引擎：AW/W 独立握手、写脉冲生成、B 响应、AR→R 读回、地址窗口译码、SLVERR 生成。**与具体寄存器内容无关，可整体复用。** |
| `mac_mgmt_regs` | MDIO 寄存器实现：Setup/Control/WriteData/ReadData，启动位自清、Ready 状态映射、字节选通。 |
| `axi_lite_mac_ctrl` | 顶层连线，暴露 MDIO 用户接口。 |

---

## 4. 寄存器定义（与 Table 40–43 一致）

### 0x0500 MDIO Setup Word（R/W）

| 位 | 属性 | 说明 |
|---|---|---|
| 31:7 | RO | 保留（读回 0） |
| 6 | R/W | MDIO 使能，`o_mdio_en` |
| 5:0 | R/W | MDC 时钟分频，`o_mdio_clk_div` |

### 0x0504 MDIO Control Word（R/W）

| 位 | 属性 | 说明 |
|---|---|---|
| 31:29 | RO | 保留 |
| 28:24 | R/W | PHYAD，`o_mdio_phyad` |
| 23:21 | RO | 保留 |
| 20:16 | R/W | REGAD，`o_mdio_regad` |
| 15:14 | R/W | TX_OP：0=写，1=读，`o_mdio_op` |
| 13:12 | RO | 保留 |
| 11 | WO | 写 1 启动一次 MDIO 传输，产生单周期 `o_mdio_start`，读回恒为 0（自清） |
| 10:8 | RO | 保留 |
| 7 | RO | MDIO Ready（来自 `i_mdio_ready`） |
| 6:0 | RO | 保留 |

### 0x0508 MDIO Write Data（R/W）

| 位 | 属性 | 说明 |
|---|---|---|
| 31:16 | RO | 保留 |
| 15:0 | R/W | MDIO 写数据，`o_mdio_wdata` |

### 0x050C MDIO Read Data（RO）

| 位 | 属性 | 说明 |
|---|---|---|
| 31:17 | RO | 保留 |
| 16 | RO | MDIO Ready，与 0x0504 bit7 相同 |
| 15:0 | RO | MDIO 读数据，`i_mdio_rdata` |

---

## 5. 端口说明（顶层）

| 端口 | 方向 | 位宽 | 说明 |
|---|---|---|---|
| `s_axi_aclk` | in | 1 | AXI 时钟 |
| `s_axi_aresetn` | in | 1 | 复位，低有效，异步复位 |
| `s_axi_awaddr` | in | 17 | 写地址（字节地址） |
| `s_axi_awvalid` / `awready` | in/out | 1 | 写地址握手 |
| `s_axi_wdata` / `wstrb` | in | 32 / 4 | 写数据 / 字节选通 |
| `s_axi_wvalid` / `wready` | in/out | 1 | 写数据握手 |
| `s_axi_bresp` / `bvalid` / `bready` | out/out/in | 2/1/1 | 写响应（00=OKAY，10=SLVERR） |
| `s_axi_araddr` / `arvalid` / `arready` | in/in/out | 17/1/1 | 读地址通道 |
| `s_axi_rdata` / `rresp` / `rvalid` / `rready` | out/out/out/in | 32/2/1/1 | 读数据通道 |
| `o_mdio_en` | out | 1 | MDIO 使能 |
| `o_mdio_clk_div` | out | 6 | MDC 分频 |
| `o_mdio_start` | out | 1 | 启动脉冲（单周期） |
| `o_mdio_phyad` / `o_mdio_regad` | out | 5 / 5 | PHY 地址 / 寄存器地址 |
| `o_mdio_op` | out | 1 | 0=写，1=读 |
| `o_mdio_wdata` | out | 16 | 写数据 |
| `i_mdio_ready` | in | 1 | MDIO 就绪/忙状态 |
| `i_mdio_rdata` | in | 16 | MDIO 读回数据 |

**泛型**

| 参数 | 默认值 | 说明 |
|---|---|---|
| `C_S_AXI_ADDR_WIDTH` | 17 | 与 MAC IP 的 `s_axi_awaddr[16:0]` 一致 |
| `C_BASE_ADDR` | `0x00000500` | 寄存器窗口基地址（需按窗口大小对齐） |
| `C_REG_IDX_WIDTH`（从机） | 2 | 窗口内寄存器索引位宽：2 → 4 个 32bit 寄存器 |

---

## 6. 行为与时序说明

### 6.1 写事务（约 3 拍完成一次写）

1. `IDLE`：`awready=1`、`wready=1`。
2. 主机给出 `awvalid` 与 `wvalid`（可同时或先后）：从机分别锁存地址、数据与 `wstrb`，并把对应 `ready` 拉低。
3. 地址与数据都到位后：产生一拍 `reg_wr_en` 脉冲，同时拉高 `bvalid`，`bresp` 按地址合法性给出 OKAY/SLVERR。
4. 主机给出 `bready` 后，`bvalid` 撤销，通道回到 `IDLE`。

> 地址落在窗口外时：不产生写脉冲，仅返回 `SLVERR`，寄存器内容不受影响。

### 6.2 读事务（约 3 拍）

1. `IDLE`：`arready=1`。
2. `arvalid` 握手后锁存地址、给出 `reg_rd_addr`，`arready` 拉低。
3. 下一拍锁存寄存器组合读数据，拉高 `rvalid`（此时 `rdata`/`rresp` 已有效）。
4. `rready` 握手后撤销 `rvalid`，回到 `IDLE`。若地址非法，`rresp=SLVERR`、`rdata=0`。

### 6.3 其它约定

* **字节选通**：`wstrb[i]=1` 才更新对应字节；`wstrb=0000` 时寄存器保持不变。
* **响应码**：`00=OKAY`、`10=SLVERR`；不支持 `EXOKAY/DECERR`。
* **事务能力**：单笔未完成事务（AXI-Lite 允许），不支持 Outstanding/Exclusive。
* **复位**：`s_axi_aresetn` 低有效异步复位，所有握手信号回到空闲、寄存器清零。
* **只读位**：读回时按表中定义拼装，写操作忽略。

---

## 7. 仿真验证

### 7.1 环境与命令

```bash
# GHDL 4.1+（VHDL-2008）
bash sim/run_ghdl.sh

# 查看波形（可选）
gtkwave sim/wave.vcd

# 重新生成时序截图（需要 python3 + matplotlib）
python3 sim/plot_wave.py
```

脚本内部等价于：

```bash
ghdl -a --std=08 rtl/*.vhd tb/*.vhd
ghdl -e --std=08 tb_axi_lite_mac_ctrl
ghdl -r --std=08 tb_axi_lite_mac_ctrl --vcd=sim/wave.vcd --stop-time=100us
```

### 7.2 测试用例

| # | 用例 | 预期结果 |
|---|---|---|
| 0 | 复位后通道状态 | `awready/wready/arready=1`，`bvalid/rvalid=0` |
| 1 | 写/读 0x0500 = 0x47 | 数据一致，`o_mdio_en=1`、分频=7 |
| 2 | 写/读 0x0508 = 0xA55A | 数据一致，`o_mdio_wdata=0xA55A` |
| 3 | `wstrb=0010` 写 0x0508 | 仅高字节更新为 0x125A |
| 4 | 写 0x0504 = 0x0511_4800 | 启动脉冲 1 次，PHYAD/REGAD/OP 正确，读回 bit11=0 |
| 5 | 再次写 0x0504 不置启动位 | 启动脉冲计数不增加 |
| 6 | 读 0x050C（Ready=1，数据 0x1234） | 读回 0x0001_1234 |
| 7 | Ready=0 | 0x050C bit16=0，0x0504 bit7=0 |
| 8 | 访问 0x0600 / 0x0518 | 读写均返回 SLVERR |
| 9 | `wstrb=0000` 写 0x0500 | 寄存器保持不变 |
| 10 | AW 与 W 分离到达 | 写成功，读回 0xC3D4 |

### 7.3 实测结果

```
[PASS] reset: all channels ready
[PASS] write 0x0500 Setup (resp)
[PASS] read 0x0500 Setup (data)
...
[PASS] split AW/W write 0x0508 (resp)
[PASS] read after split write (data)
=============== ALL TESTS PASSED (38 checks) ===============
```

完整日志见 `sim/sim_log.txt`，握手时序见 `sim/waveform.png`。

> 注意：GHDL 的 VHDL 源码字符串不支持 UTF-8 汉字，因此 testbench 的打印信息使用英文；
> 源码注释中的中文不影响编译。

---

## 8. 在 Vivado / ModelSim 中使用

### Vivado（xsim）

1. 将 `rtl/` 下三个 `.vhd` 加入设计源文件，`axi_lite_mac_ctrl.vhd` 设为顶层。
2. 将 `tb/tb_axi_lite_mac_ctrl.vhd` 加入仿真源文件。
3. Tcl Console：

```tcl
xvhdl --2008 rtl/axi_lite_slave.vhd
xvhdl --2008 rtl/mac_mgmt_regs.vhd
xvhdl --2008 rtl/axi_lite_mac_ctrl.vhd
xvhdl --2008 tb/tb_axi_lite_mac_ctrl.vhd
xelab -debug typical tb_axi_lite_mac_ctrl -s tb_sim
xsim tb_sim -runall
```

### ModelSim / Questa

```tcl
vlib work
vcom -2008 rtl/axi_lite_slave.vhd rtl/mac_mgmt_regs.vhd rtl/axi_lite_mac_ctrl.vhd
vcom -2008 tb/tb_axi_lite_mac_ctrl.vhd
vsim -c tb_axi_lite_mac_ctrl -do "run -all; quit"
```

### 接入 AXI 互联

* 从机接口按标准 AXI4-Lite 连接（如 Zynq PS 的 `M_AXI_GP0`、MicroBlaze 的 `M_AXI_DP`、
  AXI Interconnect / SmartConnect 的从端口）。
* 本设计只使用 32 位数据、17 位地址；若系统地址位更宽，可在顶层截取对应位，或将
  `C_S_AXI_ADDR_WIDTH` 改大并把 `C_BASE_ADDR` 设为实际基地址。
* 无低功耗接口（C 通道），如需可在外层添加。

---

## 9. 扩展方法

* **增加寄存器数量**：修改顶层 `C_REG_IDX_WIDTH`（从机泛型）并在 `mac_mgmt_regs` 的读/写
  `case` 中增加分支；窗口基地址需按 `4 × 2^C_REG_IDX_WIDTH` 对齐。
* **换成通用寄存器堆**：保留 `axi_lite_slave`，把 `mac_mgmt_regs` 替换为 N×32bit 的
  R/W 寄存器阵列即可；从机的 `reg_wr_* / reg_rd_*` 接口不依赖具体寄存器含义。
* **接 MDIO 控制器**：将 `o_mdio_start/phyad/regad/op/wdata` 接到 MDIO 主控，
  `i_mdio_ready` 接忙闲指示，`i_mdio_rdata` 接读回数据即可与文档中的 MAC 管理流程对接。

## 10. 已知限制

* 仅支持 32 位数据位宽、字对齐访问；未实现非对齐地址处理。
* 单笔未完成事务；不支持 outstanding、exclusive、QoS/低功耗信号。
* 未实现文档中其它功能块（统计、帧过滤、中断等）的寄存器，访问这些地址返回 SLVERR。
* 启动脉冲仅在 MDIO 使能时才有意义（由外部 MDIO 主控决定是否响应），本模块不做门控。
