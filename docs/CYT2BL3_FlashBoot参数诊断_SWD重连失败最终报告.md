# CYT2BL3 FlashBoot 参数读取与 SWD 重连失败最终诊断报告

> **日期**: 2026-05-05  
> **工具**: probe-rs v0.31.0 (含 CYT2BL3 支持)  
> **操作**: 读取 SFlash TOC2_FLAGS 寄存器诊断 SWD 不可达原因

---

## 1. 操作过程

### 1.1 定位寄存器地址

从 Infineon PDL 源码 (`cyip_sflash_tviibe4m.h`) 确认：

```
SFLASH 基地址:     0x17000000
TOC2_FLAGS 偏移:   0x7DF8
TOC2_FLAGS 地址:   0x17007DF8
```

### 1.2 位域定义

```
TOC2_FLAGS 寄存器 (32-bit):

bits [1:0]   CLOCK_CONFIG     启动时钟配置
bits [4:2]   LISTEN_WINDOW    调试器 Listen Window 时长
bits [6:5]   SWJ_PINS_CTL     SWJ 引脚控制
bits [8:7]   APP_AUTH_CTL     应用认证控制
bits [10:9]  FB_BOOTLOADER_CTL FlashBoot 引导加载控制
```

### 1.3 读取命令

```bash
$ probe-rs read --chip CYT2BL3BAS b32 0x17007DF8 1

17007df8: 00000243
```

---

## 2. 寄存器值解码

```
0x00000243 = 0b 0000 0000 0000 0000 0000 0010 0100 0011

位域解码:
┌──────────────┬───────┬──────┬─────────────────────────────────┐
│ 位域          │ 位    │ 值   │ 含义                            │
├──────────────┼───────┼──────┼─────────────────────────────────┤
│ CLOCK_CONFIG │ [1:0] │ 0b11 │ = 3: Use ROM boot clocks (100MHz)│
│ LISTEN_WINDOW│ [4:2] │ 0b000│ = 0: ★ 20 ms ★                  │
│ SWJ_PINS_CTL │ [6:5] │ 0b10 │ = 2: ★ Enable SWJ pins ★        │
│ APP_AUTH_CTL │ [8:7] │ 0b00 │ = 0: No authentication          │
│ BOOTLOADER   │[10:9] │ 0b00 │ = 0: Normal boot                │
└──────────────┴───────┴──────┴─────────────────────────────────┘
```

---

## 3. 关键结论

### 3.1 SWJ_PINS_CTL = 2 ✅

**SWJ 引脚已启用！** FlashBoot 会在启动过程中将 SWJ 引脚配置为 SWD/JTAG 模式。

### 3.2 LISTEN_WINDOW = 0 → 20ms ✅

**Listen Window 为默认的 20ms！** FlashBoot 配置完 SWJ 引脚后，芯片会在 20ms 窗口内等待调试器连接。

### 3.3 但是——probe-rs 仍然重连失败！

这说明问题**不在 FlashBoot 参数配置上**。SWJ 引脚已启用，Listen Window 有 20ms，参数完全正确。

---

## 4. 那为什么还是失败？——重新分析

### 4.1 时间线重新计算

```
芯片侧 (SYSRESETREQ 后):
═══════════════════════════════════════════════════════
t=0      复位开始
t≈2ms    ROM Boot 完成
t≈5ms    FlashBoot 完成, SWJ 引脚配置完毕, Listen Window 开启
t≈25ms   Listen Window 关闭, 进入用户程序
t>25ms   用户程序运行 (LED blinker, SysTick ISR)


probe-rs 侧 (SYSRESETREQ 后):
═══════════════════════════════════════════════════════
t=0      写 AIRCR → SYSRESETREQ
t≈100ms  【关键延迟】 probe-rs 的内部准备 (USB 通信、状态清理等)
t≈150ms  cortex_m_wait_for_reset() 开始循环
          ├─ 读 DHCSR → NoAcknowledge
          └─ probe.reinitialize() → debug_port_setup()
               ├─ t≈150ms: SWD Line Reset → JTAG-to-SWD → DPIDR Read
               │            ↑
               │            【Listen Window 在 125ms 前就关了!】
               │
               ├─ t≈290ms: 第 2 次 retry
               ├─ t≈430ms: 第 3 次 retry (dormant state)
               └─ ... 直到 t≈735ms: 5 次外层重试用尽
```

### 4.2 🔑 真正的根因：probe-rs 开始重连太晚了！

```
Listen Window:  [5ms =========== 25ms]
                                  ↑
probe-rs 重连:                    ...等待中...    [150ms ====== 735ms]
                                  ↑
                          晚了 125ms！
```

