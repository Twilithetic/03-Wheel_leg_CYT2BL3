# CYT2BL3 烧录分析报告

> 基于 Infineon 官方 Datasheet (Rev. *H, 2024-03-04) 及 TRAVEO T2G 系列技术文档
> 项目：Wheel_leg_CYT2BL3 | 芯片型号：CYT2BL3 (TRAVEO T2G Family)

---

## 一、问题分析

### 1.1 CYT2BL3 有 Flash 外设吗？

**✅ 有！CYT2BL3 内置丰富的非易失性存储器 (NVM/Flash)：**

| Flash 类型 | 容量 | 用途 |
|-----------|------|------|
| **Code Flash** | **4160 KB** (4032 KB + 128 KB) | 存储用户程序代码，支持单/双 Bank 模式 |
| **Work Flash** | **128 KB** (96 KB + 32 KB) | 存储长期数据（Flash 保护设置、校准参数等），支持单/双 Bank 模式 |
| **Supervisory Flash** | 引导加载程序专用 | 存储 Boot ROM、安全启动代码、设备配置 |
| **SRAM** | **512 KB** (前 2 KB 保留) | 运行时数据存储 |

**技术细节：**
- 所有 Flash 均支持 **SECDED ECC**（单纠错/双检错）—— 满足 ASIL-B 功能安全
- 制造工艺：Infineon 40-nm 先进工艺
- Flash 控制器基地址：**`0x4024 0000`**（FLASHC）
- 支持 **Dual-Bank** 模式，可用于 FOTA（固件空中升级）

### 1.2 用什么外设烧录？

**CYT2BL3 支持 4 种烧录通道：**

| 烧录通道 | 引脚数 | 用途 | 速率/特点 |
|---------|--------|------|----------|
| **SWD** (Serial Wire Debug) | 2 线 (SWDIO + SWCLK) | 开发调试 & 烧录 | 最常用 |
| **JTAG** (IEEE 1149.1) | 4 线 (TMS/TCK/TDI/TDO) | 调试 & 烧录 & 边界扫描 | 支持菊花链 |
| **CAN Bootloader** | CAN0_1_TX (P0.2) + CAN0_1_RX (P0.3) | 量产烧录 | 100/500 kbps |
| **LIN Bootloader** | LIN1_TX (P0.1) + LIN1_RX (P0.0) | 量产烧录 | 20/115.2 kbps |

#### 核心板烧录接口（P3 插座）

本项目核心板的 **P3** 为 **10-pin Cortex Debug Connector**（2×5 排针），引脚定义：

```
P3 (Header 5X2) - ARM Cortex Debug 接口
┌──────────────┐
│ 1  VCC3V3  │ 2  GND
│ 3  NRST    │ 4  SWDIO
│ 5  SWCLK   │ 6  (NC)
│ 7  (NC)    │ 8  (NC)
│ 9  (NC)    │ 10 (NC)
└──────────────┘
```

- **SWDIO** 和 **SWCLK** 各串接 22Ω 电阻（J1/J2）做阻抗匹配
- **NRST** 通过 10KΩ 上拉到 VCC3V3

---

## 二、烧录流程详解

### 2.1 启动/Boot 流程（关键！理解烧录的前提）

CYT2BL3 的启动流程决定了烧录的时序窗口：

```
上电复位 (POR)
    │
    ▼
┌─────────────────────────────────────┐
│ 1. CM0+ 执行 Boot ROM（掩膜ROM）       │
│    ├─ 初始化电源、时钟                  │
│    ├─ 读取 eFuse 配置                  │
│    ├─ 配置 DAP 访问限制 & 系统保护      │
│    └─ 验证 Flash Boot 签名 (SECURE 模式)│
└─────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────┐
│ 2. CM0+ 执行 Flash Boot               │
│    （从 Supervisory Flash @ 0x17002000）│
│    ├─ 配置 SWD/JTAG 引脚（从 GPIO →    │
│    │   Debug 功能）                     │
│    ├─ 设置 CM0_VTOR → Flash 起始地址   │
│    ├─ 设置 CM4_VECTOR_TABLE_BASE       │
│    │   (@ 0x00000200)                 │
│    └─ 释放 CM4 复位                    │
└─────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────┐
│ 3. CM4 从 Code Flash 或 SRAM 直接执行  │
│    (用户应用程序)                       │
└─────────────────────────────────────┘
```

**⚠️ 重点**：SWD/JTAG 引脚在复位后默认为 GPIO 模式，Boot 过程中才切换为 Debug 功能。因此**必须在 Boot 完成后才能通过 SWD 连接**。

### 2.2 Flash 编程机制（底层原理）

所有 Flash 操作（擦除/编程/读取）都通过 **CM0+ 的系统调用 (System Calls)** 实现：

