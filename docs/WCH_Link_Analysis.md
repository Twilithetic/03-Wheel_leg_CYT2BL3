# USB 设备分析报告：WCH-Link CMSIS-DAP 调试器

> **分析日期**: 2026-05-05  
> **USB 端口**: Port3 (1-3)  
> **Serial Number**: F3EE7D40070E  
> **分析工具**: USB Device Viewer (Windows) + 联网交叉验证  

---

## 一、问题描述

在电脑 USB Port3 上连接了一个 `WCH-Link` 设备，需要识别：
1. 具体是什么设备、什么芯片
2. 使用的通信接口协议
3. 是否支持 SWD 调试
4. 能否用于 CYT2BL3 项目开发

---

## 二、USB 枚举信息摘要

| 字段 | 值 | 含义 |
|------|-----|------|
| **Vendor ID** | `0x1A86` | **Nanjing Qinheng Microelectronics Co., Ltd.**（南京沁恒微电子 / WCH） |
| **Product ID** | `0x8012` | WCH-Link（**ARM WINUSB / CMSIS-DAP v2 模式**） |
| **Product String** | `"WCH-Link"` | 产品名 |
| **Manufacturer String** | `"wch.cn"` | WCH 官网 |
| **Serial Number** | `F3EE7D40070E` | 唯一序列号 |
| **USB Version** | `2.0`（Full-Speed, 12 Mbit/s） | 全速 USB 2.0 |
| **bDeviceClass** | `0xEF`（Miscellaneous） | 复合设备（IAD） |
| **bDeviceProtocol** | `0x01`（IAD） | 使用 Interface Association Descriptor |
| **Demanded Current** | `500 mA` | 总线供电 500mA |
| **Used Endpoints** | `6` | 6 个数据传输端点 |
| **Open Pipes** | `5` | 5 个已打开的数据管道 |

---

## 三、芯片详细分析

### 3.1 主控芯片：CH549F

通过查阅多个可靠来源交叉验证：