**probe-rs 在 SYSRESETREQ 之后花了约 100-150ms 才到达 `cortex_m_wait_for_reset()` 的重连逻辑。而 Listen Window 在复位后 25ms 就关闭了。差了 125ms！**

### 4.3 为什么 Listen Window 关闭后 SWD 还是不可达？

Listen Window 只是 FlashBoot 给调试器的一个"优先连接窗口"。窗口关闭后，芯片进入用户程序。理论上 SWD 引脚仍应处于 SWD 模式（只要用户程序不重配引脚）。

但实际情况可能是：
1. 用户程序 (LED blinker) 可能通过 SysTick ISR 或 GPIO 操作改变了某些状态
2. CM0+ 进入了 WFI 睡眠（我们的 `delay_ms` 中调用了 `__WFI()`）
3. 芯片进入了某种低功耗状态，影响了 SWD 响应
4. 或者：**SYSRESETREQ 之后，OpenOCD/probe-rs 之前写入的 DEMCR.VC_CORERESET 被清除，核心在复位后直接全速运行，没有停在复位向量**

### 4.4 验证方法

如果要进一步验证"Listen Window 关闭后 SWD 是否还可用"，可以：

```bash
# 1. 先让芯片跑着 (不触发复位)
# 2. 用 probe-rs attach 方式连接
probe-rs attach --chip CYT2BL3BAS

# 3. 手动 reset_and_halt 并观察
```

但 probe-rs 的 `download` 命令强制先 `reset_and_halt`，无法跳过。

---

## 5. 对比 OpenOCD halt 方式的成功原因

```
OpenOCD halt 方式:
═══════════════════════════════════════════════════════
1. init → 连接 SWD → DPIDR ✅  (芯片已上电运行中)
2. halt → 暂停 CM0+ ✅          (SWD 连接保持)
3. flash write → 加载 Flash 算法到 RAM → 执行 → 烧录 ✅
4. 全程不触发 SYSRESETREQ → 不进入 ROM Boot → SWD 不断


probe-rs download 方式:
═══════════════════════════════════════════════════════
1. attach → 连接 SWD → DPIDR ✅
2. reset_and_halt → SYSRESETREQ → ROM Boot → SWD 断开 ❌
3. reconnect 尝试 → 开始太晚 (150ms) → Listen Window 已关闭 ❌
4. 失败
```

---

## 6. 最终诊断总结

```
╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║  TOC2_FLAGS = 0x00000243                                          ║
║                                                                  ║
║  ✅ SWJ_PINS_CTL  = 2 (Enable)  — 引脚会被配置                    ║
║  ✅ LISTEN_WINDOW = 0 (20ms)   — 等待窗口 20ms                    ║
║  ✅ CLOCK_CONFIG  = 3 (100MHz) — 时钟配置正确                     ║
║                                                                  ║
║  ❌ 但不是配置问题——是时序问题！                                   ║
║                                                                  ║
║  Listen Window:  5ms ──── 25ms                                    ║
║  probe-rs 重连:          ...150ms... ──────── 735ms               ║
║                          ↑                                        ║
║                    晚了 ~125ms!                                    ║
║                                                                  ║
║  根因: probe-rs 的 SYSRESETREQ → reconnect 之间有个约 100-150ms   ║
║        的内部处理延迟，而 Listen Window 在 25ms 就关了。           ║
║        Listen Window 关闭后 SWD 是否可用取决于芯片状态，          ║
║        而运行中的用户程序 (WFI/SysTick) 可能导致 SWD 不应。       ║
║                                                                  ║
║  解法: 要么缩短 reconnect 延迟，要么复活 Listen Window，          ║
║        要么学习 OpenOCD——不复位，直接 halt。                      ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
```

---

> 📎 **源码引用**:
> - `cyip_sflash_tviibe4m.h:123` — TOC2_FLAGS @ 0x7DF8
> - `cyip_sflash_tviibe4m.h:283-284` — SWJ_PINS_CTL bits [6:5]
> - `cyip_sflash_tviibe4m.h:281-282` — LISTEN_WINDOW bits [4:2]
> - `sequences.rs:979-980` — RESET_RECOVERY_TIMEOUT = 1s, interval = 5ms
> - `sequences.rs:407-408` — PSOC6 600ms wait comment
>
> 📎 **关联报告**:
> - [probe-rs 烧录失败 Trace 分析](./CYT2BL3_probe-rs_烧录失败Trace分析报告.md)
> - [复位后 SWD 可用时序](./CYT2BL3_复位后SWD可用时序_官方文档分析报告.md)