```
外部调试器 (DAP)            CM0+ (IRQ0)             Flash 控制器
     │                        │                        │
     │  1. 写操作码到          │                        │
     │     IPC DATA0          │                        │
     │  (@0x08010000)        │                        │
     ├───────────────────────►│                        │
     │                        │  2. 解析操作码          │
     │                        │  3. 执行系统调用        │
     │                        ├───────────────────────►│
     │                        │  4. 擦除/编程 Flash     │
     │                        │◄───────────────────────┤
     │  5. 返回状态            │                        │
     │◄───────────────────────┤                        │
```

**系统调用流程 (以 Code Flash 编程为例)：**

```
Step 1: 获取 IPC 锁 (IPC1 ACQUIRE)
Step 2: 写 Flash 目标地址到 SRAM_SCRATCH_DATA_ADDR
Step 3: 写编程数据到 DATA0
Step 4: 写数据大小 (32-bit word) 到 DATA0
Step 5: 发送 NOTIFY 事件给 CM0+ IRQ0
Step 6: 等待 CM0+ 返回成功状态 (0xA)
Step 7: 释放 IPC 锁 (IPC1 RELEASE)
```

**IPC 结构分配：**
| IPC 结构 | 使用者 |
|----------|--------|
| IPC 0 | 保留给 CM0+ |
| IPC 1 | CM4 / DAP |
| IPC 2 | 保留 |

### 2.3 支持的烧录工具

| 厂商 | 硬件 | 软件 | 适用场景 |
|------|------|------|----------|
| **Infineon** | MiniProg3 | Infineon Programmer 1.0 | 仅 CYT2B7 |
| **Infineon** | **MiniProg4** | **Infineon Auto Flash Utility** (含 OpenOCD) | **开发推荐** |
| **SEGGER** | **J-Link** | **J-Flash** | **开发推荐** |
| SEGGER | Flasher ARM | J-Flash | 量产烧录 |
| DTS Insight | NETIMPRESS AF430 | Remote Controller AZ490 | 量产烧录 |

### 2.4 开发环境与调试器

| IDE | 调试器 | 编译器 |
|-----|--------|--------|
| **IAR EWARM** (v8.42.1+) | I-JET | IAR C/C++ Compiler |
| Green Hills MULTI (v7.1.4+) | GHS Probe (v5.6.4+) | GHS Compiler |
| ModusToolbox™ (Eclipse) | KitProg3 / J-Link | GCC ARM |

---

## 三、如何烧录 CYT2BL3

### 方案 A：使用 J-Link + J-Flash（推荐开发方式）

#### 硬件连接
```
J-Link (20-pin JTAG/SWD)  →  CYT2BL3 核心板 P3
┌──────────┐                  ┌──────────┐
│ VTref  1 │─────────────────│ VCC3V3   │
│ GND   4  │─────────────────│ GND      │
│ SWDIO  7 │───[22Ω J2]─────│ P3 Pin4  │
│ SWCLK  9 │───[22Ω J1]─────│ P3 Pin5  │
│ nRESET 15│───[10KΩ上拉]───│ P3 Pin3  │
└──────────┘                  └──────────┘
```

#### 步骤
1. 安装 SEGGER J-Link Software Pack
2. 连接 J-Link 到核心板 P3 接口
3. 上电核心板（5V → RT9013-3.3 → VCC3V3）
4. 打开 J-Flash，创建新工程
5. 选择目标设备：**Infineon → TRAVEO T2G → CYT2BL3**
6. 选择接口：**SWD**（推荐，仅 2 线）
7. 加载 .hex 或 .bin 固件文件
8. 点击 **Target → Connect** 建立连接
9. 点击 **Target → Production Programming** 执行烧录

### 方案 B：使用 Infineon Auto Flash Utility (OpenOCD)

#### 命令行烧录
```powershell
# 1. 启动 OpenOCD 服务器 (J-Link 作为调试探针)
%INFINEON_AUTO_FLASH_UTILITY_DIR%\bin\openocd ^
  -s %INFINEON_AUTO_FLASH_UTILITY_DIR%\scripts ^
  -f interface/jlink.cfg ^
  -c "transport select swd" ^
  -f target/traveo2_c2d_4m.cfg

# 2. 使用 GDB 连接并烧录
arm-none-eabi-gdb.exe firmware.elf ^
  -ex "target remote localhost:3333" ^
  -ex "monitor traveo2 reset_halt sysresetreq" ^
  -ex "load" ^
  -ex "monitor reset" ^
  -ex "quit"
```

#### 使用 KitProg3 探针
```powershell
# 如果使用 Infineon 官方开发板的 KitProg3
openocd -s scripts ^
  -f interface/kitprog3.cfg ^
  -c "transport select swd" ^
  -f target/traveo2_c2d_4m.cfg
```