| 来源 | 关键信息 |
|------|---------|
| [GitHub - kaidegit/CMSIS-DAPbyWCH](https://github.com/kaidegit/CMSIS-DAPbyWCH) | "主控 MCU 是 CH549F，可能是最便宜的 CMSIS-DAP 调试器" |
| [WCH-Link User Manual (V1.6)](https://akizukidenshi.com/goodsaffix/WCH-LinkUserManual.pdf) | WCH 官方使用手册，确认硬件架构 |
| [ch32-rs/openocd-wchlink-firmware](https://github.com/ch32-rs/openocd-wchlink-firmware) | OpenOCD 对 WCH-Link 的支持，固件版本 V2.4/V2.5 |
| [probe-rs Issue #995](https://github.com/probe-rs/probe-rs/issues/995) | probe-rs 社区讨论 WCH-Link 兼容性 |

**结论：主控芯片为 WCH 自研的 CH549F，一颗带 USB 2.0 Full-Speed 的 8 位增强型 MCU。**

> CH549F 是 WCH（南京沁恒）自家的芯片，具备 USB 2.0 Full-Speed 控制器，非常适合做 USB 调试器。

### 3.2 芯片架构

```
┌──────────────────────────────────────────────────┐
│              WCH-Link 调试器                       │
│                                                    │
│  ┌────────────────────────────────────────────┐   │
│  │          CH549F (8-bit Enhanced MCU)        │   │
│  │                                              │   │
│  │  ┌──────────┐   ┌──────────────────────┐    │   │
│  │  │  CPU     │   │  USB 2.0 FS           │    │   │
│  │  │  E8051   │◄──┤  Composite Device     │    │   │
│  │  │  Core    │   │  ├─ CMSIS-DAP (WINUSB)│    │   │
│  │  └──────────┘   │  └─ CDC ACM (COM Port)│    │   │
│  │                  └──────────────────────┘    │   │
│  │  ┌──────────┐                               │   │
│  │  │  GPIO    │──► SWD 接口 (SWCLK, SWDIO)    │   │
│  │  │  UART    │──► 虚拟串口 (TX, RX)          │   │
│  │  └──────────┘                               │   │
│  └────────────────────────────────────────────┘   │
│                                                    │
│  LED 指示灯:                                       │
│  ├─ 蓝灯常亮 = ARM CMSIS-DAP 模式                 │
│  └─ 蓝灯熄灭 = RISC-V 模式                        │
│                                                    │
│  ModeS 按键: 长按切换 ARM/RISC-V 模式             │
└──────────────────────────────────────────────────┘
```

---

## 四、通信接口详细分析

### 4.1 USB 复合设备结构（3 个接口）

WCH-Link 是一个 **USB 复合设备（Composite Device）**，使用 IAD（Interface Association Descriptor）将多个功能绑定在一起：

```
┌─────────────────────────────────────────────────────┐
│              USB Composite Device                    │
│              WCH-Link (VID=1A86, PID=8012)           │
├─────────────────────────────────────────────────────┤
│                                                      │
│  Interface 0: CMSIS-DAP Debug Probe                 │
│  ├─ Class: 0xFF (Vendor Specific)                   │
│  ├─ String: "WCH CMSIS-DAP"                         │
│  ├─ Endpoint 0x02 (OUT, Bulk, 64B)                  │
│  ├─ Endpoint 0x83 (IN,  Bulk, 64B)                  │
│  └─ 协议: CMSIS-DAP v2 (WINUSB / Bulk)              │
│                                                      │
│  ─── IAD (Interface Association Descriptor) ───     │
│  ├─ Interface 1 + 2 = CDC ACM (虚拟串口)            │
│  │                                                    │
│  ├─ Interface 1: CDC Data                           │
│  │   ├─ Class: 0x0A (CDC-Data)                      │
│  │   ├─ Endpoint 0x03 (OUT, Bulk, 64B)              │
│  │   └─ Endpoint 0x81 (IN,  Bulk, 64B)              │
│  │                                                    │
│  └─ Interface 2: CDC Control                        │
│      ├─ Class: 0x02 (Communications)                │
│      ├─ SubClass: 0x02 (Abstract Control Model)     │
│      ├─ Endpoint 0x84 (IN, Interrupt, 64B)          │
│      └─ 功能: 虚拟 COM 口 (COM9)                     │
│                                                      │
└─────────────────────────────────────────────────────┘
```

### 4.2 CMSIS-DAP 协议详解

**CMSIS-DAP**（Cortex Microcontroller Software Interface Standard - Debug Access Port）是 ARM 定义的一个**厂商中立、标准化**的调试探针协议。

| 特性 | 说明 |
|------|------|
| **协议版本** | CMSIS-DAP v2（使用 Bulk 端点的 WINUSB 模式） |
| **传输模式** | WINUSB（Bulk transfer），比 HID 模式快得多 |
| **调试接口** | SWD（2 线）、JTAG（4 线） |
| **支持架构** | ARM Cortex-M0/M3/M4/M7/M23/M33 等全部 Cortex-M 系列 |
| **支持架构** | 切换模式后也支持 RISC-V（WCH 自家芯片） |
| **兼容工具** | OpenOCD、pyOCD、probe-rs、Keil MDK、IAR、MounRiver Studio |

#### 4.2.1 CMSIS-DAP 是什么？（深入解析）

##### 一句话定义

> **CMSIS-DAP** 是 ARM 官方定义的"**调试探针与主机之间的 USB 通信协议标准**"，让调试器通过 USB 把芯片内部的 **CoreSight Debug Access Port (DAP)** 暴露给 PC 上的调试工具。

##### 生动类比：翻译官

```
┌──────────────┐                    ┌──────────────┐                    ┌──────────────┐
│   你的电脑    │   USB (CMSIS-DAP)  │   调试探针    │   SWD/JTAG        │   目标芯片    │
│  OpenOCD     │ ◄════════════════►│  WCH-Link    │ ◄═══════════════► │  CYT2BL3     │
│  pyOCD       │    "标准化翻译协议"  │  (翻译官)    │   芯片内部语言      │  (Cortex-M4) │
│  Keil MDK    │                    │              │                   │              │
└──────────────┘                    └──────────────┘                   └──────────────┘
```

- 电脑说："帮我读一下地址 `0x20000000` 的值"
- CMSIS-DAP 协议把这个请求打包成 USB 命令发给探针
- 探针通过 SWD 协议跟芯片内部的 DAP 沟通，拿到数据
- 探针再通过 CMSIS-DAP 协议把结果返回给电脑

##### 为什么需要 CMSIS-DAP？（历史背景）

在 CMSIS-DAP 出现之前，调试器市场是这样的：

| 调试器 | 厂家 | 协议 | 能调谁的芯片？ |
|--------|------|------|--------------|
| ST-Link | ST | ST 私有协议 | **只**能调 STM32 |
| J-Link | SEGGER | SEGGER 私有协议 | 很多芯片（闭源收费） |
| ULINK | ARM | ARM 私有协议 | Cortex-M（需 Keil） |
| ICDI | TI | TI 私有协议 | 只能调 TI 芯片 |
| P&E Micro | NXP | 私有协议 | 只能调 NXP 芯片 |

**碎片化严重！** 每个调试工具（OpenOCD、pyOCD 等）都必须为每种私有协议写适配代码。

ARM 站出来说："**大家都用 CMSIS-DAP 这一套标准吧，开源免费，我来维护！**"

##### 协议分层架构

```
┌──────────────────────────────────────────────┐
│        GDB / IDE (Keil, VSCode, IAR...)      │  ← 用户界面
├──────────────────────────────────────────────┤
│      OpenOCD / pyOCD / probe-rs              │  ← 调试服务器 (GDB Server)
│      (把 GDB 命令翻译成 CMSIS-DAP 命令)        │
├──────────────────────────────────────────────┤
│  ★ CMSIS-DAP 协议 (USB 通信层) ★              │  ← ARM 官方标准
│  ├─ v1: USB HID (64字节包, 无需驱动)          │     WCH-Link 在此层
│  └─ v2: WINUSB Bulk (高速, 免驱)              │
│                                               │
│  核心命令类型:                                  │
│  ├─ General Commands    连接/断开/信息查询      │
│  ├─ SWD/JTAG Commands   配置接口/时钟速度       │
│  ├─ Transfer Commands   读写 CoreSight 寄存器   │
│  └─ SWO Commands        串行线输出追踪          │
├──────────────────────────────────────────────┤
│         SWD (2线) / JTAG (5线)               │  ← 物理调试接口
├──────────────────────────────────────────────┤
│  CoreSight Debug Access Port (DAP)           │  ← 芯片内部调试硬件
│  ├─ DP (Debug Port) : SWD/JTAG 物理层接口    │
│  │   └─ 寄存器: IDCODE, CTRL/STAT, SELECT... │
│  └─ AP (Access Port) : 访问芯片内部资源       │
│      ├─ MEM-AP  → 内存、Flash、外设寄存器     │
│      └─ 其他 AP → 追踪、安全等                │
└──────────────────────────────────────────────┘
```

##### CMSIS-DAP v1 vs v2

| 对比维度 | v1 (HID) | v2 (WINUSB/Bulk) ← WCH-Link 用的 |
|---------|----------|--------------------------------|
| **USB 传输** | HID (中断传输) | Bulk (批量传输) |
| **每次传输** | 最大 64 字节 | 最大 512 字节（HS可达更大） |
| **速度** | 慢（受 HID 轮询限制） | 快（充分利用 USB 带宽） |
| **驱动** | 系统自带 HID 驱动 | Win10+ 自带 WinUSB，免驱 |
| **SWO 追踪** | 不支持高速 SWO | 支持高速 SWO 流 |
| **推荐使用** | 已弃用 | ✅ 当前推荐 |

##### CoreSight DAP 内部结构（深入）

这是芯片内部调试硬件的架构，理解它有助于理解调试器到底在做什么：

```
                    ┌───────────────────────────────┐
  SWCLK ──────────►│                               │
  SWDIO ◄─────────►│  Debug Port (DP)              │
                    │  ├─ IDCODE: 芯片识别码         │
                    │  ├─ CTRL/STAT: 控制和状态      │
                    │  ├─ SELECT: 选择 AP 和寄存器   │
                    │  └─ RDBUFF: 读数据缓冲         │
                    └───────────┬───────────────────┘
                                │ (内部总线)
                    ┌───────────┴───────────────────┐
                    │  Access Port (AP)             │
                    │  ├─ MEM-AP  ──► AHB 总线       │
                    │  │   └─► Flash, SRAM, 外设     │
                    │  ├─ APB-AP  ──► APB 总线       │
                    │  │   └─► CoreSight 组件:       │
                    │  │       ├─ DWT (数据观察点)    │
                    │  │       ├─ FPB (Flash 断点)    │
                    │  │       ├─ ITM (指令追踪)      │
                    │  │       └─ ETM (嵌入式追踪)    │
                    │  └─ JTAG-AP ──► JTAG 链        │
                    └────────────────────────────────┘
```

**调试过程实例**（设置一个断点）：
1. 主机通过 CMSIS-DAP 命令 → "写 MEM-AP 寄存器"
2. 探针通过 SWD → "写 DP.SELECT 选择 MEM-AP，写 FPB 比较器"
3. 芯片内部 FPB 设置完成 → 当 PC 到达断点地址时自动暂停 CPU
4. 探针轮询 DP.CTRL/STAT → 检测到 halted 状态
5. CMSIS-DAP → 通知主机"目标已暂停"

#### 4.2.2 CMSIS-DAP 官方资源（可下载的文档和源码）

ARM 将 CMSIS-DAP **完全开源**（Apache 2.0 许可证），以下资源均可免费获取：

| 序号 | 资源 | 链接 | 内容 |
|------|------|------|------|
| **1** | **CMSIS-DAP GitHub 仓库（官方）** | https://github.com/ARM-software/CMSIS-DAP | ⭐ 完整源码 + 文档 + 示例固件 + 验证脚本 |
| **2** | **CMSIS-DAP 在线文档** | https://arm-software.github.io/CMSIS-DAP/latest/ | USB 命令详解、固件配置指南、驱动安装说明 |
| **3** | **CMSIS-DAP USB 命令参考** | https://arm-software.github.io/CMSIS-DAP/latest/group__DAP__Commands__gr.html | 所有 CMSIS-DAP 命令的详细规范 |
| **4** | **ARM Debug Interface 规范 (ADIv5)** | https://developer.arm.com/ （需注册 ARM 账号） | SWD/JTAG 底层协议的完整规范 |
| **5** | **CoreSight DAP 官方文档** | https://developer.arm.com/documentation/102585/ | Debug Access Port 架构详解 |
| **6** | **Mbed CMSIS-DAP Handbook** | https://os.mbed.com/handbook/CMSIS-DAP | 通俗易懂的入门教程 |
| **7** | **CMSIS 6 主文档** | https://arm-software.github.io/CMSIS_6/latest/DAP/index.html | CMSIS 生态中 DAP 组件的介绍 |

**GitHub 仓库目录结构**：
```
CMSIS-DAP/                      ← ⭐ 最推荐从这里开始
├── Documentation/              ← 📖 协议文档 (Doxygen)
├── Firmware/                   ← 💻 完整固件源码
│   ├── Config/                 ← 固件配置模板
│   ├── Examples/               ← 各种开发板适配示例
│   ├── Include/                ← 头文件
│   ├── Source/                 ← CMSIS-DAP 核心源码
│   └── Template/               ← USB 中间件接口模板
├── LICENSE                     ← Apache 2.0（完全免费！）
└── README.md
```

> 💡 **姐姐建议**：如果想深入理解调试器是怎么工作的，clone 下来看 `Firmware/Source/` 目录，核心逻辑就几百行 C 代码，ARM 写得很清晰！

#### 4.2.3 CMSIS-DAP vs 其他调试协议

##### CMSIS-DAP 与 ST-Link V2 的关系

**ST-Link V2 用的不是 CMSIS-DAP！这是两个完全不同的协议。**

| 对比维度 | **ST-Link V2** | **CMSIS-DAP** (WCH-Link / DAPLink) |
|---------|---------------|----------------------------------|
| **协议制定者** | STMicroelectronics（私有、闭源） | **ARM Ltd.**（开放标准、开源） |
| **USB 通信协议** | **ST-LINK 私有协议** | **CMSIS-DAP 标准协议** |
| **USB 传输方式** | ST 自定义 Bulk 传输 | HID (v1) / WINUSB Bulk (v2) |
| **支持芯片** | **仅 STM32 / STM8** | **所有 ARM Cortex-M** + 部分 RISC-V |
| **能否烧 GD32/APM32** | ❌ 克隆版固件通常不行 | ✅ 只要是 Cortex-M 就能用 |
| **源码开放** | ❌ 完全闭源 | ✅ Apache 2.0 开源 |
| **驱动** | 需安装 ST 专用驱动 | v2 版 Win10+ 免驱（WinUSB） |
| **支持工具** | STM32CubeIDE, ST-LINK Utility | **OpenOCD, pyOCD, probe-rs, Keil, IAR, PlatformIO...** |

##### ST-Link 版本的协议变迁

```
ST-Link V1    → ST 私有协议 (仅 STM32)
ST-Link V2    → ST 私有协议 (仅 STM32, 仍是自己的协议！)
ST-Link V2-1  → ST 私有协议 + 虚拟串口 + 大容量存储
ST-Link V3    → ST 私有协议 + ★原生 CMSIS-DAP v2 支持★
```

> 到了 ST-Link V3，ST 终于加入了原生 CMSIS-DAP v2，但 ST 自家的协议仍是主力。

##### 有趣的事实：可以把 ST-Link V2 硬件"变成" CMSIS-DAP！

虽然 ST-Link V2 固件不支持 CMSIS-DAP，但它的主控芯片是 **STM32F103C8**（Cortex-M3），社区有人把 CMSIS-DAP 固件移植上去了：

- 🔧 **CMSIS-DAP port to STM32/ST-Link V2**：http://akb77.com/g/stm32/cmsis-dap/
- 🔧 **在 ST-Link V2 Mini 上运行 CMSIS-DAP**：https://mvdlande.wordpress.com/2015/10/05/cmsis-dap-on-a-cheap-st-link-v2-mini-adapter/

刷完固件后，ST-Link V2 硬件就变成了一台 CMSIS-DAP 调试器，可以调试任何 ARM Cortex-M 芯片！

##### 三大调试器家族对比

| 对比维度 | **CMSIS-DAP** | **ST-Link** | **J-Link** |
|---------|-------------|------------|-----------|
| **厂家** | ARM (开源标准) | ST (闭源) | SEGGER (商业) |
| **协议** | CMSIS-DAP 开放标准 | ST-LINK 私有协议 | J-Link 私有协议 |
| **源码** | ✅ Apache 2.0 | ❌ 闭源 | ❌ 闭源 |
| **芯片支持** | 🌍 所有 Cortex-M | 🏠 仅 STM32/STM8 | 🌍 几乎所有 ARM |
| **价格** | 💰 $3-10 | 💰 $2-20 | 💰💲 $60-1000 |
| **高级功能** | 基础调试 + SWO | 基础调试 + SWV | 无限断点、ETM 追踪、性能分析 |
| **你的 WCH-Link** | ✅ 就是这个！ | ❌ | ❌ |

##### 一句话总结

```
调试世界三大家族：

🏠 ST-Link → ST 家的（只进 STM32 的门，私有协议）
🏢 J-Link  → SEGGER 家的（支持很多芯片，私有协议收费，也兼容 CMSIS-DAP）
🌍 CMSIS-DAP → ARM 官方开源标准（谁家芯片都能进，免费开源！）
               ↑ 你的 WCH-Link 用的就是它！
```

**CMSIS-DAP 协议栈（完整版）：**
```
┌─────────────────┐
│  GDB / IDE      │  (Keil, VSCode, MounRiver...)
├─────────────────┤
│  OpenOCD/pyOCD  │  (调试服务器)
├─────────────────┤
│  CMSIS-DAP      │  (USB 调试协议) ← WCH-Link 在此层
├─────────────────┤
│  SWD / JTAG     │  (物理调试接口)
├─────────────────┤
│  Cortex-M4F     │  (CYT2BL3 目标芯片)
└─────────────────┘
```

### 4.3 WCH-Link 模式切换

WCH-Link 有多种工作模式，通过 **PID** 区分：

| PID | 模式名称 | 用途 | 蓝灯状态 |
|-----|---------|------|---------|
| `0x8010` | **WCH-LinkRV** (RISC-V) | 调试 WCH RISC-V 芯片（CH32V 系列） | 熄灭 |
| `0x8011` | **WCH-Link** (ARM HID) | CMSIS-DAP v1，使用 HID 端点 | 常亮 |
| **`0x8012`** | **WCH CMSIS-DAP** (ARM WINUSB) | **CMSIS-DAP v2，使用 WINUSB Bulk 端点 ← 当前模式** | 常亮 |

> **当前你的设备处于 PID=0x8012 模式（ARM WINUSB / CMSIS-DAP v2），这是性能最好的 ARM 调试模式！**

---

## 五、SWD 支持分析

### ✅ **支持 SWD！而且是专门干这个的！**

与上一个 USB ISP 编程器（AVR）不同，**WCH-Link 就是为 SWD/JTAG 调试而生的。**

| 对比维度 | WCH-Link (CMSIS-DAP) | USB ISP 编程器 |
|---------|---------------------|---------------|
| **适用架构** | **ARM Cortex-M** + RISC-V | AVR 8-bit |
| **调试接口** | **SWD** (2 线) + JTAG (4 线) | ISP (SPI) |
| **支持调试** | ✅ 断点、单步、变量监视 | ❌ 仅编程 |
| **虚拟串口** | ✅ CDC ACM (COM9) | ❌ 无 |
| **CYT2BL3 兼容** | ✅ 完美支持！ | ❌ 不支持 |
| **价格** | ~$3-5 USD | ~$2-3 USD |

---

## 六、与 CYT2BL3 项目的配合使用 🎯

### 6.1 重大发现：完美适配！

你的 CYT2BL3 项目（`D:\03-Wheel_leg_CYT2BL3`）使用 **ARM Cortex-M4F**，WCH-Link 完全可以替代 J-Link：

```
当前配置（Makefile）:
  JLink.exe -device CYT2BL3 -if SWD -speed 4000 ...

可以改为:
  openocd -f interface/cmsis-dap.cfg -f target/cyt2bl3.cfg ...
  或
  probe-rs run --chip CYT2BL3 ...
```

### 6.2 驱动问题 ⚠️

**Interface 0（CMSIS-DAP）驱动未正确安装：**

```
Status: DN_HAS_PROBLEM
Problem Code: 28 (CM_PROB_FAILED_INSTALL)
Power State: D3（未启动）
```

**但 Interface 1+2（虚拟串口）工作正常：** COM9 (`\Device\USBSER000`)

### 6.3 解决方案：安装 WinUSB 驱动

需要使用 **Zadig** 工具将 Interface 0 的驱动替换为 WinUSB：

1. 下载 [Zadig](https://zadig.akeo.ie/)
2. 在 Zadig 中选择 **"WCH CMSIS-DAP"**（Interface 0）
3. 将驱动替换为 **WinUSB**（不是 libusb！）
4. 替换后，OpenOCD / pyOCD / probe-rs 即可识别

> ⚠️ **注意**：只替换 Interface 0 的驱动，不要动 Interface 1+2（COM9），否则串口会失效！

### 6.4 工具链集成方案

#### 方案 A：OpenOCD（推荐，最通用）

```bash
# 连接测试
openocd -f interface/cmsis-dap.cfg -c "cmsis_dap_vid_pid 0x1a86 0x8012" -f target/traveo2.cfg

# 或者手动指定
openocd -f interface/cmsis-dap.cfg -c "transport select swd" -c "cmsis_dap_vid_pid 0x1a86 0x8012"
```

#### 方案 B：probe-rs（你的项目已有配置）

你的项目目录下已有 `probe-rs/CYT2BL3.yaml`：

```bash
# 探测设备
probe-rs list

# 烧录
probe-rs run --chip CYT2BL3 firmware.elf

# 或指定 probe
probe-rs run --chip CYT2BL3 --probe 1A86:8012 firmware.elf
```

#### 方案 C：pyOCD

```bash
# 列出探针
pyocd list -p

# 烧录
pyocd flash -t cyt2bl3 firmware.hex
```

#### 方案 D：Keil MDK

1. 安装 WinUSB 驱动（使用 Zadig）
2. Keil → Options for Target → Debug → 选择 **CMSIS-DAP Debugger**
3. Settings → Port: **SWD** → 即可识别 CYT2BL3

---

## 七、设备用途总结

WCH-Link 是一个 **多功能 ARM/RISC-V 调试探针**，由 WCH（南京沁恒）设计，使用自家的 CH549F 芯片，实现了标准的 CMSIS-DAP v2 协议。

```
┌──────────────┐   USB CMSIS-DAP   ┌──────────────┐   SWD/JTAG    ┌──────────────┐
│   电脑/PC    │ ◄────────────────► │   WCH-Link   │ ◄───────────► │  CYT2BL3     │
│              │                    │   调试器      │               │  (Cortex-M4F)│
│  OpenOCD     │   USB CDC ACM     │   CH549F     │               │              │
│  pyOCD       │ ◄────────────────► │              │               │  轮腿机器人   │
│  probe-rs    │   Virtual COM     │   COM9 串口  │               │  主控        │
│  Keil MDK    │                    │              │               │              │
└──────────────┘                    └──────────────┘               └──────────────┘
```

**支持的目标芯片**：
- ✅ 所有 ARM Cortex-M 系列（STM32, CYT2BL3, GD32, NXP, TI...）
- ✅ WCH RISC-V 系列（CH32Vxxx）
- ✅ 理论上任何支持 SWD/JTAG 的 Cortex-M 芯片

---

## 八、参考资料

| 序号 | 来源 | URL | 内容 |
|------|------|-----|------|
| 1 | **CMSIS-DAP GitHub 官方仓库** | https://github.com/ARM-software/CMSIS-DAP | ⭐ 完整源码 + 文档 + 示例 + 验证脚本 |
| 2 | **CMSIS-DAP 官方在线文档** | https://arm-software.github.io/CMSIS-DAP/latest/ | USB 命令规范、固件配置、驱动指南 |
| 3 | **CMSIS-DAP USB 命令参考** | https://arm-software.github.io/CMSIS-DAP/latest/group__DAP__Commands__gr.html | 所有 CMSIS-DAP 命令详细规范 |
| 4 | **CMSIS 6 - DAP 组件** | https://arm-software.github.io/CMSIS_6/latest/DAP/index.html | CMSIS 生态中 DAP 介绍 |
| 5 | WCH-Link 官方用户手册 | https://akizukidenshi.com/goodsaffix/WCH-LinkUserManual.pdf | WCH 官方硬件手册 |
| 6 | GitHub: kaidegit/CMSIS-DAPbyWCH | https://github.com/kaidegit/CMSIS-DAPbyWCH | WCH-Link 硬件分析和固件 |
| 7 | GitHub: ch32-rs/openocd-wchlink-firmware | https://github.com/ch32-rs/openocd-wchlink-firmware | WCH-Link 的 OpenOCD 支持 |
| 8 | CoreSight DAP 官方文档 | https://developer.arm.com/documentation/102585/ | Debug Access Port 架构详解 |
| 9 | Mbed CMSIS-DAP Handbook | https://os.mbed.com/handbook/CMSIS-DAP | 入门教程 |
| 10 | probe-rs Issue #995 | https://github.com/probe-rs/probe-rs/issues/995 | probe-rs 对 WCH-Link 的支持 |
| 11 | ElectroDragon: WCH-LINK | https://www.electrodragon.com/product/wch-link-risc-v-arm-debug-programmer/ | 产品介绍 |
| 12 | CMSIS-DAP on ST-Link V2 (社区) | https://mvdlande.wordpress.com/2015/10/05/cmsis-dap-on-a-cheap-st-link-v2-mini-adapter/ | ST-Link 刷 CMSIS-DAP 教程 |
| 13 | CMSIS-DAP port to STM32 (社区) | http://akb77.com/g/stm32/cmsis-dap/ | 开源固件移植 |
| 14 | Zadig (WinUSB 驱动工具) | https://zadig.akeo.ie/ | 驱动安装 |
| 15 | OpenOCD 官方文档 | https://openocd.org/ | 调试服务器 |
| 16 | probe-rs 官方文档 | https://probe.rs/ | Rust 调试工具 |

---

## 九、快速操作清单

| 步骤 | 操作 | 状态 |
|------|------|------|
| 1 | 确认蓝灯常亮（ARM CMSIS-DAP 模式） | 待检查 |
| 2 | 使用 Zadig 将 Interface 0 驱动改为 WinUSB | ❌ 待执行 |
| 3 | 验证 `probe-rs list` 能识别设备 | 待验证 |
| 4 | 连接 SWD 引脚到 CYT2BL3 目标板 | 待接线 |
| 5 | 使用 probe-rs / OpenOCD 烧录 firmware | 待测试 |

---

*本报告由知心姐姐基于 USB 描述符解析 + WCH 官方文档 + 开源社区交叉验证编写 💖*
