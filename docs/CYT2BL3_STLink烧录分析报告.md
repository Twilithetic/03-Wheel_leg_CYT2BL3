# ST-Link 烧录 CYT2BL3 技术分析与操作指南

> *"ST-Link 有哪些接口？怎么给 CYT2BL3 烧录 hex？"*
> 基于 USB 描述符分析、OpenOCD 文档及社区实践

---

## 一、你的 ST-Link 身份信息

```
┌─────────────────────────────────────────────────┐
│  设备: ST-Link v2 (STMicroelectronics)           │
│  VID/PID: 0x0483 / 0x3748                       │
│  USB 速度: Full-Speed (12 Mbps)                  │
│  驱动: WinUSB (通用 USB 驱动)                     │
│  功耗: < 100mA                                   │
└─────────────────────────────────────────────────┘
```

---

## 二、ST-Link 的通信接口分析

### 2.1 USB 端（连电脑）

ST-Link 通过 **3 个 Bulk 端点** 和电脑通信：

```
电脑 (USB)                        ST-Link v2
═══════════                      ═══════════
         ◄── EP1 IN  (Bulk, 64B) ──  数据上传 (读目标芯片)
         ── EP2 OUT (Bulk, 64B) ──► 数据下发 (写目标芯片)
         ◄── EP3 IN  (Bulk, 64B) ──  状态/跟踪数据
```

这 3 个端点承载 **ST-Link 私有协议**（不是标准 CMSIS-DAP 或 J-Link 协议）。当 OpenOCD 驱动 ST-Link 时，它会通过这 3 个端点发送 SWD 命令。

### 2.2 SWD 端（连芯片）

ST-Link 对外暴露 **SWD（Serial Wire Debug）** 接口：

```
ST-Link v2 (20-pin 牛角座 / 4-pin 排针)
═══════════
Pin 1  VTref   ← 目标电压检测 (3.3V) → 接 CYT2BL3 P3-Pin1 (VCC3V3)
Pin 4  GND     ← 地                   → 接 CYT2BL3 P3-Pin2 (GND)
Pin 7  SWDIO   ← 数据线               → 接 CYT2BL3 P3-Pin4 (SWDIO)
Pin 9  SWCLK   ← 时钟线               → 接 CYT2BL3 P3-Pin5 (SWCLK)
Pin 15 NRST    ← 复位 (可选)           → 接 CYT2BL3 P3-Pin3 (NRST)
```

**接口逻辑：**

```
┌─────────┐   USB Bulk    ┌──────────────┐    SWD 2线    ┌───────────┐
│  电脑    │◄─────────────►│  ST-Link v2   │◄─────────────►│ CYT2BL3   │
│ OpenOCD │  EP1/EP2/EP3  │ (SWD 主设备)  │ SWDIO+SWCLK  │ (SWD 从设备)│
└─────────┘               └──────────────┘               └───────────┘
     ▲                          ▲                            ▲
     │                          │                            │
  发送 hex 数据           ST-Link 协议 → SWD 协议         接收并写入 Flash
  "flash write 10000000"  转换层                           (CM0+ 系统调用)
```

---

## 三、ST-Link 能烧录 CYT2BL3 吗？

### 3.1 答案：✅ 可以，但有前提条件

| 条件 | 状态 | 说明 |
|------|:---:|------|
| SWD 协议兼容 | ✅ | CYT2BL3 是标准 ARM SWD |
| OpenOCD 支持 ST-Link | ✅ | `openocd -f interface/stlink.cfg` |
| Flash 编程算法 | ⚠️ | **需要 CYT2BL3 的目标配置** |
| ST 授权限制 | ⚠️ | ST 协议限制非 STM32（技术上可绕过） |

### 3.2 原理

ST-Link 本质上是一个 **USB ↔ SWD 协议转换器**。它能：
1. 通过 SWD 读写任何 Cortex-M 芯片的内存和寄存器
2. 通过 SWD 的 DAP（Debug Access Port）访问 AHB 总线
3. 间接控制 CYT2BL3 的 Flash 控制器

**但 Flash 编程需要特定的算法**——不同芯片的 Flash 控制器不同。ST-Link 固件内置的是 STM32 的 Flash 算法。要烧录 CYT2BL3，需要由 OpenOCD 在芯片 RAM 中加载 CYT2BL3 的 Flash 算法。

### 3.3 ST-Link vs J-Link：烧录 CYT2BL3 对比

| 特性 | ST-Link v2 | J-Link |
|------|:---:|:---:|
| 价格 | ~¥15-30 | ~¥100-400 |
| SWD 速度 | ~1.8 MHz | 可达 15 MHz |
| OpenOCD 支持 | ✅ `stlink.cfg` | ✅ `jlink.cfg` |
| CYT2BL3 目标配置 | ❌ 无（需自定义） | ⚠️ 需 Infineon 支持 |
| 非 STM32 支持 | ⚠️ 重编译 OpenOCD | ✅ 原生支持 |
| 稳定性 | ⚠️ 偶有兼容问题 | ✅ 可靠 |

---

## 四、用 ST-Link 烧录 CYT2BL3 的三种方案

### 方案 A：OpenOCD + ST-Link（推荐尝试）

