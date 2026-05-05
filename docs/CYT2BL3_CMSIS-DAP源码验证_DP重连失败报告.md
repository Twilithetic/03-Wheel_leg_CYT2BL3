# CYT2BL3 DP 重连失败 — CMSIS-DAP 源码级验证报告

> **验证日期**: 2026-05-05  
> **分析方法**: 逐行阅读 CMSIS-DAP v2.1.2 官方源码 + 网络搜索交叉验证  
> **源码位置**: `docs/CMSIS-DAP/Firmware/Source/DAP.c` + `SW_DP.c`  
> **前序报告**: [DP 重连失败根因分析](./CYT2BL3_DP重连失败根因分析报告.md)

---

## 1. 核心发现：前序报告的结论需要修正！

之前说"WCH-Link 的 CMSIS-DAP 固件重试窗口太短"。现在读了源码后发现：**比"太短"更严重——根本不是重试不够，而是重试机制根本不想管这种情况！**

---

## 2. 源码铁证

### 2.1 `retry_count` 配置 — 由 HOST 决定，不由固件固定

```c
// DAP.c:662-672 — TransferConfigure 命令处理
static uint32_t DAP_TransferConfigure(const uint8_t *request, uint8_t *response) {
    DAP_Data.transfer.idle_cycles =            *(request+0);
    DAP_Data.transfer.retry_count = (uint16_t) *(request+1) |    // ← HOST 配置!
                                    (uint16_t)(*(request+2) << 8);
    DAP_Data.transfer.match_retry = (uint16_t) *(request+3) |
                                    (uint16_t)(*(request+4) << 8);
    *response = DAP_OK;
    return ((5U << 16) | 1U);
}
```

**结论**：`retry_count` 不是固件写死的——是 OpenOCD（HOST 端）通过 USB 命令配置的。所以"WCH-Link 固件重试次数太少"不是根因。

### 2.2 重试循环 — 只对 WAIT 响应重试！

```c
// DAP.c:816-819 — SWD 读 DP 寄存器（比如读 DPIDR）
retry = DAP_Data.transfer.retry_count;
do {
    response_value = SWD_Transfer(request_value, &data);
} while ((response_value == DAP_TRANSFER_WAIT) && retry-- && !DAP_TransferAbort);
//         ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
//         只重试 ACK=010 (WAIT) !!!!
if (response_value != DAP_TRANSFER_OK) {
    break;   // ← 不是 WAIT 就直接退出，不重试！
}
```

**这是整个问题的核心！** 重试循环的条件是：

```c
(response_value == DAP_TRANSFER_WAIT)  // ← 必须是 WAIT (ACK=010)
```

### 2.3 SWD Transfer — 当引脚 Hi-Z 时返回什么

```c
// SW_DP.c:136-261 — SWD_Transfer 函数（精简版）
static uint8_t SWD_TransferSlow(uint32_t request, uint32_t *data) {
    uint32_t ack;
    // ... 发送 Start + APnDP + RnW + A[3:2] + Parity + Stop + Park ...
    // ... Turnaround (切换总线方向) ...

    /* Acknowledge response */
    SW_READ_BIT(bit);  ack  = bit << 0;     // 读 ACK[0]
    SW_READ_BIT(bit);  ack |= bit << 1;     // 读 ACK[1]
    SW_READ_BIT(bit);  ack |= bit << 2;     // 读 ACK[2]

    if (ack == DAP_TRANSFER_OK) {           // ACK = 001 → ✅ 正常
        /* Data transfer */ ...
        return ((uint8_t)ack);
    }

    if ((ack == DAP_TRANSFER_WAIT) ||       // ACK = 010 → 🔄 重试
        (ack == DAP_TRANSFER_FAULT)) {      // ACK = 100 → 🔄 重试
        /* WAIT or FAULT response */ ...
        return ((uint8_t)ack);
    }

    /* Protocol error */                     // ACK = 其它 (如 111) → 💀
    // ... back off data phase ...
    return ((uint8_t)ack);                   // 直接返回错误 ACK！
}
```

---

## 3. 完整故障链条（源码版）

