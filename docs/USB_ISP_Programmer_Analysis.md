# USB 设备分析报告：zhifengsoft USB ISP 编程器

> **分析日期**: 2026-05-05  
> **USB 端口**: Port3 (1-3)  
> **分析工具**: USB Device Viewer (Windows) + 联网交叉验证  

---

## 一、问题描述

在电脑 USB Port3 上连接了一个 USB 设备，需要识别该设备的：
1. 具体芯片型号
2. 使用的通信接口协议
3. 是否支持 SWD 调试协议

---

## 二、USB 枚举信息摘要

| 字段 | 值 | 含义 |
|------|-----|------|
| **Vendor ID** | `0x03EB` | **Atmel Corporation**（现已被 Microchip 收购） |
| **Product ID** | `0xC8B4` | zhifengsoft 定制的 USB ISP 编程器 |
| **Manufacturer String** | `"zhifengsoft"` | 制造商：智峰软件（中国） |
| **Product String** | `"USBHID"` | 产品名 |
| **USB Version** | `1.1`（Low-Speed, 1.5 Mbit/s） | 低速 USB 设备 |
| **bDeviceClass** | `0xFF`（Vendor Specific） | 厂商自定义类 |
| **bInterfaceClass** | `0x03`（HID） | 人机接口设备类 |
| **bInterfaceSubClass** | `0x00` | 无子类 |
| **bInterfaceProtocol** | `0x00` | 无协议 |
| **Demanded Current** | `100 mA` | 总线供电 100mA |
| **HID Descriptor Length** | `0x33`（51 bytes） | HID 报告描述符长度 |
| **bNumEndpoints** | `0x00` | 仅使用默认控制端点(EP0) |

---

## 三、芯片详细分析

### 3.1 芯片型号：ATmega88（或 ATmega8）

通过查阅多个可靠来源交叉验证：