```bash
# 1. 启动 OpenOCD（使用 ST-Link 作为调试探针）
openocd -f interface/stlink.cfg \
        -c "transport select hla_swd" \
        -f target/traveo2_be_4m.cfg

# 2. 如果 OpenOCD 没有 traveo2_be_4m.cfg，使用通用 Cortex-M4 配置
openocd -f interface/stlink.cfg \
        -c "transport select hla_swd" \
        -c "set CHIPNAME traveo2" \
        -c "source [find target/swj-dp.tcl]" \
        -c "set CPUTAPID 0x6ba02477" \
        -c "target create traveo2.cpu cortex_m -endian little -chain-position traveo2.dap"

# 3. 连接后烧录
telnet localhost 4444
> init
> reset init
> flash write_image erase build/firmware.hex
> reset
```

**但有个关键问题**：OpenOCD 的 ST-Link 驱动使用 `hla_swd` 传输层（high-level adapter），它不支持 `traveo2_be_4m.cfg` 这种使用低层 DAP 访问的目标配置。**需要修改 OpenOCD 或使用 CMSIS-DAP 模式。**

### 方案 B：将 ST-Link 刷成 J-Link（最稳定）

SEGGER 官方提供了将 ST-Link 转换为 J-Link 的工具：

```bash
# 下载 SEGGER STLinkReflash 工具
# https://www.segger.com/downloads/jlink#STLink_Reflash

# 运行后 ST-Link 变成 J-Link！
# 之后直接用 J-Link 烧录：
JLink.exe -device CYT2BL3 -if SWD -speed 4000 -autoconnect 1
```

> ⚠️ 刷成 J-Link 后只能用于调试，SEGGER 协议禁止用于量产。可以刷回 ST-Link。

### 方案 C：将 ST-Link 刷成 CMSIS-DAP/DAPLink（最通用）

```bash
# 开源项目: https://github.com/devanlai/dap42
# 将 ST-Link 刷成 CMSIS-DAP 固件，变成通用 ARM 调试器
# 然后 OpenOCD 用 cmsis-dap 驱动
openocd -f interface/cmsis-dap.cfg \
        -c "transport select swd" \
        -f target/traveo2_be_4m.cfg
```

---

## 五、最快上手方案：直接用 OpenOCD 测试 ST-Link + CYT2BL3

### 5.1 硬件接线

```
ST-Link v2 (4线)               CYT2BL3 核心板 P3 (10-pin)
═══════════════                ══════════════════════
3.3V  ──── VTref (Pin 1) ──── VCC3V3 (Pin 1)    ← 电压检测
GND   ──── GND   (Pin 4) ──── GND    (Pin 2)    ← 共地
SWDIO ──── SWDIO (Pin 7) ──── SWDIO  (Pin 4)    ← 数据
SWCLK ──── SWCLK (Pin 9) ──── SWCLK  (Pin 5)    ← 时钟
(可选)─── NRST  (Pin 15) ──── NRST   (Pin 3)    ← 复位

⚠️ 核心板需要独立 5V 供电！ST-Link 的 3.3V 只是电压检测，不给核心板供电！
```

### 5.2 测试连接

```powershell
# 测试 1: 看 OpenOCD 能不能找到 ST-Link
openocd -f interface/stlink.cfg -c "adapter list; shutdown"

# 测试 2: 尝试连接 CYT2BL3 的 SWD
openocd -f interface/stlink.cfg -c "transport select hla_swd; init; dap info; shutdown"
```

### 5.3 如果 ST-Link 方案不行，备选

```bash
# 直接用 J-Link（项目 Makefile 已配好）
make flash

# 或者 Infineon Auto Flash Utility 带的 OpenOCD
C:\Program Files (x86)\Infineon\Auto Flash Utility 1.4\bin\openocd.exe ^
  -f interface/jlink.cfg -f target/traveo2_be_4m.cfg ^
  -c "program build/firmware.hex verify reset exit"
```

---

## 六、总结对比

| 方案 | 难度 | 费用 | 稳定性 | 推荐度 |
|------|:---:|:---:|:---:|:---:|
| ST-Link + OpenOCD 直连 | ⭐⭐⭐ | ¥15 | ⚠️ 需折腾 | ⭐⭐ |
| ST-Link 刷成 J-Link | ⭐ | ¥15 | ✅ 稳定 | ⭐⭐⭐⭐ |
| ST-Link 刷成 CMSIS-DAP | ⭐⭐ | ¥15 | ✅ 通用 | ⭐⭐⭐ |
| 直接买 J-Link | ⭐ | ¥100+ | ✅ 最佳 | ⭐⭐⭐⭐⭐ |

### 🎯 最终推荐

```
🥇 预算够 → 直接买 J-Link EDU (¥400)，省心省力
🥈 省钱方案 → ST-Link 刷 J-Link 固件，免费但稳定
🥉 折腾方案 → ST-Link + OpenOCD 直连，挑战技术
```

---

## 七、ST-Link 的完整接口能力

```
                    ST-Link v2
                         │
    ┌────────────────────┼────────────────────┐
    │                    │                    │
  USB 端              SWD 端              UART 端
  (连电脑)            (连芯片)            (串口通信)
    │                    │                    │
    ├ EP1 IN (Bulk)     ├ SWDIO              ├ TX (部分版本)
    ├ EP2 OUT (Bulk)    ├ SWCLK              └ RX (部分版本)
    └ EP3 IN (Bulk)     ├ GND
                        ├ VTref (3.3V检测)
                        └ NRST (复位, 可选)
```

---

*报告版本：v1.0 | 2026-05-04*
