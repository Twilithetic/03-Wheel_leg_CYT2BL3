# Infineon OpenOCD 探针支持分析

> *"为什么 Infineon OpenOCD 不支持 ST-Link V2？支持哪些烧录器？"*
> 基于 OpenOCD 官方文档、Infineon ModusToolbox 文档、SEGGER 设备列表

---

## 一、Infineon OpenOCD 支持的探针

### 官方支持列表（四个）

| 探针 | 类型 | 接口 | 价格 |
|------|------|------|:---:|
| **SEGGER J-Link** | 独立调试器 | JTAG + SWD | ¥200-400 |
| **Infineon KitProg3** | 板载调试器 | SWD (CMSIS-DAP) | 随开发板 |
| **Infineon MiniProg4** | 独立调试器 | SWD (CMSIS-DAP) | ~¥150 |
| **FTDI-based** | 板载适配器 | JTAG | 特定开发板 |

> 来源：Infineon ModusToolbox OpenOCD CLI User Guide (002-26234 Rev. T, 2026-03-13)

---

## 二、为什么不支持 ST-Link V2？

### 2.1 核心原因：ST-Link 用 HLA 模式

```
探针                    OpenOCD 中的模式            AP 支持
────                    ────────────────            ──────
J-Link                  DAP API (原生)             支持所有 AP ✅
KitProg3 / MiniProg4    CMSIS-DAP (原生)           支持所有 AP ✅
ST-Link V2 (旧 API)     HLA (High-Level Adapter)   不支持多 AP ❌
ST-Link V2 (新 API)     DAP API (>=V2.J21.S4)      有限支持 ⚠️
```

### 2.2 HLA 模式的限制

```
HLA 模式 = 高层抽象，简化了 SWD 操作，但代价是功能受限：

  ✅ 可以: 连接、halt、单步、读写内存
  ❌ 不能: 选择 AP 号 > 0
  ❌ 不能: 访问多个 AP
  ❌ 不能: 精细控制 DAP

对于单核 STM32: 足够了
对于双核 CYT2BL3: 失败！(CM0+ 在 AP0, CM4 在 AP1)
```

### 2.3 CYT2BL3 需要什么

```
cyt2bl.cfg 第 81 行:
  target create ${TARGET}.cm0 cortex_m -dap ... -ap-num 1

  ↑ 需要指定 AP 号 = 1

ST-Link HLA 模式:
  Error: hla_target: invalid parameter -ap-num (> 0)
  
  ↑ HLA 不支持 AP 号参数！

这就是根本矛盾：
  CYT2BL3 需要 AP1 → ST-Link HLA 不支持 → 失败
```

### 2.4 ST-Link 的新固件呢？

```
ST-Link V2 固件 >= V2.J21.S4 支持 DAP API（新接口）

但需要:
  1. 固件版本够新
  2. 使用 interface/stlink-dap.cfg (而非 stlink.cfg)
  3. 直接 SWD 传输模式

我们的测试:
  - stlink.cfg    → hla_swd → 不支持多 AP ❌
  - stlink-dap.cfg → swd     → "adapter doesn't support SWD" ❌
  
说明你的 ST-Link V2 固件版本不够新，或不支持 DAP API。
（克隆版 ST-Link 的固件更是未知数）
```

---

## 三、各大工具对 TRAVEO T2G 的支持

| 工具/探针 | SWD | 支持 AP0+AP1 | CYT2BL3 Flash | 备注 |
|----------|:---:|:---:|:---:|------|
| **J-Link** (原装) | ✅ | ✅ | ✅ | SEGGER + Infineon 合作 |
| **KitProg3** | ✅ | ✅ | ✅ | Infineon 官方板载 |
| **MiniProg4** | ✅ | ✅ | ✅ | Infineon 独立调试器 |
| ST-Link V2 (原装) | ✅ | ⚠️ 需新固件 | ❌ | HLA 模式限制 |
| ST-Link V2 (克隆) | ✅ | ❌ | ❌ | 固件未知，DAP API 不可用 |
| **probe-rs** | ✅ | ❌ | ❌ | 缺 TRAVEO 连接序列 |

---

## 四、SEGGER J-Link 对 CYT2BL 的官方支持

SEGGER 官方设备列表明确列出：

```
✅ Traveo II (CYT2B6)
✅ Traveo II (CYT2B7)  
✅ Traveo II (CYT2B9)
✅ Traveo II (CYT2BL)     ← 你的芯片！
✅ Traveo II (CYT2CL)
✅ Traveo II (CYT3BB)
...
```

> 来源：https://www.segger.com/supported-devices/jlink/

---

## 五、解决方案

### 🥇 买 J-Link（推荐）

```
SEGGER J-Link EDU Mini:    ~¥200
SEGGER J-Link EDU:         ~¥400

支持：
  ✅ 所有 TRAVEO T2G 芯片
  ✅ Infineon OpenOCD
  ✅ J-Flash GUI
  ✅ probe-rs (连接+调试)
  ✅ 高速 SWD (4-15 MHz)
  ✅ RTT 日志
  ✅ 无限 Flash 断点
```

### 🥈 买 Infineon MiniProg4

```
Infineon MiniProg4:  ~¥150

支持：
  ✅ Infineon 全系列
  ✅ OpenOCD (CMSIS-DAP)
  ✅ ModusToolbox
```

### 🥉 继续用 ST-Link（部分功能）

```
你现在可以:
  ✅ probe-rs info → 查看芯片 CoreSight 架构
  ✅ probe-rs read → 读写 SRAM
  ✅ 编译 → make all → firmware.hex

不能:
  ❌ 烧录 Flash（所有工具都不行）
```

---

## 六、总结

```
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║  Infineon OpenOCD 不支持 ST-Link V2 的根本原因：              ║
║                                                              ║
║  ST-Link 用 HLA 模式 → 不支持多 AP                           ║
║  CYT2BL3 是双核 → 需要访问 AP0 + AP1                        ║
║  HLA 不支持 AP 号 > 0 → 直接报错                             ║
║                                                              ║
║  这和 SWD 协议没关系！SWD 本身完全支持多 AP。                 ║
║  问题在 ST-Link 固件暴露给 OpenOCD 的接口层次。              ║
║                                                              ║
║  J-Link / KitProg3 / MiniProg4 用原生 DAP API               ║
║  → 支持所有 AP → CYT2BL3 完美支持                           ║
║                                                              ║
║  🥇 推荐: 买 J-Link EDU Mini (~¥200)                        ║
║     一劳永逸，SEGGER 官方支持 CYT2BL                        ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
```

---

*报告版本：v1.0 | 2026-05-04 | 基于 OpenOCD 官方文档 + Infineon ModusToolbox 文档*
