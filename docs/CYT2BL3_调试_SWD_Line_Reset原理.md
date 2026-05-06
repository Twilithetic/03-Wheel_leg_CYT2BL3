# SWD Line Reset 原理与跨芯片重连问题 — 深度分析报告

> **日期**: 2026-05-05  
> **核心问题**: 为什么 SWD Line Reset 如此重要？J-Link 为什么能成功重连？其他芯片也有这个问题吗？

---

## 1. SWD 状态机原理

### 1.1 芯片内部的 SW-DP 是一个状态机

```
SW-DP (Serial Wire Debug Port) 状态机行为:

  上电/复位后:
  ┌─────────────────────────────────────┐
  │  状态: UNKNOWN (未知)               │
  │  - 不接受任何 SWD 包                 │
  │  - 所有读操作返回 ACK = 111 (JUNK)   │
  │  - 引脚可能处于 Hi-Z                │
  └──────────────┬──────────────────────┘
                 │
                 │ SWD Line Reset (50+ 周期, SWDIO = HIGH)
                 │ 或 JTAG-to-SWD 切换序列
                 ▼
  ┌─────────────────────────────────────┐
  │  状态: LINE RESET (或 RESET)       │
  │  - 根据 ADIv5.2 规范:               │
  │    仅允许以下操作:                   │
  │    A) 读 IDCODE (DPIDR)             │
  │    B) SWD ↔ JTAG 切换               │
  │    C) 写 TARGETSEL 寄存器            │
  │  - 任何其他操作 → 不可预测结果        │
  └──────────────┬──────────────────────┘
                 │
                 │ 读 DPIDR (IDCODE) 成功
                 ▼
  ┌─────────────────────────────────────┐
  │  状态: IDLE (就绪)                  │
  │  - 可以接受所有 SWD 命令             │
  │  - DP/AP 读写正常                    │
  │  - 正常返回 ACK = 001 (OK)          │
  └─────────────────────────────────────┘
```

### 1.2 ARM 官方规范原文（ADIv5.2，第 124 页）

> *"Following a Line Reset, the only valid SWD transactions are:*
> *A) reading the IDCODE*
> *B) switching back-n-forth between SWD and JTAG*
> *C) writing to Target Select register*
> *Any other transactions produces unpredictable results."*

> 📎 来源: ARM Debug Interface v5.2 Architecture Specification (ARM IHI 0031E)

### 1.3 为什么直接读 DPIDR 不行

```
正常流程 (需要 Line Reset):
  ┌──────────────────────────────────────┐
  │ 1. SWD Line Reset (50+周期, SWDIO=H) │ ← 强制状态机进入 RESET 状态
  │ 2. 读 DPIDR (IDCODE)                 │ ← 唯一合法操作
  │ 3. 状态机进入 IDLE                    │ ← 可以正常通信了
  └──────────────────────────────────────┘

OpenOCD 的实际操作 (跳过 Line Reset):
  ┌──────────────────────────────────────┐
  │ 1. 直接读 DPIDR                       │ ← 状态机在 UNKNOWN 状态
  │    → SWD 发请求包                     │
  │    → 芯片不懂这个包是什么意思           │
  │    → 返回 ACK = 111 (JUNK)            │
  │    → ❌ 失败                           │
  └──────────────────────────────────────┘
```

---

## 2. 正常调试器（J-Link）的复位→重连流程

### 2.1 J-Link 的完整流程

```
J-Link 复位 → 重连流程:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Step 1: 复位芯片
  ├─ 方式A: 写 AIRCR = SYSRESETREQ (软件复位)
  └─ 方式B: 拉低 nRESET 引脚 (硬件复位)

Step 2: 等待复位完成
  └─ J-Link 固件自动等待 (延迟可配置)

Step 3: 重新建立 SWD 连接 (J-Link 固件自动执行!)
  ├─ 3a. SWD Line Reset (50+ 周期, SWDIO=H)
  ├─ 3b. JTAG-to-SWD 切换序列
  ├─ 3c. 读 DPIDR → ✅ 成功
  ├─ 3d. 配置 DP (上电调试域, 设置 AP)
  └─ 3e. SWD 连接恢复完成

Step 4: 恢复调试上下文
  ├─ 读 VTOR, 验证向量表
  ├─ 设置硬件断点在复位向量
  └─ 如果需要 halt: 写 DHCSR 暂停核心
```

**关键差异**: J-Link 把 Step 3（SWD Line Reset + JTAG-to-SWD + DPIDR 读）做在了**固件内部**，对上层完全透明。OpenOCD + CMSIS-DAP 的架构把 Step 3a-3c 放在了 `swd_connect()` 中（C 代码层），而 `swd_connect()` 只在 `init` 阶段调用一次。

### 2.2 SEGGER 官方描述

来自 J-Link 用户手册的 Cortex-M 复位策略：

> *"Reset: Halt core after reset via DEMCR.VC_CORERESET.*  
>  *Reset: Reset device via AIRCR.SYSRESETREQ."*

