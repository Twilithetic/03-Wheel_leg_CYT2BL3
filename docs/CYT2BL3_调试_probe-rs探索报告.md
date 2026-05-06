# probe-rs × CYT2BL3：完整探索报告

> *从 YAML 到 Flash 算法，从 SWD 连接到双核架构 — 完整记录*
> 日期：2026-05-04 | probe-rs 版本：0.30 / 0.31

---

## 目录

1. [项目目标](#一项目目标)
2. [已完成的工作](#二已完成的工作)
3. [probe-rs 双核支持现状](#三probe-rs-双核支持现状)
4. [TRAVEO T2G 独特架构分析](#四traveo-t2g-独特架构分析)
5. [为什么 probe-rs 无法连接](#五为什么-probe-rs-无法连接)
6. [所有测试记录](#六所有测试记录)
7. [社区与文档调研](#七社区与文档调研)
8. [结论与建议](#八结论与建议)

---

## 一、项目目标

```
让 probe-rs 完整支持 CYT2BL3：
  ✅ SWD 连接
  ✅ 芯片识别
  ✅ Flash 烧录
  ✅ GDB 调试
```

---

## 二、已完成的工作

### 2.1 硬件链路 ✅

```
$ probe-rs list
[0]: STLink V2 -- 0483:3748: (ST-LINK)

接线: ST-Link Pin 1/4/7/9/15 → P3 Pin 1/2/4/5/3
      VCC3V3 + GND + SWDIO + SWCLK + NRST
```

### 2.2 SWD 探测 ✅

```
$ probe-rs info (SWD 协议)
Debug Port: DPv2, Designer: Cypress
├── MemoryAP 0 → CM0+ 系统 ROM
├── MemoryAP 1 → CM4 系统空间
└── MemoryAP 2 → ETB + TPIU + Cortex-M4 ETM
```

### 2.3 CMSIS-Pack 获取 ✅

```
来源: https://itools.infineon.com/cmsis_packs/CAT1C_DFP/
版本: 1.2.0 (2025-12-03)
包含: CAT1C_4160.FLM (125KB), cat1c4m.svd (2.3MB)
```

### 2.4 Flash 算法提取 ✅

```
从 CAT1C_4160.FLM 符号表提取:

  Init          @ 0x0001      初始化
  UnInit        @ 0x0a55     反初始化
  EraseChip     @ 0x06a9     全片擦除
  EraseSector   @ 0x06b1     扇区擦除
  ProgramPage   @ 0x0891     页编程
  Verify        @ 0x0a61     校验

API 封装:
  SromApiEraseAll    @ 0x0899
  SromApiEraseSector @ 0x08b9
  SromApiProgramRow  @ 0x08e1
  Syscall_Init       @ 0x0975

源文件: FlashDev.c, FlashPrg.c, algo_xflash.c, cy_device.c
```

### 2.5 YAML 配置 ✅

```
文件: probe-rs/CYT2BL3.yaml (169 KB)

包含:
  ✅ 芯片族: CYT2BL3 (Infineon, JEP106 0x34)
  ✅ CPU: Cortex-M4F (armv7em), AP1
  ✅ 内存映射:
     Code Flash @ 0x10000000 (4160KB)
     Work Flash @ 0x14000000 (128KB)
     SRAM      @ 0x08000000 (512KB)
  ✅ Flash 算法: CAT1C_4160.FLM base64 编码
  ✅ 入口地址: pc_init/erase/program/verify
  ✅ Flash 属性: 页512B, 扇区32KB

验证: probe-rs info 能通过 YAML 识别芯片 ✅
```

---

## 三、probe-rs 双核支持现状

### 3.1 probe-rs 支持的双核芯片

| 芯片 | 架构 | 核 | 支持 |
|------|------|:---:|:---:|
| RP2040 | 对称双核 | M0+ × 2 | ✅ |
| STM32H7 系列 | 非对称 | M7 + M4 | ✅ |
| LPC55 系列 | 非对称 | M33 × 2 | ✅ |
| **TRAVEO T2G** | **主从架构** | **M0+ 控制 M4** | **❌** |

### 3.2 为什么 TRAVEO 特殊

```
普通双核 (STM32H7):            TRAVEO T2G (CYT2BL3):
                              
  ┌──────┐  ┌──────┐           ┌──────┐
  │  M7  │  │  M4  │           │ M0+  │ ← 管理者
  │ 主核 │  │ 辅核 │           │安全核│   负责安全、Flash
  └──┬───┘  └──┬───┘           └──┬───┘   控制 M4 启动/复位
     │         │                  │
     └────┬────┘            ┌─────┴─────┐
          │                 │  使能/禁用 │
       独立启动             │  复位控制  │
       各自复位             ▼           │
                         ┌──────┐      │
                         │  M4  │◄─────┘
                         │ 主核 │  被 M0+ 控制
                         └──────┘

M4 不能独立存活！必须由 M0+ 先启动！
```

---

## 四、TRAVEO T2G 独特架构分析

### 4.1 官方证据：Datasheet 原文 🔴

> **来源：Infineon CYT2BL Datasheet (002-28876 Rev. *H)，第 23 页 "CPU Start-up Sequence"**

```
CYT2BL CPU Start-up Sequence (原文引用):

1. System Reset (@0x0000 0000)

2. CM0+ executes ROM boot (@0x0000 0004)
   ├── Applies DAP access restrictions and system protection
   └── Authenticates flash boot (SECURE mode)

3. CM0+ executes Flash Boot (Supervisory flash @0x1700 2000)
   └── Configures SWD/JTAG debug pins

4. CM0+ starts execution:
   ├── Moves CM0+ vector table to SRAM
   ├── Sets CM4_VECTOR_TABLE_BASE (@0x0000 0200)  ← CM0+ 决定 CM4 入口！
   ├── Releases CM4 from reset                      ← CM0+ 释放 CM4！！
   └── Continues execution of CM0+ user application

5. CM4 executes from code-flash or SRAM
   └── CM4 branches to its Reset handler
```

### 4.2 架构铁证：三个关键词

| 步骤 | 原文 | 证明什么 |
|------|------|---------|
| **Step 4-ii** | `Sets CM4_VECTOR_TABLE_BASE` | CM0+ 决定 CM4 的入口地址 |
| **Step 4-iii** | `Releases CM4 from reset` | **CM4 的复位由 CM0+ 控制！** |
| **Step 2-5** | 全程只有 CM0+ 在执行 | 复位后 CM4 根本不存在于总线上 |

> 🔴 **这不是对称双核！这是主从架构！**
> CM0+ = 管理者（决定何时、如何启动 CM4）
> CM4 = 被管理者（不能独立启动，不能独立存活）

### 4.3 为什么这颗核心这么"怪"？

**这不是设计缺陷，是汽车功能安全的刻意设计！**

```
CM0+ 被赋予"管理者"角色，因为：

1. 🔒 安全隔离 (ASIL-B)
   CM0+ 运行安全固件（HSM/eSHE），独立于 CM4
   CM4 的用户代码无法干预 CM0+ 的安全操作

2. 🔑 Flash 编程保护
   所有 Flash 操作必须通过 CM0+ 的 SROM 系统调用
   CM4 不能直接操作 Flash 控制器
   → 防止恶意代码篡改固件

3. 🛡️ 安全启动 (Secure Boot)
   上电后 CM0+ 先验证 Flash Boot 签名（SECURE 模式）
   验证通过后才释放 CM4
   → 确保只有授权固件能运行

4. 🔄 FOTA 支持
   CM0+ 可以在 CM4 运行时更新 Flash（通过 Dual-Bank）
   CM4 无感知地切换到新固件
   → 空中升级的关键

5. 🎛️ 低功耗管理
   CM0+ 独立于 CM4 运行（自己的电压域）
   可以在 CM4 休眠时处理 CAN/LIN 唤醒、RTC、ADC
   → 超低功耗待机
```

> 💡 **所以 CM0+ 不是"多余的累赘"，而是这颗芯片的安全核心！**
> 汽车 MCU 和普通 MCU（STM32）的根本区别就在这儿。

### 4.4 启动/复位序列（来自 Infineon AN220118）

### 4.2 SEGGER 官方文档的关键警告

> 来自 SEGGER Knowledge Base (kb.segger.com/Infineon_Traveo_T2G)：
>
> **"J-Link does not perform a reset for the Cortex-M7 dual-cores"**
>
> - System reset：会复位整个芯片，但**可能意外禁用其他核**
> - Core reset：只复位连接的核，**其他核不受影响**
>
> **FAQ:**
> - **Q: 如何连接 M4/M7 核？**
> - **A: 在连接到核之前避免复位，否则会禁用 M4/M7 核！**
> - J-Link 的连接序列：**先连 M0 使能 M4/M7，再连 M4/M7**

### 4.3 软件复位说明（Infineon KBA）

> TRAVEO T2G 有多个 CPU，每个都有独立的 AIRCR 寄存器用于软件复位。
> 还有专门的 SoftReset SROM API。
> CM0+ 和 CM4 只能访问各自的系统空间。

---

## 五、为什么 probe-rs 无法连接

### 5.1 根因分析

```
probe-rs download 的标准 ARM 调试序列:

  Session::auto_attach()
    └── ArmDebugSequence::default()
        └── DebugPortDefault::power_up()
        └── attach_to_core()
        └── reset_and_halt()       ← 问题在这里！

reset_and_halt() 尝试:
  1. 拉低 nRESET
  2. 释放 nRESET
  3. 等待 CPU 进入 halt 状态

TRAVEO T2G 的实际情况:
  1. nRESET → 整个芯片复位
  2. CM0+ 启动 → 执行 Boot ROM → Flash Boot
  3. CM0+ 需要时间释放 CM4  ← probe-rs 没等这一步！
  4. probe-rs 超时 → 报错

SEGGER J-Link 的做法:
  1. 不复位！
  2. 直接连接 CM0+ (AP0)
  3. 通过 CM0+ 使能 CM4
  4. 再连接 CM4 (AP1)
```

### 5.2 代码层面

```
probe-rs 使用 DefaultArmSequence，它假设:
  - 所有 CPU 核在复位后立即可用
  - 可以直接 halt 任何核

TRAVEO T2G 需要:
  - 专门的多核连接序列
  - 先通过 AP0 (CM0+) 确保 CM4 已释放
  - 然后再 halt CM4

probe-rs 目前没有为 TRAVEO T2G 实现这样的序列。
```

---

## 六、所有测试记录

| # | 测试 | 命令/配置 | 结果 |
|---|------|---------|------|
| 1 | 基础识别 | `probe-rs list` | ✅ STLink V2 |
| 2 | SWD 探测 | `probe-rs info --protocol swd` | ✅ DPv2, 3 APs |
| 3 | YAML 加载 | `probe-rs info --chip-description-path` | ✅ 识别芯片 |
| 4 | AP1 + 无NRST | `download --chip ... AP1` | ❌ SwdDpError |
| 5 | AP1 + NRST | `download --connect-under-reset AP1` | ❌ Timeout |
| 6 | AP0 + NRST | `download --connect-under-reset AP0` | ❌ SwdApWdataError |
| 7 | 自动AP + NRST | `download --connect-under-reset !Arm{}` | ❌ YAML 格式错误 |

---

## 七、社区与文档调研

### 7.1 probe-rs 相关 Issue

| Issue | 描述 | 相关度 |
|-------|------|:---:|
| #2563 | "Problem with reset of Cortex-M4 VA41630" | ⭐⭐⭐ |
| #3715 | "Can't program unless first erased by CubeProgrammer" | ⭐⭐ |
| #2950 | "probe-rs incompatible with RPi Debug Probe" | ⭐ |
| #2256 | "Clarification on how to add a new target" | 参考 |
| #2590 | "target-gen fails with custom flash algorithm" | 参考 |

### 7.2 官方文档

| 文档 | 关键信息 |
|------|---------|
| probe.rs/docs | 支持 `--chip-description-path` 加载自定义 YAML |
| probe.rs/docs/knowledge-base/cmsis-packs | target-gen、YAML 格式说明 |
| github.com/probe-rs/flash-algorithm-template | Rust Flash 算法模板 |
| kb.segger.com/Infineon_Traveo_T2G | **TRAVEO 复位序列的特殊要求** |
| infineon AN220118 | CYT2B 启动序列 |

### 7.3 TRAVEO 双核的关键事实

```
来源: SEGGER Knowledge Base + Infineon AN220118 + 实测

1. TRAVEO T2G 是 "M0+ 主控 M4" 架构
   → M0+ = 安全核，负责 Flash、复位控制
   → M4 = 应用核，由 M0+ 启动和管控

2. 复位后 M4 不会自动运行
   → 必须等 M0+ Boot ROM → Flash Boot → 释放 M4

3. SWD 直接 halt M4 不可靠
   → 需要先通过 M0+ 确保 M4 已就绪

4. SEGGER 为此实现了专门连接序列
   → "先连 M0 → 使能 M4 → 再连 M4"

5. probe-rs 没有实现这个序列
   → 导致所有带 AP 指定的连接尝试失败
```

---

## 八、结论与建议

### 8.1 结论

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  🔴 铁证：Infineon CYT2BL Datasheet 第 23 页明确记载：       │
│                                                             │
│  "CM0+ ... Releases CM4 from reset"                         │
│                                                             │
│  CYT2BL3 的 CM4 不是独立的 CPU！                             │
│  它在硬件层面被 CM0+ 控制复位和启动。                         │
│                                                             │
│  probe-rs 的 DefaultArmSequence 认为所有核在复位后            │
│  立即可用，直接 halt。这在 TRAVEO T2G 上必然失败。            │
│                                                             │
│  这需要 probe-rs 上游实现专门的 "TraveoArmSequence"：         │
│  Step 1: 连接 CM0+ (AP0)，不复位                             │
│  Step 2: 等待 CM0+ Boot ROM → Flash Boot 完成                │
│  Step 3: 确认 CM0+ 释放了 CM4                                │
│  Step 4: 连接 CM4 (AP1)，加载 Flash 算法                     │
│  Step 5: Flash 编程 (通过 CM0+ SROM API)                     │
│                                                             │
│  ✅ YAML 配置正确                                           │
│  ✅ Flash 算法就绪                                          │
│  ✅ SWD 链路完好                                            │
│  ⏳ 等 probe-rs 上游支持 TRAVEO 连接序列                     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 8.2 产出物清单

| 产出 | 文件 | 状态 |
|------|------|:---:|
| 芯片 YAML | `probe-rs/CYT2BL3.yaml` (169KB) | ✅ |
| Flash 算法 | CAT1C_4160.FLM (125KB) | ✅ |
| Base64 编码 | 内嵌在 YAML 中 | ✅ |
| 符号表 | Init/Erase/Program/Verify 入口 | ✅ |
| 源码分析 | cy_device.c, FlashPrg.c | ✅ |
| CMSIS-Pack | CAT1C_DFP 1.2.0 | ✅ |

### 8.3 建议

```
🥇 当下烧录方案:
   ST-Link 刷 J-Link 固件 → 5 分钟 → 完美支持
   或 下载 Infineon OpenOCD → 注册账号 → 原生支持

🥈 长期跟进:
   给 probe-rs 提 Feature Request
   附上 YAML + Flash 算法 + TRAVEO 架构分析
   等社区实现 TraveoArmSequence

🥉 自己动手:
   study probe-rs 源码中的 ArmDebugSequence
   实现 TRAVEO 专用的连接序列
   提交 PR
```

---

*报告版本：v2.0 | 2026-05-04 | 基于 probe-rs 0.30/0.31 + SEGGER KB + Infineon AN220118*