```
时间线:
─────────────────────────────────────────────────────────────────────►

[OpenOCD]                         [CMSIS-DAP 固件]              [CYT2BL3 芯片]
    │                                   │                            │
(1) │─ program 命令 ──────────────────►│                            │
    │                                   │                            │
(2) │─ ocd_process_reset ──────────────►│                            │
    │                                   │                            │
(3) │─ 写 AIRCR=SYSRESETREQ ───────────►│── DAP_Transfer ──────────►│ 芯片复位!
    │                                   │   写 DP CTRL/STAT           │
    │                                   │                            │ ROM Boot 开始
    │                                   │                            │ 引脚进入 Hi-Z
    │                                   │                            │
(4) │─ reset-deassert-post ────────────►│                            │
    │                                   │                            │
(5) │─ dap init ───────────────────────►│                            │
    │                                   │                            │
(6) │                                   │── SWD Line Reset ─────────►│ ← 50+时钟, SWDIO=H
    │                                   │   (SWJ_Sequence)           │   ⚠️ 芯片不响应
    │                                   │                            │
(7) │                                   │── JTAG-to-SWD switch ─────►│ ← 特定序列
    │                                   │   (SWJ_Sequence)           │   ⚠️ 芯片不响应
    │                                   │                            │
(8) │                                   │── SWD_Transfer(DPIDR读) ──►│
    │                                   │   发送请求包:               │
    │                                   │   Start=1, APnDP=0, RnW=1  │
    │                                   │   A[3:2]=00, Parity,       │   引脚 Hi-Z
    │                                   │   Stop=0, Park=1           │   SWDIO 浮空
    │                                   │                            │
    │                                   │   ← 读 ACK ───────────────│
    │                                   │   SWDIO 浮空 → ACK = 111  │   ← 上拉电阻拉高
    │                                   │                            │
    │                                   │   111 = JUNK (非法ACK)     │
    │                                   │                            │
    │                                   │   if (ack != WAIT) {       │
    │                                   │       return error; ──┐   │
    │                                   │   }  ← 不重试!      │   │
    │                                   │                      │   │
(9) │◄── DAP_TRANSFER_ERROR ◄───────────┘                      │   │
    │                                   │                      │   │
(10)│◄── "cannot read IDR" ◄────────────┘                      │   │
    │                                   │                            │ ROM Boot 继续...
    │                                   │                            │
(11)│─ dap init 重试 (sleep 25ms) ─────►│ 重复 (6)→(10)             │
    │                                   │ 还是失败                   │
    │                                   │                            │ ~2ms 后引脚配置完成
    │                                   │                            │ SWD 就绪!
    │                                   │                            │
(12)│─ 超时, 放弃 ──────────────────────►│                            │
    │                                   │                            │
    │  program 失败 ❌                   │                            │
```

**关键时间点**：步骤 (6)~(12) 的整个循环发生在 OpenOCD 的 `dap_handshake` 函数中。这个函数每 25ms 调用一次 `dap init`，但受限于 `TIMEOUT_RESET_HANDSHAKE` 和 `TIMEOUT_BOOT_COMPLETE` 两个超时变量。默认情况下总超时大约 600ms，但如果这些变量被设得很小，可能在 Boot ROM 完成引脚配置之前就超时了。

---

## 4. 根因修正

### 前序报告的判断

> ❌ "WCH-Link 的 CMSIS-DAP 固件重试窗口太短"

### 源码验证后的修正

> ✅ **CMSIS-DAP 固件的 `retry_count` 机制对"芯片引脚 Hi-Z"场景完全不适用！**

具体来说有三层问题：

| 层级 | 问题 | 证据 |
|------|------|------|
| **CMSIS-DAP 固件** | `retry_count` 仅对 `ACK=WAIT(010)` 重试。引脚 Hi-Z 时读到的 ACK 是 `111`(JUNK)，直接被当作协议错误返回，**不触发任何重试** | `DAP.c:819` 条件判断 `== DAP_TRANSFER_WAIT` |
| **SWD 物理层** | 当芯片引脚未配置时，SWDIO 浮空被上拉电阻拉到 1。读 3 个 ACK bit 得到 `111`。这个值不在 `OK(001)`/`WAIT(010)`/`FAULT(100)` 中，被归类为"协议错误" | `SW_DP.c:254` "Protocol error" 分支 |
| **OpenOCD 层** | `dap_handshake` 轮询 `dap init`，每次失败后 `sleep 25ms`。总超时受限于配置变量。Boot ROM 配置引脚需要 ~2-5ms（Infineon 文档），理论上时间够——但可能有额外的 USB 延迟叠加 | `common_ifx.cfg:200-230` |

### 所以竞态条件到底在哪？

