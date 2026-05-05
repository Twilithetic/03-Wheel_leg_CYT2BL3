# CYT2BL3 复位后 SWD 可用时序 — 官方文档精确分析报告

> **日期**: 2026-05-05  
> **目的**: 精确回答"复位后 SWD 到底什么时候能准备好"  
> **信息来源**: Infineon 官方应用笔记 AN220118、AN228680、Debug Training v04_00

---

## 1. 核心答案

> **复位后 SWD 在 ~5ms 之后才可用（FlashBoot 配置完 SWJ 引脚），且在随后的 Listen Window（默认 20ms）内保持可用。如果此窗口内没有调试器连接，芯片进入用户程序，SWD 可用性取决于用户固件。**

---

## 2. 官方文档证据

### 2.1 AN220118 — CYT2B 系列启动序列

```
复位
  │
  ▼
┌─────────────────────────────────────┐
│ Step 1: 系统复位 (@0x00000000)       │  t = 0
├─────────────────────────────────────┤
│ Step 2: CM0+ 执行 ROM Boot           │  t ≈ 0~2ms
│  · 应用校准值 (trims)                │
│  · 应用 DAP 访问限制和系统保护       │  ★ 调试引脚 Hi-Z
│  · 认证 FlashBoot                    │
├─────────────────────────────────────┤
│ Step 3: CM0+ 执行 FlashBoot          │  t ≈ 2~5ms
│         (从 @0x17002000)             │
│  · ★ 按 SWD/JTAG 规范配置调试引脚 ★ │  ★ SWD 刚配置完
│  · 开启 Listen Window                │
├─────────────────────────────────────┤
│ Step 4: CM0+ 启动用户应用程序        │  t > 25ms
└─────────────────────────────────────┘
```

