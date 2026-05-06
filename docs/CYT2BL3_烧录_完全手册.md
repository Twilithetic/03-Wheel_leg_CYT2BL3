# CYT2BL3 烧录完全手册

> *从芯片 Flash 到 SWD 协议，从 OpenOCD 到 probe-rs，从 ST-Link 到 J-Link*
> 一份文档覆盖所有烧录知识

---

## 目录

1. [芯片 Flash 规格](#一芯片-flash-规格)
2. [烧录通道](#二烧录通道)
3. [核心板烧录接口](#三核心板烧录接口)
4. [SWD/JTAG 协议详解](#四swdjtag-协议详解)
5. [烧录原理：Flash 编程机制](#五烧录原理flash-编程机制)
6. [启动流程与烧录时序](#六启动流程与烧录时序)
7. [烧录工具全景对比](#七烧录工具全景对比)
8. [ST-Link 深度分析](#八st-link-深度分析)
9. [probe-rs 实测报告](#九probe-rs-实测报告)
10. [Flash 算法的真相](#十flash-算法的真相)
11. [实战命令速查](#十一实战命令速查)
12. [推荐路线与决策](#十二推荐路线与决策)

---

## 一、芯片 Flash 规格

### 1.1 CYT2BL3 存储器一览

| 存储器 | 容量 | 基地址 | 用途 |
|--------|------|--------|------|
| **Code Flash** | 4160 KB | `0x10000000` | 用户程序代码 |
| **Work Flash** | 128 KB | `0x14000000` | 配置/校准数据 |
| **Supervisory Flash** | - | `0x17000000` | 安全启动/BootROM |
| **SRAM** | 512 KB | `0x08000000` | 运行时数据 |

> 数据来源：Infineon CYT2BL Datasheet (002-28876 Rev. *H)

### 1.2 Flash 特性

- ✅ **SECDED ECC**：所有 Flash 支持单纠错/双检错（ASIL-B）
- ✅ **Dual-Bank**：支持 FOTA 固件升级
- ✅ **40nm 工艺**：低功耗 Flash
- ⚠️ **保护机制**：支持读写保护、芯片级擦除使能

---

## 二、烧录通道

### 2.1 四种烧录方式

| 通道 | 引脚 | 速度 | 场景 |
|------|------|------|------|
| 🔌 **SWD** | 2 线 (SWDIO+SWCLK) | 可达 50 MHz | 开发调试 |
| 🔌 **JTAG** | 4 线 | 较慢 | 边界扫描 |
| 🚗 **CAN Bootloader** | P0.2(TX)+P0.3(RX) | 100/500 kbps | 量产烧录 |
| 🔗 **LIN Bootloader** | P0.1(TX)+P0.0(RX) | 20/115.2 kbps | 量产烧录 |

### 2.2 CAN Bootloader 参数

```
CAN 实例:   CAN0, Channel #1
RX ID:      0x1A1
TX ID:      0x1B1
模式:       Classic CAN
超时:       300 秒 (无通信自动退出)
```

---

## 三、核心板烧录接口

### 3.1 P3 插座 (10-pin Cortex Debug)

```
P3 (Header 5X2, 1.27mm 间距)
══════════════════════
1  VCC3V3  │  GND    2   ← 目标电压 + 地
3  NRST    │  SWDIO  4   ← 复位 + 数据 (22Ω J2)
5  SWCLK   │  (NC)   6   ← 时钟 (22Ω J1)
7  (NC)    │  (NC)   8
9  (NC)    │  (NC)  10
══════════════════════
```

### 3.2 调试器接线速查

```
探针                P3
══════════          ══════
VTref (1)    ────   VCC3V3 (1)   电压检测
GND (4/任何) ────   GND (2)      共地
SWDIO (7)    ────   SWDIO (4)    数据
SWCLK (9)    ────   SWCLK (5)    时钟
nRESET (15)  ────   NRST (3)     复位(可选)
```

---

## 四、SWD/JTAG 协议详解

### 4.1 协议对比

| 特性 | SWD | JTAG |
|------|-----|------|
| 引脚数 | **2 线** | 4 线 |
| 速度 | 更快 | 较慢 |
| Flash 编程 | ✅ | ✅ |
| 调试 | ✅ | ✅ |
| 边界扫描 | ❌ | ✅ |
| 多核调试 (CYT2BL3) | ✅ 通过 DAP | ✅ 通过 TAP |
| 追踪 (SWO/ETM) | ✅ | ✅ |
| **推荐用于** | **日常开发** | 产线测试 |

### 4.2 ARM CoreSight 调试架构

```
CYT2BL3 CoreSight 拓扑 (probe-rs 实测):

DPv2 (Debug Port v2, Designer: Cypress)
  │
  ├── MemoryAP 0 → Cypress ROM  (CM0+ 安全核)
  │
  ├── MemoryAP 1 → 系统空间
  │     ├── Cypress ROM Table
  │     ├── ARM ROM Table
  │     └── CTI (交叉触发接口)
  │
  └── MemoryAP 2 → 调试追踪
        ├── ETB   (Embedded Trace Buffer, 8KB)
        ├── TPIU  (Trace Port Interface Unit)
        └── ETM   (Embedded Trace Macrocell, M4 指令追踪)
```

### 4.3 调试组件清单

| 组件 | 用途 | 容量 |
|------|------|:---:|
| MTB (CM0+) | 微跟踪缓冲区 | 4 KB |
| ETB (CM4) | 嵌入式跟踪缓冲区 | 8 KB |
| ETM (CM4) | 嵌入式跟踪宏 | - |
| ITM | 指令跟踪宏 | - |
| TPIU | 跟踪端口接口 | - |
| SWO | 串行线输出 | 1 线 |
| CTI / CTM | 交叉触发 | - |

---

## 五、烧录原理：Flash 编程机制

### 5.1 核心原理

```
CYT2BL3 的所有 Flash 操作都通过 CM0+ 的 SROM 系统调用实现：

  ┌──────────┐    SWD/DAP     ┌──────────┐   IPC 通知   ┌──────────┐
  │ 调试器    │◄─────────────►│   CM4    │────────────►│   CM0+   │
  │(J-Link等) │               │ (用户核) │             │ (安全核) │
  └──────────┘               └──────────┘             └────┬─────┘
                                                          │
                                                    SROM 系统调用
                                                          │
                                                    ┌─────▼─────┐
                                                    │   Flash   │
                                                    │  控制器   │
                                                    └───────────┘
```

### 5.2 编程流程

```
Step 1: 获取 IPC 锁 (IPC1 ACQUIRE @0x08010000)
Step 2: 写 Flash 目标地址
Step 3: 写编程数据
Step 4: 写数据大小
Step 5: 发送 NOTIFY → CM0+ IRQ0
Step 6: CM0+ 执行 SROM API
Step 7: 等待返回状态 (0xA = 成功)
Step 8: 释放 IPC 锁
```

### 5.3 这就是为什么需要"Flash 算法"

```
┌─────────────────────────────────────────────────────────────┐
│  SWD 能直接读写 SRAM，但 Flash 不行！                        │
│                                                             │
│  Flash 编程 = 先在 SRAM 运行一段程序 →                        │
│             这段程序调用 SROM API →                          │
│             SROM API 操作 Flash 控制器                       │
│                                                             │
│  这段"小程序"就是 Flash Algorithm Blob (~2KB)                │
│  每个工具都需要它才能烧录 Flash                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 六、启动流程与烧录时序

### 6.1 启动流程

```
上电复位 (POR)
  │
  ▼
CM0+ Boot ROM (掩膜ROM)
  ├── 初始化电源、时钟
  ├── 读 eFuse 配置
  ├── 验证 Flash Boot 签名 (SECURE 模式)
  └── 配置 SWD/JTAG 引脚 (GPIO → Debug 功能)
  │
  ▼
CM0+ Flash Boot (Supervisory Flash @0x17002000)
  ├── 设置 CM0_VTOR → Flash 起始
  ├── 设置 CM4_VECTOR_TABLE_BASE @0x00000200
  └── 释放 CM4 复位
  │
  ▼
CM4 执行用户程序 (Code Flash @0x10000000)
```

### 6.2 ⚠️ 关键时序

```
复位后 SWD 引脚默认为 GPIO 模式
Boot ROM 执行后才切换为 Debug 功能
→ 上电后需等待 ~200ms 才能 SWD 连接！
```

---

## 七、烧录工具全景对比

### 7.1 工具矩阵

| 工具 | 开源 | ST-Link | J-Link | CYT2BL3 Flash | 调试 | 推荐度 |
|------|:---:|:---:|:---:|:---:|:---:|:---:|
| **J-Flash** (SEGGER) | ❌ 商业 | ⚠️ 刷固件 | ✅ | ✅ 内置 | ✅ | ⭐⭐⭐⭐⭐ |
| **Infineon OpenOCD** (AFU) | ✅ 开源 | ⚠️ 待测 | ✅ | ✅ 内置 | ✅ | ⭐⭐⭐⭐ |
| **通用 OpenOCD** | ✅ | ✅ | ✅ | ❌ 无 | ✅ | ⭐⭐ |
| **probe-rs** | ✅ | ✅ | ✅ | ❌ 无 | ✅ 最佳 | ⭐⭐⭐ |
| **pyOCD** | ✅ | ✅ | ✅ | ❌ 无 | ✅ | ⭐⭐ |
| **st-flash** | ✅ | ✅ | ❌ | ❌ STM32 | ❌ | ⭐ |
| **BlackMagic Probe** | ✅ | ⚠️ 刷固件 | ❌ | ❌ | ✅ | ⭐⭐ |

### 7.2 工具能力雷达图

```
                Flash 烧录
                    ▲
                    │
              J-Flash ████
       Infineon OOCD  ████
                     │
                     │
    probe-rs ────────┼──────── 调试体验
   pyOCD             │
                     │
                     ▼
                 开源免费
```

---

## 八、ST-Link 深度分析

### 8.1 你的 ST-Link

```
设备:    ST-Link v2
VID/PID: 0x0483 / 0x3748
速度:    USB Full-Speed (12 Mbps)
驱动:    WinUSB
功耗:    < 100 mA
```

### 8.2 USB 通信架构

```
电脑 ⇄ ST-Link v2 (USB Bulk)

  EP1 IN  (Bulk, 64B)  ← ST-Link → 电脑 (读取数据)
  EP2 OUT (Bulk, 64B)  ← 电脑 → ST-Link (下发命令)
  EP3 IN  (Bulk, 64B)  ← ST-Link → 电脑 (状态/跟踪)

这三个端点承载 ST-Link 私有协议。
OpenOCD/probe-rs/pyOCD 各自实现了 ST-Link 协议驱动。
```

### 8.3 SWD 物理接口

```
ST-Link (20-pin 牛角座)
═══════════════════════
Pin 1  VTref   → 目标电压检测 (3.3V)
Pin 4  GND     → 地
Pin 7  SWDIO   → 数据线
Pin 9  SWCLK   → 时钟线
Pin 15 NRST    → 复位线

支持: SWD ✅    JTAG ❌ (ST-Link v2 的 JTAG 支持有限)
```

### 8.4 ST-Link 的局限

```
✅ 可以做:
   - SWD 连接任何 Cortex-M 芯片
   - 读写内存/寄存器
   - GDB 远程调试
   - RTT 日志

❌ 不能做:
   - 自动烧录非 STM32 Flash (缺算法)
   - 高速 SWD (最高 ~1.8 MHz)
   - JTAG 边界扫描

⚠️ 注意:
   ST 协议禁止用于非 STM32 量产
   开发和调试可以
```

---

## 九、probe-rs 实测报告

### 9.1 实测结果

```
✅ probe-rs list          → 识别 ST-Link v2
✅ probe-rs info (SWD)    → 完整 CoreSight 探测
   ├── DPv2, Designer: Cypress ✓
   ├── 3 个 MemoryAP ✓
   ├── ETB + TPIU + ETM ✓
   └── CM4 + CM0+ 双核识别 ✓

❌ probe-rs chip list     → 无 TRAVEO T2G
❌ probe-rs download      → 芯片不在数据库
❌ Flash 自动编程          → 缺算法
```

### 9.2 probe-rs 能做什么

```
✅ 连接验证 (硬件链路测试)
✅ 内存读写 (任意地址)
✅ CPU 暂停/恢复
✅ GDB 远程调试
✅ RTT 日志输出
✅ 寄存器查看/修改
✅ VSCode 集成 (DAP 协议)
```

### 9.3 probe-rs 原理

```
probe-rs 的 Flash 烧录需要:

  1. chip.yaml     ← 芯片描述 (内存布局、Flash 页大小等)
  2. flash_algo.bin ← Flash 算法 (擦除/编程/校验函数)
  
这些来自 CMSIS-Pack 或手写。
Infineon 没有为 CYT2BL3 发布 CMSIS-Pack。
```

---

## 十、Flash 算法的真相

### 10.1 为什么这么难获取？

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  Flash 算法不是"配置"，是"一个小程序"                         │
│                                                             │
│  它需要:                                                    │
│  ├── 知道 SROM API 的操作码                                  │
│  ├── 知道 IPC 通信的寄存器地址                                │
│  ├── 知道 Flash 控制器的寄存器                                │
│  ├── 编译成位置无关代码 (PIC)                                │
│  └── 导出标准的 init/erase/program/verify 函数              │
│                                                             │
│  Infineon 把这个算法编译进了 Auto Flash Utility               │
│  没有公开独立的 CMSIS-Pack 或算法文件                         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 10.2 各工具中算法的状态

```
Infineon OpenOCD (AFU):
  └── traveo2_be_4m.cfg → 引用内置 Flash 驱动
     内部是一个编译好的 .elf 被加载到 SRAM 执行

J-Flash:
  └── SEGGER 和 Infineon 合作开发的闭源算法
     打包在 J-Link 软件中

probe-rs / pyOCD:
  └── 没有，需要等社区贡献或自己写

PDL 源码 (libs/pdl/drivers/source/cy_flash_srom.c):
  ├── 有 SROM API 调用代码
  └── 但 CYT2BL3 不在当前 PDL 支持列表中
```

---

## 十一、实战命令速查

### 11.1 编译固件

```bash
make clean && make all     # 全量编译
make                       # 增量编译
ls build/firmware.hex      # 烧录文件
```

### 11.2 probe-rs

```bash
probe-rs list                        # 扫描探针
probe-rs info                        # 探测芯片
probe-rs read 0x10000000 256 b8      # 读 Flash
probe-rs read 0x08000000 64 b32      # 读 SRAM
```

### 11.3 烧录 (需算法支持)

```bash
# Infineon OpenOCD (Auto Flash Utility)
openocd -f interface/jlink.cfg \
        -c "transport select swd" \
        -f target/traveo2_be_4m.cfg \
        -c "program build/firmware.hex verify reset exit"

# J-Flash
JLink.exe -device CYT2BL3 -if SWD -speed 4000 -autoconnect 1
# 然后在 J-Flash GUI 中加载 hex → Program

# Makefile 烧录 (需 make 环境 + J-Link)
make flash
```

### 11.4 GDB 调试

```bash
# 终端1: 启动 GDB Server
probe-rs gdb --chip psoc6_01    # 或用 OpenOCD

# 终端2: 连接 GDB
arm-none-eabi-gdb build/firmware.elf
(gdb) target remote localhost:1337
(gdb) load
(gdb) break main
(gdb) continue
```

---

## 十二、推荐路线与决策

### 12.1 三条路线对比

```
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║  🥇 路线A: Infineon OpenOCD (推荐)                           ║
║     下载 Auto Flash Utility → OpenOCD + CYT2BL3 算法         ║
║     探针: ST-Link 或 J-Link 都可以                           ║
║     成本: 注册 Infineon 账号 (免费)                          ║
║     效果: 开源 + 官方算法 + 命令行烧录                        ║
║                                                              ║
║  🥈 路线B: J-Flash (最稳定)                                  ║
║     ST-Link 刷 J-Link → J-Flash GUI 烧录                     ║
║     成本: SEGGER 工具免费用于开发                            ║
║     效果: 最稳定，零折腾                                     ║
║                                                              ║
║  🥉 路线C: 等 probe-rs 社区支持 (最酷)                       ║
║     目前只能做调试，不能做 Flash 烧录                         ║
║     等社区贡献或自己写 Flash 算法                             ║
║     效果: 将来最好的调试体验                                  ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
```

### 12.2 决策矩阵

| 你想要... | 推荐 |
|-----------|------|
| 最快烧录 | 🥇 Infineon OpenOCD |
| 最稳定 | 🥈 J-Flash |
| 最好调试体验 | 🥉 probe-rs (调试) + 其他 (烧录) |
| 完全不花钱 | 🥇 注册 Infineon (免费) |
| 懒得注册 | 🥈 ST-Link 刷 J-Link |

### 12.3 当前可用组合

```
调试用: probe-rs ← 连接快、信息全、VSCode 好看
烧录用: 待获取 (AFU 或 J-Flash)

组合拳:
  开发时 → probe-rs info 验证连接
  烧录时 → openocd 或 J-Flash 一键烧录
```

---

## 附录：烧录故障排查

| 现象 | 原因 | 解决 |
|------|------|------|
| SWD 连不上 | 上电后没等够 | 等 200ms 后再连 |
| SWD 连不上 | 芯片进入 Sleep | 接 NRST 线，`connect_under_reset` |
| Flash 擦除失败 | CM0+ 没运行 | 确保 `reset init` 正确 |
| 烧录后不运行 | 没复位 | 烧录后执行 `reset` |
| probe-rs 报 JtagUnknownJtagChain | JTAG 没启用 | 用 `--protocol swd` |

---

*手册版本：v1.0 | 2026-05-04 | 整合所有烧录知识*