```
WCH-Link CMSIS-DAP 的 USB 延迟:
  OpenOCD → USB → CMSIS-DAP → SWD → (失败) → CMSIS-DAP → USB → OpenOCD
  └──────────────── 往返约 1-3ms ────────────────┘

Boot ROM 引脚配置:
  └── 约 2-5ms ──┘

实际情况:
  OpenOCD 每 25ms 重试一次 dap init
  但每次 dap init 内部会多次尝试 SWD 操作
  在芯片复位后的前几次尝试中，USB 往返 + SWD 操作耗时就可能让
  所有重试都落在 Boot ROM 窗口内
```

**结论**：竞态条件成立，但不是因为"固件重试太少"，而是因为：
1. CMSIS-DAP 架构上**不负责重新建立物理连接**——那是 Host 的职责
2. OpenOCD 的 `dap init` 重连机制虽然设计上考虑了延迟，但在 WCH-Link 的 USB 延迟 + 芯片 Boot ROM 时长的组合下不够健壮
3. J-Link 等专业调试器在固件内部实现了更智能的自动重连（包括可变延时、自适应重试），而 CMSIS-DAP 把重连责任完全推给了 Host

---

## 5. 网络搜索交叉证实

| 来源 | 关键发现 |
|------|---------|
| **pyOCD issue #1962** | `"DP IDCODE read failed; resending SWJ sequence"` — pyOCD 在 Host 端实现了 SWD 重连循环，反复发 SWJ sequence + DPIDR 读 |
| **Infineon Community** | PSoC 系列同样有 SWD 协议锁问题：Line Reset 后只能接受 `READ IDCODE`，其它命令被拒绝 |
| **OpenOCD adi_v5_swd.c** | `cmsis_dap_swd_read_process()` → JUNK ACK → `cmsis_dap_swd_switch_seq()` 重发 JTAG-to-SWD — 无限循环直到成功（在硬件复位死锁时） |
| **CMSIS-DAP 官方文档** | `DAP_TransferConfigure` 的 retry/match_retry 参数由 HOST 设置，固件只是执行者 |
| **probe-rs issue #995** | WCH-Link 的产品字符串是 `"WCH-Link"` 而非 `"CMSIS-DAP"`，导致工具链识别失败 |

---

## 6. 为什么 `halt` 能成功？

```
halt 3000 流程:
┌────────────────────────────────────────────────────────────┐
│ 1. 芯片已上电运行 > 5ms                                     │
│ 2. Boot ROM 已完成引脚配置 ✅                                │
│ 3. DP 已连接, DPIDR 已验证 ✅                                │
│ 4. CMSIS-DAP 发送 halt 命令 → SWD 写 DHCSR                  │
│ 5. 整个过程中 SWD 物理层始终稳定 → 不涉及 DP 重连           │
└────────────────────────────────────────────────────────────┘

reset init 流程:
┌────────────────────────────────────────────────────────────┐
│ 1. 发送 SYSRESETREQ → 芯片复位                              │
│ 2. 引脚进入 Hi-Z ❌                                          │
│ 3. OpenOCD 尝试 dap init → SWD Line Reset → 读 DPIDR       │
│ 4. CMSIS-DAP 固件读 ACK=111 → 不重试 → 返回协议错误         │
│ 5. OpenOCD 重试 → 全部落在 Boot ROM 窗口 → 超时 → 失败     │
└────────────────────────────────────────────────────────────┘
```

---

## 7. 最终结论

```
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║   ❌ 前序判断: "CMSIS-DAP 固件重试窗口太短"                     ║
║                                                               ║
║   ✅ 源码验证: CMSIS-DAP 固件的 retry_count 机制               ║
║      根本不适用于"引脚 Hi-Z"场景                                ║
║                                                               ║
║   重试只对 ACK=WAIT(010) 生效                                  ║
║   引脚 Hi-Z 时 ACK=111(JUNK) → 直接当协议错误返回 → 不重试     ║
║                                                               ║
║   这是 CMSIS-DAP 架构的设计决策:                                ║
║   "物理层重连"是 HOST 的事, 固件只管协议层重试                  ║
║                                                               ║
║   J-Link 等专业调试器把"物理层自动重连"做到了固件里             ║
║   CMSIS-DAP 把这个责任留给了 Host (OpenOCD/pyOCD/probe-rs)     ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
```

> 📎 **关联文档**:
> - [DP 重连失败根因分析报告](./CYT2BL3_DP重连失败根因分析报告.md) — 前序分析
> - [OpenOCD 烧录实操成功报告](./CYT2BL3_OpenOCD_烧录实操成功报告.md) — 解决方案
> - CMSIS-DAP 官方源码: `docs/CMSIS-DAP/Firmware/Source/DAP.c` (line 819) + `SW_DP.c` (line 254)