| 来源 | 关键信息 |
|------|---------|
| [irq5.io - Making USBasp Chinese Clones Usable](https://irq5.io/2017/07/25/making-usbasp-chinese-clones-usable/) | "它由一个 ATmega88 驱动（听说老版本用的是 ATmega8），PCB 上标注 MX-USBISP-V4.00" |
| [GreenPhotons - Hacking an AVR programmer](https://www.sciencetronics.com/greenphotons/?p=938) | 确认 VID=03EB, PID=C8B4，主控为 ATmega88 |
| [GitHub - lb5tr/usbasp-zhifengsoft](https://github.com/lb5tr/usbasp-zhifengsoft) | "Zhifengsoft 制造廉价的 USBasp AVR 编程器，主控为 ATmega88 或 ATmega8" |
| [GitHub - p2c2e/usbasp-zhifengsoft](https://github.com/p2c2e/usbasp.2011-05-28-zhifengsoft-USB-ISP-Clone) | 提供针对 zhifengsoft 版本的 USBasp 固件（ATmega88 芯片） |
| [EEVBlog Forum](https://www.eevblog.com/forum/microcontrollers/usb-isp-programmer/) | 确认 VID/PID 为 03EB/C8B4 |

**结论：芯片是 Atmel ATmega88（TQFP 封装）或早期版本的 ATmega8。**

> 注：ATmega88 是 Atmel（现 Microchip）出品的 **8 位 AVR 微控制器**，内置 8KB Flash、1KB SRAM、512B EEPROM。

### 3.2 芯片架构

```
┌────────────────────────────────────┐
│         ATmega88 (AVR 8-bit)       │
│                                    │
│  ┌──────────┐    ┌──────────────┐  │
│  │  CPU     │    │  USB (V-USB) │  │
│  │  8-bit   │◄──►│  软件实现    │  │
│  │  12MHz   │    │  Low-Speed   │  │
│  └──────────┘    └──────┬───────┘  │
│                         │          │
│  ┌──────────┐    ┌──────┴───────┐  │
│  │  ISP     │    │  USB 引脚    │  │
│  │  SPI接口 │    │  D+/D-       │  │
│  └────┬─────┘    └──────────────┘  │
│       │                            │
└───────┼────────────────────────────┘
        │ 10-pin ISP 接口
        ▼
   ┌─────────┐
   │ 目标芯片 │  (待编程的 AVR MCU)
   └─────────┘
```

---

## 四、通信接口分析

### 4.1 USB 端：HID（Human Interface Device）+ V-USB

- **接口类**：HID（Human Interface Device，`bInterfaceClass = 0x03`）
- **底层 USB 实现**：**V-USB**（原名 AVR-USB），由 Objective Development GmbH 开发
  - V-USB 是一个**纯软件实现的 USB 驱动**，不需要专用 USB 控制器
  - 仅需两个 GPIO 引脚 + 少量外部元件（电阻、晶振）
  - 支持 USB 1.1 Low-Speed（1.5 Mbit/s）
  - 通信通过**控制端点 EP0** 实现（`bNumEndpoints = 0x00`）
- **HID 报告描述符**：51 字节（`0x33`），定义了自定义 HID 报告格式
  - 使用 HID Feature Reports 进行数据交换
  - 不需要专门的 USB 驱动，Windows 使用内置的 `hidusb.sys`

### 4.2 编程端：ISP（In-System Programming，SPI 协议）

```
10-pin ISP 接口标准引脚：
┌──────────────────────┐
│ 1  MOSI  (PB3)      │ ──► 目标芯片 MOSI
│ 2  VCC   (5V)       │ ──► 目标芯片 VCC
│ 3  RST   (PB2)      │ ──► 目标芯片 RESET
│ 4  SCK   (PB5)      │ ──► 目标芯片 SCK
│ 5  MISO  (PB4)      │ ◄── 目标芯片 MISO
│ 6  GND              │ ──► 目标芯片 GND
│ 7  NC               │
│ 8  NC               │
│ 9  NC               │
│ 10 GND              │
└──────────────────────┘
```

ISP 本质是 **SPI 总线** + RESET 控制，用于：
- 烧录 Flash 固件
- 读写 EEPROM
- 配置 Fuse Bits（熔丝位）
- 读写 Lock Bits

---

## 五、SWD 支持分析

### ❌ **不支持 SWD！**

**这是本报告最关键的技术判断。**

| 对比维度 | SWD (Serial Wire Debug) | ISP (In-System Programming) |
|---------|------------------------|----------------------------|
| **适用架构** | **ARM Cortex-M** 系列 | **AVR** 8 位微控制器 |
| **所属厂商** | ARM Ltd. | Atmel / Microchip |
| **引脚数量** | 2 线（SWCLK + SWDIO） | 4 线（MOSI, MISO, SCK, RESET） |
| **协议层级** | ARM Debug Interface v5 | SPI 总线协议 |
| **调试能力** | 支持实时断点、单步调试、变量监视 | **仅编程**，不支持运行时调试 |
| **本设备支持** | ❌ 不支持 | ✅ 支持 |

**原因详解：**

1. **架构不兼容**：ATmega88 是 **AVR 8-bit 哈佛架构**，而 SWD 是 **ARM Cortex-M 系列独有的调试协议**。两者完全不兼容。
2. **物理引脚不同**：SWD 需要 SWCLK 和 SWDIO 两个专用调试引脚，AVR 芯片根本没有这些外设。
3. **AVR 的调试方案**：AVR 芯片使用 **debugWIRE**（单线调试，占用 RESET 引脚）或 **JTAG**（部分高端型号），小型芯片如 ATmega88 通常没有硬件调试功能。

### 对你的 CYT2BL3 项目的意义

你的项目（`D:\03-Wheel_leg_CYT2BL3`）使用的是 **Infineon CYT2BL3**（ARM Cortex-M4F），Makefile 中已经配置了 J-Link + SWD：

```makefile
# Makefile 第 79 行
JLink.exe -device CYT2BL3 -if SWD -speed 4000 -autoconnect 1 ...
```

所以这个 USB ISP 编程器**无法**用于 CYT2BL3 的调试/烧录。你需要：
- ✅ **J-Link** / **DAP-Link** / **ST-Link** 等 ARM 调试器
- ✅ 或者使用项目中的 `probe-rs`（`probe-rs/CYT2BL3.yaml`）

---

## 六、设备用途总结

这个设备是一个 **AVR ISP 编程器（USBasp 克隆版）**：

```
┌──────────────┐    USB HID     ┌──────────────┐    ISP/SPI     ┌──────────────┐
│   电脑/PC    │ ◄────────────► │  USB ISP      │ ◄────────────► │  目标 AVR    │
│  (avrdude/   │                │  编程器        │                │  芯片        │
│   ProgISP)   │                │  (ATmega88)   │                │ (ATmega328P  │
│              │                │               │                │  等)         │
└──────────────┘                └──────────────┘                └──────────────┘
```

支持的软件：
- **ProgISP**（智峰软件原厂配套工具，Windows）
- **avrdude**（开源，需刷写 USBasp 固件替换原厂固件）
- **Arduino IDE**（可作为编程器烧录 Arduino bootloader）

---

## 七、参考资料

| 序号 | 来源 | URL |
|------|------|-----|
| 1 | irq5.io：Making USBasp Chinese Clones Usable | https://irq5.io/2017/07/25/making-usbasp-chinese-clones-usable/ |
| 2 | GreenPhotons：Hacking an AVR programmer | https://www.sciencetronics.com/greenphotons/?p=938 |
| 3 | GitHub：lb5tr/usbasp-zhifengsoft | https://github.com/lb5tr/usbasp-zhifengsoft |
| 4 | GitHub：p2c2e/usbasp-zhifengsoft | https://github.com/p2c2e/usbasp.2011-05-28-zhifengsoft-USB-ISP-Clone |
| 5 | USBasp 官方（Thomas Fischl） | https://www.fischl.de/usbasp/ |
| 6 | V-USB 官方文档 | https://www.obdev.at/products/vusb/ |
| 7 | EEVBlog：USB-ISP Programmer 讨论 | https://www.eevblog.com/forum/microcontrollers/usb-isp-programmer/ |
| 8 | Atmel USB 设备列表 (DeviceHunt) | https://devicehunt.com/view/type/usb/vendor/03EB |

---

## 八、附录：如何让这个编程器工作

如果你想用这个编程器来烧录 AVR 芯片（比如 Arduino），需要：

### 方案 A：继续使用原厂固件（ProgISP）
- 下载 ProgISP 软件（智峰软件官网）
- 使用专用上位机进行编程
- 优点：开箱即用，无需刷固件
- 缺点：仅限 Windows，不支持 avrdude

### 方案 B：刷写 USBasp 固件（推荐）
- 需要另一个编程器（如 Arduino 做 ISP）
- 刷写适配的 `main.hex` 固件
- 需要焊接飞线连接 PB2（Self-Programming 跳线）
- 之后可以使用 avrdude / Arduino IDE 进行编程

### 方案 C：直接购买支持 SWD 的调试器（用于你的 CYT2BL3 项目）
推荐：
- J-Link EDU（已在 Makefile 中配置）
- DAP-Link（CMSIS-DAP，开源）
- ST-Link V2/V3（性价比高）

---

*本报告由知心姐姐基于 USB 描述符解析 + 多个开源社区交叉验证编写 💖*