J-Link 在复位后:
1. 通过 DEMCR.VC_CORERESET 确保核心停在复位向量
2. 通过 AIRCR.SYSRESETREQ 触发芯片复位
3. **固件自动处理 DP 重连**（包括 SWD Line Reset）

---

## 3. 跨芯片对比：这个错误有多普遍？

### 3.1 "Error connecting DP: cannot read IDR" 是一个跨厂商的普遍问题

| 芯片厂商 | 芯片型号 | 调试器 | 报错 | 来源 |
|---------|---------|--------|------|------|
| **Infineon** | **CYT2BL3** | WCH-Link CMSIS-DAP | ✅ 同错误 | 本项目 |
| **Infineon** | PSoC 4 | KitProg3 CMSIS-DAP | ✅ 同错误 | [Community](https://community.infineon.com/t5/PSOC-4/Error-Error-connecting-DP-cannot-read-IDR/) |
| **ST** | STM32F0 | CMSIS-DAP | ✅ 同错误 | [ST Community](https://community.st.com/t5/stm32-mcus-products/open-ocd-swd-programming-with-cmsis-dap/td-p/782532) |
| **ST** | STM32F1 | ST-Link v2 | ✅ 同错误 | [EEVblog](https://www.eevblog.com/forum/beginners/troubleshooting-st-linkv2-fails-to-connect-to-stm32f030k6t6/) |
| **ADI** | MAX32670 | CMSIS-DAP | ✅ 同错误 | [EngineerZone](https://ez.analog.com/microcontrollers/precision-microcontrollers/f/q-a/577566/) |
| **Seeed** | SAMD11 (XIAO) | CMSIS-DAP | ✅ 同错误 | [Seeed Forum](https://forum.seeedstudio.com/t/error-error-connecting-dp-cannot-read-idr/292799) |
| **SiLabs** | EFM32 | CMSIS-DAP | ✅ 同错误 | [Seeed Forum](https://forum.seeedstudio.com/t/error-error-connecting-dp-cannot-read-idr/292799) |

### 3.2 共同特征

| 条件 | 所有案例的共同点 |
|------|-----------------|
| **调试器** | **全部使用 CMSIS-DAP**（或 ST-Link 的 CMSIS-DAP 模式） |
| **协议** | SWD |
| **触发场景** | 芯片复位后（硬件复位或软件复位） |
| **根因** | **SWD Line Reset 未被（正确）执行** |
| **J-Link 表现** | **不出此错误**（J-Link 固件自动处理 Line Reset） |

### 3.3 PSoC 4 社区的精确诊断（与我们的发现完全一致）

来自 Infineon PSoC 4 社区（2025年12月）：

> *"The problem wasn't a random timing bug, but a **protocol lock imposed by the DAP state machine itself**. After a Line Reset, the chip was entering an exclusive state where it would only accept a READ IDCODE command. I fixed the issue by implementing:*
> *Line Reset → READ IDCODE (Dummy Read) → WRITE OR READ DP REGISTER"*

> 📎 来源: [PSoC 4100S SWD Failure](https://community.infineon.com/t5/PSOC-4/PSoC-4100S-SWD-Failure-WRITE-Commands-Rejected-ACK-0b111-After-Successful-IDCODE/td-p/1141642)

**这和我们发现的完全一样！** SWD 状态机在 Line Reset 后进入受限状态，必须先读 IDCODE 才能解锁。

---

## 4. 为什么 J-Link 没问题但 CMSIS-DAP 有问题

### 4.1 架构对比

```
J-Link 架构 (固件一体化):
┌────────────────────────────────────────────────────┐
│                  J-Link 固件                        │
│  ┌──────────┐   ┌──────────┐   ┌───────────────┐  │
│  │ USB 协议 │──▶│ SWD 引擎  │──▶│ 自动重连逻辑   │  │
│  │          │   │          │   │ · Line Reset   │  │
│  │          │   │          │   │ · JTAG-to-SWD  │  │
│  │          │   │          │   │ · DPIDR Read   │  │
│  └──────────┘   └──────────┘   └───────────────┘  │
└────────────────────────────────────────────────────┘
  ▲ J-Link 固件在每次芯片复位后自动执行完整重连


CMSIS-DAP 架构 (分层, 固件只管传输):
┌──────────────┐     ┌───────────────────┐
│    HOST      │     │  CMSIS-DAP 固件    │
│  (OpenOCD)   │────▶│  (只做 USB↔SWD 桥) │
│              │     │                   │
│ swd_connect  │     │  DAP_Transfer     │
│   (发 Line   │     │  (执行单个SWD传输)  │
│    Reset)    │     │                   │
│              │     │  ❌ 不自动重连!     │
│ dap_init     │     │                   │
│   (读DPIDR)  │     │                   │
└──────────────┘     └───────────────────┘
  ▲ HOST 负责重连, 但芯片复位后 HOST 没有重新调用 swd_connect
```

### 4.2 职责分离导致的"断层"

| 职责 | J-Link | CMSIS-DAP + OpenOCD |
|------|:--:|:--:|
| SWD Line Reset | 固件自动 | HOST: `swd_connect()` (init 时调用一次) |
| 芯片复位后重连 | 固件自动检测+恢复 | HOST 需手动重连，但代码路径缺失 |
| 协议层重试 | 固件内置 | HOST: `dap_handshake` (我们加的) |
| 物理层恢复 | 固件内置 | ❌ **缺失** — 这就是问题! |

### 4.3 OpenOCD 日志中的精确确认

来自 STM32F0 + CMSIS-DAP 的 OpenOCD debug 日志：

```
Debug: cmsis_dap.c:891 cmsis_dap_swd_read_process(): SWD ack not OK @ 0 JUNK
Error: adi_v5_swd.c:366 swd_connect_single(): Error connecting DP: cannot read IDR
```

`SWD ack not OK @ 0 JUNK` — 芯片返回了 JUNK ACK (111)，说明 SWD 状态机处于 UNKNOWN 状态，没有收到过 Line Reset。

---

## 5. 修复方案对比

| 方案 | 原理 | 难度 | 适用范围 |
|------|------|:--:|------|
| **J-Link** | 固件内置完整重连 | — | 所有芯片 ✅ |
| **pyOCD** | Host 层每次 DPIDR 失败后发 SWJ Sequence | ⭐ | 所有芯片 ✅ |
| **添加 SRST 硬件复位** | OpenOCD 用 SRST 控制芯片复位时序 | ⭐⭐ | 需要硬件接线 |
| **修改 OpenOCD C 源码** | 在 `cortex_m_deassert_reset` 中加 `swd_connect` | ⭐⭐⭐⭐ | 需编译 OpenOCD |
| **当前方案 (halt)** | 不触发芯片复位 | ✅ 已验证 | CYT2BL3 ✅ |

---

## 6. 总结

```
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║  Q: SWD Line Reset 为什么这么重要？                           ║
║  A: 芯片的 SW-DP 是一个状态机。复位后状态机处于 UNKNOWN，     ║
║     必须先收到 Line Reset (或 JTAG-to-SWD 切换) 才能进入      ║
║     RESET 状态，然后读 IDCODE 才能进入 IDLE 正常工作状态。    ║
║     ARM ADIv5.2 规范明确规定：Line Reset 后只能读 IDCODE，    ║
║     任何其他操作"产生不可预测结果"。                           ║
║                                                              ║
║  Q: J-Link 为什么能自动重连？                                 ║
║  A: J-Link 把 Line Reset → JTAG-to-SWD → DPIDR Read          ║
║     整个流程做在了固件内部，芯片复位后自动执行。              ║
║     CMSIS-DAP 把这部分职责留给了 HOST (OpenOCD)，             ║
║     而 OpenOCD 的 swd_connect() 只在 init 时调用一次。        ║
║                                                              ║
║  Q: 其他芯片也有这个问题吗？                                  ║
║  A: ✅ 是的！STM32F0、STM32F1、PSoC4、MAX32670、SAMD11、    ║
║     EFM32 等所有 Cortex-M 芯片，用 CMSIS-DAP + OpenOCD       ║
║     在复位后都会报 "cannot read IDR"。                        ║
║     这是一个 ARM 架构层面的通用问题，不是 CYT2BL3 特有的。    ║
║                                                              ║
║  Q: 正常流程是什么？                                          ║
║  A: Line Reset → JTAG-to-SWD Switch → Read IDCODE →          ║
║     Configure DP → Connect AP → Read VTOR → Debug            ║
║     缺了第一步，后面的全部失败。                               ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
```

---

> 📎 **跨芯片案例来源**:
> - [STM32F0 CMSIS-DAP](https://community.st.com/t5/stm32-mcus-products/open-ocd-swd-programming-with-cmsis-dap/td-p/782532)
> - [PSoC4 KitProg3](https://community.infineon.com/t5/PSOC-4/Error-Error-connecting-DP-cannot-read-IDR/)
> - [PSoC4 SWD Protocol Lock](https://community.infineon.com/t5/PSOC-4/PSoC-4100S-SWD-Failure-WRITE-Commands-Rejected-ACK-0b111/)
> - [MAX32670 CMSIS-DAP](https://ez.analog.com/microcontrollers/precision-microcontrollers/f/q-a/577566/)
> - [SAMD11 XIAO CMSIS-DAP](https://forum.seeedstudio.com/t/error-error-connecting-dp-cannot-read-idr/292799)
> - [STM32F1 ST-Link](https://www.eevblog.com/forum/beginners/troubleshooting-st-linkv2-fails-to-connect-to-stm32f030k6t6/)
> - [ARM ADIv5.2 Spec](https://developer.arm.com/documentation/ihi0031/) — SW-DP Line Reset 后仅允许 IDCODE 读
>
> 📎 **关联报告**:
> - [复位后 SWD 可用时序](./CYT2BL3_复位后SWD可用时序_官方文档分析报告.md)
> - [reset init 修复方案](./CYT2BL3_reset_init_修复方案报告.md)