### 方案 C：CAN Bootloader 烧录（量产方式）

```
┌──────────────┐         CAN Bus          ┌───────────────┐
│  烧录主机     │◄────────────────────────►│  CYT2BL3 目标板 │
│  (上位机)     │   CAN0_1: P0.2/P0.3     │               │
└──────────────┘                          └───────────────┘
```

#### CAN Bootloader 参数（来自 Datasheet §31.1）

| 参数 | 值 |
|------|-----|
| CAN 实例 | CAN0, Channel #1 |
| CAN TX 引脚 | **P0.2** (CAN0_1_TX) |
| CAN RX 引脚 | **P0.3** (CAN0_1_RX) |
| RX Message ID | **0x1A1** |
| TX Message ID | **0x1B1** |
| 波特率 | 100 kbps / 500 kbps 交替轮询 |
| 模式 | Classic CAN |
| 超时时间 | 总计 **300 秒**（无通信时，交替轮询 CAN/LIN） |

#### Bootloading 时序
```
上电 → CAN 100kbps 轮询 (10ms)
    → CAN 500kbps 轮询 (10ms)
    → LIN 20kbps 轮询 (150ms)
    → 循环...
    → 收到 Bootloader 命令 → 锁定该接口
    → 300秒内无通信 → 超时退出
```

### 方案 D：LIN Bootloader 烧录

| 参数 | 值 |
|------|-----|
| LIN 实例 | LIN0, Channel #1 |
| LIN TX 引脚 | **P0.1** (LIN1_TX) |
| LIN RX 引脚 | **P0.0** (LIN1_RX) |
| 模式 | Slave |
| TX PID | **0x46** |
| RX PID | **0x45** |
| 校验类型 | Classic |
| 波特率 | 20 kbps / 115.2 kbps |
| Break Field Length | 11 位 |
| Break Delimiter | 1 位 |

---

## 四、项目实际配置（Wheel_leg_CYT2BL3）

### 4.1 核心板调试接口

```
P3 插座 (10-pin Cortex Debug)
  Pin 1: VCC3V3   — 目标电压检测
  Pin 2: GND      — 地
  Pin 3: NRST     — 系统复位 (10KΩ 上拉至 VCC3V3)
  Pin 4: SWDIO    — 串行线数据 (22Ω 串联匹配)
  Pin 5: SWCLK    — 串行线时钟 (22Ω 串联匹配)
```

### 4.2 电源架构
```
USB 5V → F1(350mA 保险) → RT9013-3.3 LDO → VCC3V3
                                          ├─ C4 100nF (去耦)
                                          ├─ C5 47μF (储能)
                                          └─ FB1/FB2 各 120Ω 磁珠
```

### 4.3 推荐烧录方案

**开发阶段：**
- 使用 **J-Link + SWD 接口** 通过 P3 插座烧录
- 或使用 **IAR EWARM + I-JET** 一站式开发烧录

**量产阶段：**
- 使用 **CAN Bootloader**（CAN0_1：P0.2/P0.3）
- 或 **SEGGER Flasher ARM** 高速批量烧录

---

## 五、常见问题与注意事项

### 5.1 SWD 连接失败

**原因**：SWD 引脚在复位后默认为 GPIO，需等待 Boot 完成

**解决**：
1. 确保芯片供电正常（3.3V）
2. 复位后等待 >100ms 再尝试 SWD 连接
3. 使用 `monitor traveo2 reset_halt sysresetreq` 命令

### 5.2 Flash 编程失败

**原因**：
- Flash 未擦除（必须先擦除再编程）
- 系统调用返回错误状态
- 电源不稳定

**解决**：
1. 确保执行 Erase 操作后再 Program
2. 检查 CM0+ 是否正常运行
3. 确保 VCC3V3 纹波 < 50mV

### 5.3 安全注意事项

- CYT2BL3 支持 **SECURE/NORMAL 生命周期阶段**
- SECURE 模式下，Flash Boot 需要签名验证
- **eFuse 是一次性可编程 (OTP)**，配置不可逆
- Supervisory Flash 包含安全启动代码，**不可随意擦写**

---

## 六、参考资料

| 文档 | 编号 | 内容 |
|------|------|------|
| CYT2BL Datasheet | 002-28876 Rev. *H | Flash 规格、引脚定义、Bootloading |
| TRAVEO T2G TRM | v06_00 | 寄存器级别 Flash 编程细节（第33章） |
| AN220118 | Getting Started | 烧录工具列表、开发环境 |
| AN220270 | Hardware Design Guide | JTAG/SWD 接口硬件设计 |
| AN227076 | Flash Bootloader | CAN/LIN 量产烧录 |
| AN220242 | Flash Accessing Procedure | Flash 访问流程 |

---

*报告生成时间：2026-05-04 | 基于 Infineon 官方文档*