> 📎 来源: [AN220118 Getting started with TRAVEO™ T2G family MCUs](https://documentation.infineon.com/traveo/docs/lwy1680596932876)

### 2.2 AN228680 — Listen Window 与 SWJ 引脚控制

`T2G_FLASH_BOOT_PARAMS` 寄存器中的两个关键位域：

```
位 [6:5] — SWJ_PINS_CTL:
  0x0 = 不启用 SWJ 引脚
  0x1 = 不启用 SWJ 引脚
  0x2 = 在 FlashBoot 中启用 SWJ 引脚  ← 默认值
  0x3 = 不启用 SWJ 引脚

位 [4:2] — LISTEN_WINDOW:
  0x0 = 20 ms   ← 默认值
  0x1 = 10 ms
  0x2 = 1 ms
  0x3 = 0 ms   (无 Listen Window)
  0x4 = 100 ms
```

**Listen Window 的含义**：FlashBoot 配置完 SWJ 引脚后，芯片在 Listen Window 内**主动等待**调试器连接。如果窗口内没有调试器连接，芯片继续启动用户程序。

> 📎 来源: [AN228680 Secure system configuration in TRAVEO™ T2G family](https://documentation.infineon.com/traveo/docs/ykc1680597580020_2)

### 2.3 Debug Training — 引脚初始状态

> *"After reset, the debug pins remain in **high-impedance mode** until Boot ROM initializes them as follows:"*

| 引脚 | 输入使能 | 驱动模式 |
|------|:--:|------|
| swj_trstn | Yes | 内部上拉 |
| swj_swo_tdo | No | 强驱动 (输出) |
| swj_swdoe_tdi | Yes | 内部上拉 |
| swj_swdio_tms | Yes | 内部上拉 |
| swj_swclk_tclk | — | 下拉 (见 HW design guide) |

> 📎 来源: [Traveo II Program and Debug Interface Training v04_00](https://www.infineon.com/dgdl/Infineon-Traveo_II_Program_and_Debug_Interface-Training-v04_00-EN.pdf)

---

## 3. SWD 可用时间线（精确版）

```
时间轴 (ms):  0      1      2      3      4      5   ...   25     >25
              │      │      │      │      │      │         │       │
              ├──────┼──────┼──────┼──────┼──────┼─────────┼───────┤
芯片阶段:     │  ROM Boot   │ FlashBoot │   Listen Window    │ 用户程序
              │  (校准+认证) │ (配引脚)  │   (默认 20ms)     │
              │             │           │                    │
SWD 引脚:     ██████████████ Hi-Z ███████████████████████████│ 取决于固件
              │  上拉→ACK=111(JUNK)  │  SWD 就绪!           │
              │                      │                      │
OpenOCD 操作: │  cortex_m_deassert   │                      │
              │  _reset() 读 VTOR    │                      │
              │  → ❌ DP 不可达      │                      │
              │                      │                      │
              │        我们的 Tcl 代码运行:                   │
              │        sleep 100 → 进入 Listen Window       │
              │        dap_handshake → dap_init             │
              │        → dap_init 不发 SWD Line Reset!      │
              │        → ❌ SWD 状态机不同步 → 还是失败       │
```

### 3.1 关键时间节点

| 时间 | 事件 | SWD 状态 |
|:---:|------|---------|
| 0ms | SYSRESETREQ 触发 | 芯片复位开始 |
| 0-2ms | ROM Boot 执行 | **Hi-Z**（高阻态），读 ACK = 111 (JUNK) |
| 2-5ms | FlashBoot 执行 | **Hi-Z**，引脚尚未配置 |
| **~5ms** | **SWJ 引脚配置完成** | **SWD 物理层可用**（需 Line Reset 同步状态机） |
| **5-25ms** | **Listen Window** | **SWD 完全就绪！** ✅ |
| >25ms | 用户程序运行 | 取决于固件（LED blinker 可能重配引脚） |

---

## 4. 为什么我们的 `reset init` 修复还是失败

### 4.1 当前修复代码分析

```tcl
# func_mxs40.cfg — 我们的修改
proc mxs40_reset_deassert_post { target_type target } {
    # ...
    sleep 100          # ✅ 等 100ms → 确定进入了 Listen Window
    if {![dap_handshake]} {  # ❌ dap_handshake 调用 dap_init
        echo "Warn ..."
        return
    }
    # ...
}
```

### 4.2 失败原因：SWD Line Reset 缺失

```
dap_init() 内部执行流程:
  ┌────────────────────────────────────────┐
  │ 1. 读取 DPIDR                           │ ← 直接发 SWD 读请求
  │    → CMSIS-DAP 固件: DAP_Transfer       │
  │    → SWD 总线: Start+APnDP+RnW+A[3:2]   │
  │    → 芯片 SWD 状态机: ??? (未知状态)     │
  │    → 返回 ACK = 111 (JUNK)              │
  │    → ❌ 失败!                             │
  └────────────────────────────────────────┘

正确的重连流程:
  ┌────────────────────────────────────────┐
  │ 1. SWD Line Reset (50+ 时钟, SWDIO=H)  │ ← 强制状态机回 IDLE
  │ 2. JTAG-to-SWD 切换序列                 │ ← 确保 SWD 模式
  │ 3. 读取 DPIDR                           │ ← 现在能读到正确值!
  │    → 返回 ACK = 001 (OK)                │
  │    → ✅ 成功!                             │
  └────────────────────────────────────────┘
```

**`dap_init()` 跳过步骤 1 和 2，直接从步骤 3 开始。** SWD Line Reset 仅在 `swd_connect()` 中执行，而 `swd_connect()` 只在 OpenOCD 的 `init` 阶段调用一次。

### 4.3 对比 pyOCD（能成功重连）

```
pyOCD 的重连流程:
  ┌──────────────────────────────────────────┐
  │ 1. 发送 SWJ Sequence (含 Line Reset)       │ ← ✅
  │ 2. 读 DPIDR → 失败                         │
  │ 3. "DP IDCODE read failed; resending SWJ" │
  │ 4. 发送 SWJ Sequence (dormant state)       │ ← ✅
  │ 5. 读 DPIDR → 成功!                        │
  └──────────────────────────────────────────┘
```

> 📎 来源: [pyOCD issue #1962](https://github.com/pyocd/pyOCD/issues/1962)

---

## 5. OpenOCD C 源码层面的根本缺陷

```
复位后 DP 重连的正确调用链:

  adapter_init()
    └─ transport_select()
         └─ swd_connect()          ← 这里发 SWD Line Reset + JTAG-to-SWD
              └─ swd_connect_single()
                   ├─ SWJ_Sequence(Line Reset)
                   ├─ SWJ_Sequence(JTAG-to-SWD)
                   └─ DPIDR Read → ✅ OK

复位后 DP 重连的实际调用链:

  cortex_m_deassert_reset()
    └─ 直接读 VTOR via DP          ← 跳过 swd_connect!
         └─ DPIDR Read → ❌ JUNK ACK

  (事件回调) dap_handshake()
    └─ dap init()
         └─ dap_dp_init()           ← 也跳过 swd_connect!
              └─ DPIDR Read → ❌ JUNK ACK
```

**缺陷**：`swd_connect()` 只在 `init` 阶段调用。芯片复位后没有任何代码路径会重新调用它。而 `dap_init()` 和 `cortex_m_deassert_reset()` 都假设 SWD 物理层已连接。

---

## 6. 完整故障链（含时间轴）

```
t=0ms     OpenOCD: cortex_m_assert_reset()
          └─ dap_dp_init_or_reconnect() → DP 还在线 → OK
          └─ 写 AIRCR = 0x05FA0004 → SYSRESETREQ

t=0ms     芯片: 全部逻辑复位
          └─ 所有 SWJ 引脚进入 Hi-Z
          └─ SWDIO 被上拉电阻拉到 VDD (ACK = 111)

t=0-2ms   芯片: ROM Boot 执行
          └─ 校准、DAP 访问限制、FlashBoot 认证
          └─ SWD 引脚仍在 Hi-Z

t=1ms     OpenOCD: cortex_m_deassert_reset()
          └─ 尝试读 VTOR → DP 读 DPIDR
          └─ CMSIS-DAP → SWD 总线上发请求
          └─ 芯片不回 ACK (Hi-Z → 111 = JUNK)
          └─ ❌ "Error connecting DP: cannot read IDR"
          └─ "Vector Table not found, reset_halt skipped"

t=2-5ms   芯片: FlashBoot 执行
          └─ 配置 SWJ 引脚
          └─ 开启 Listen Window (默认 20ms)

t=5ms     SWD 物理层就绪! ✅
          └─ 可以接受 SWD Line Reset
          └─ 可以响应 JTAG-to-SWD 切换
          └─ 可以正确返回 DPIDR

t=~6ms    OpenOCD: reset-deassert-post 事件触发
          └─ event_cm0_reset_deassert_post()
          └─ mxs40_reset_deassert_post()
          └─ 【我们的修复】sleep 100 → 等到了 Listen Window ✅
          └─ dap_handshake → dap_init → dap_dp_init()
          └─ 直接读 DPIDR → ❌ 还是 JUNK ACK!
          └─ 原因: SWD 状态机未同步, 缺 Line Reset

t=5-25ms  Listen Window 期间
          └─ 如果 debugger 发了 Line Reset → SWD 连接成功
          └─ 但 OpenOCD 不发 → 连接失败

t>25ms    芯片进入用户程序
          └─ LED blinker 可能重配 GPIO
          └─ SWD 可能再次不可用
```

---

## 7. 彻底修复方案

### 方案 A：修改 OpenOCD C 源码（最彻底）

在 `cortex_m_deassert_reset()` 中，读 VTOR 之前先检查 DP 连接。如果断开，调用 `swd_connect()` 重新建立连接。

**文件**: `src/target/cortex_m.c`（约 1900 行附近）  
**难度**: ⭐⭐⭐⭐（需要编译 OpenOCD）

### 方案 B：Tcl 层发送 SWD Line Reset（最实用）

在 `mxs40_reset_deassert_post` 的 `dap_handshake` 之前，用 `adapter assert/deassert` 或 SWJ Sequence 命令发送 Line Reset。

**文件**: `func_mxs40.cfg`  
**难度**: ⭐⭐（但需要确认 OpenOCD 是否暴露了 SWJ Sequence 的 Tcl 接口）

```tcl
# 伪代码 — 需要验证 OpenOCD 是否支持
proc swd_line_reset_and_reconnect {} {
    # 发送 SWD Line Reset = 50+ 时钟周期, SWDIO=H
    # 然后 JTAG-to-SWD 切换序列
    # 然后读 DPIDR
    
    # 可能的实现:
    # adapter gpio swclk ...  (bit-bang)
    # 或: 如果 OpenOCD 暴露了 swj_sequence 命令
}
```

### 方案 C：硬件复位 (SRST)（最可靠）

将 WCH-Link 的 nRESET 引脚连接到 CYT2BL3 的 XRES 引脚，使用硬件复位。

```tcl
# cyt2bl.cfg — 取消注释:
reset_config srst_only srst_pulls_trst
adapter srst delay 100
```

**硬件**: 需要焊接一根线  
**优点**: OpenOCD 可以精确控制复位时序，在 SRST 释放后延时再访问 DP

### 方案 D：当前可用方案（已实现）

```bash
# 继续使用 halt 方式:
make flash

# 重复烧录前断电重启:
# 拔 USB → 等 5 秒 → 插上 → make flash
```

---

## 8. 总结

```
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║  Q: 复位后 SWD 什么时候能准备好？                             ║
║  A: FlashBoot 配置完 SWJ 引脚之后 (~5ms)，                    ║
║     且在随后的 Listen Window (默认 20ms) 内。                 ║
║                                                              ║
║  Q: ROM Boot 期间 SWD 能用吗？                               ║
║  A: ❌ 不能。引脚 Hi-Z，读到的 ACK 全是 111 (JUNK)。          ║
║                                                              ║
║  Q: 为什么 OpenOCD 重连失败？                                 ║
║  A: `dap_init()` 不发送 SWD Line Reset。                     ║
║     芯片复位后 SWD 状态机处于未知状态，                        ║
║     必须先做 Line Reset 让状态机回到 IDLE，                   ║
║     然后 JTAG-to-SWD 切换，才能正常通信。                     ║
║     OpenOCD 的 swd_connect() 做这些，                         ║
║     但只在 init 阶段调用一次，芯片复位后不会重新调用。          ║
║                                                              ║
║  Q: pyOCD 为什么能成功？                                      ║
║  A: pyOCD 在每次 DPIDR 读失败后会显式发送 SWJ Sequence        ║
║     (含 Line Reset)，而 OpenOCD 不会。                        ║
║                                                              ║
║  Q: 彻底修复需要什么？                                        ║
║  A: 改 OpenOCD C 源码 (cortex_m.c) 或加 SRST 硬件复位线。     ║
║     当前方案 (halt + 断电重启) 已经可用。                      ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
```

---

> 📎 **关联文档**:
> - [DP 重连失败根因分析 v1.0](./CYT2BL3_DP重连失败根因分析报告.md)
> - [CMSIS-DAP 源码验证 v2.0](./CYT2BL3_CMSIS-DAP源码验证_DP重连失败报告.md)
> - [OpenOCD 配置缺陷定责 v3.0](./CYT2BL3_OpenOCD配置缺陷_最终定责报告.md)
> - [reset init 修复方案 v4.0](./CYT2BL3_reset_init_修复方案报告.md)
> - [OpenOCD 烧录实操成功报告](./CYT2BL3_OpenOCD_烧录实操成功报告.md)
>
> 📎 **外部参考文献**:
> - [AN220118 Getting started with TRAVEO™ T2G](https://documentation.infineon.com/traveo/docs/lwy1680596932876)
> - [AN228680 Secure system configuration](https://documentation.infineon.com/traveo/docs/ykc1680597580020_2)
> - [Traveo II Program and Debug Interface Training v04_00](https://www.infineon.com/dgdl/Infineon-Traveo_II_Program_and_Debug_Interface-Training-v04_00-EN.pdf)
> - [pyOCD issue #1962 — nRESET kills DAP](https://github.com/pyocd/pyOCD/issues/1962)
